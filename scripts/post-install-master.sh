#!/bin/bash

SECOND_IF_IP_PREFIX=${1:-20.20.20}

# Exits on errors
set -ex
exec > >(tee -i /var/log/"$(basename "$0" .sh)"_"$(date '+%Y-%m-%d_%H-%M-%S')".log) 2>&1

# Retrieve proxy information from installation
proxy=`grep Acquire::http::Proxy /etc/apt/apt.conf | sed -e 's/";$//' | awk -F/ '{print $3}'`
if [ -n "$proxy" ]; then
	echo -e "http_proxy=http://${proxy}/\nftp_proxy=ftp://${proxy}/\nhttps_proxy=https://${proxy}/\nno_proxy=\"localhost,127.0.0.1,${SECOND_IF_IP_PREFIX}.0/24\"" >>/etc/environment
fi

# Put banner in /etc/issue* files
for f in /etc/issue*; do
	sed -i '/^Ubuntu/i master host/machine\n' $f
done
if [ -d /etc/update-motd.d ]; then
	echo -e '#!/bin/sh\nprintf "\\nmaster host/machine\\n\\n"' >/etc/update-motd.d/20-machine-name
	chmod 755 /etc/update-motd.d/20-machine-name
	rm -f /etc/update-motd.d/10-help-text
fi

# Configure ntp service
if [ -f /etc/ntp.conf ]; then
	sed -i -e "/^#broadcast /a broadcast ${SECOND_IF_IP_PREFIX}.255" \
		-e "/^# \/etc\/ntp.conf,/a \\ninterface ignore wildcard\ninterface listen ${SECOND_IF_IP_PREFIX}.1\ninterface listen 127.0.0.1\ninterface listen ::1" \
		/etc/ntp.conf
fi

# IPv6 disabling can be done in preseed but is less "generic"
# d-i debian-installer/add-kernel-opts string ipv6.disable=1 ...
# Disable IPv6 if not activated
if [ ! -d /proc/sys/net/ipv6 ]; then
	ipv6_sed_filter="-e /.*::.*/d -e /^#.*IPv6.*/d"
	sed -i -e 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="ipv6.disable=1 /' /etc/default/grub
	update-grub
fi

# Enable extra modules
echo -e 'bonding\n8021q' >>/etc/modules

# Set hostname
echo "master" >/etc/hostname

# Remove dummy network entries and potentially IPv6 entries from hosts file and make this the default hosts template
sed -i.orig $ipv6_sed_filter -e '/127.0.1.1/d' -e '/^$/d' /etc/hosts
cp /etc/hosts /etc/hosts.tmpl

# Configure secondary interface if any and enable IP forwarding
itf2=`ip link show | egrep -v 'lo: |state UP ' | egrep '^[1-9]' | cut -d: -f2 | tr -d ' '`
if [ -n "$itf2" ]; then
	cat >/etc/network/interfaces.d/$itf2 <<_EOF
# The secondary network interface
auto $itf2
iface $itf2 inet static
	address ${SECOND_IF_IP_PREFIX}.1
	netmask 255.255.255.0
_EOF
	sed -i -e 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
fi

# /etc/hosts update script to be launched at each boot via service
cat >/usr/local/bin/network-hosts.sh <<_EOF
#!/bin/bash

if [ ! -f /etc/hosts.tmpl ]; then
	echo -e "127.0.0.1\tlocalhost" >/etc/hosts.tmpl
fi
host=\`cat /etc/hostname\`
fqdn=\${host}.vagrantup.com
(echo "# Dynamically added at startup by \$0 script" ; \
 ip a | awk -v h=\${fqdn}=\${host},\${host}-priv 'BEGIN{n=0;split(h,a,",");} /^[1-9][0-9]*: .* state UP/{ok=1;next} /^[1-9]/{ok=0} ok && /inet /{split(\$2,b,"/");n++;printf "%s\t%s\n",b[1],a[n]}' ; \
 echo '# Standard entries' ; \
 cat /etc/hosts.tmpl ) | sed -e 's/=/ /g' >/etc/hosts
_EOF
chmod 755 /usr/local/bin/network-hosts.sh

cat >/lib/systemd/system/network-hosts.service <<_EOF
[Unit]
After=sshd.service

[Service]
ExecStart=/usr/local/bin/network-hosts.sh

[Install]
WantedBy=default.target
_EOF
chmod 644 /lib/systemd/system/network-hosts.service
systemctl enable network-hosts.service

# Configure apt-cacher-ng if present
if [ -f /etc/apt-cacher-ng/acng.conf ]; then
	sed -i -e 's/^# Port:3142/Port:9999/' /etc/apt-cacher-ng/acng.conf
	# Bootsrap with local files
	#mv /var/cache/apt/archives /var/cache/apt-cacher-ng/_import
	rsync -a /var/cache/apt/archives/ /var/cache/apt-cacher-ng/_import
	chown -R apt-cacher-ng: /var/cache/apt-cacher-ng/_import
	cat >/etc/apt/apt.conf.d/01acng <<_EOF
Acquire::http {
	Proxy "http://127.0.0.1:9999";
	};
_EOF
	#apt-get update && apt-get clean
fi

# Configure apache2 if present so that it does not conflict with nginx:80/443
if [ -d /etc/apache2 ]; then
	if [ -f /etc/apache2/ports.conf ]; then
		sed -i -e 's/80/9080/' -e 's/443/9443/' /etc/apache2/ports.conf
	fi
	if [ -f /etc/apache2/sites-available/000-default.conf ]; then
		sed -i -e 's/:80>$/:9080>/' /etc/apache2/sites-available/000-default.conf
	fi
	if [ -f /etc/apache2/sites-available/default-ssl.conf ]; then
		sed -i -e 's/:443>$/:9443>/' /etc/apache2/sites-available/default-ssl.conf
	fi
	if [ -f /etc/apache2/sites-available/default-tls.conf ]; then
		sed -i -e 's/:443>$/:9443>/' /etc/apache2/sites-available/default-tls.conf
	fi
fi

# Configure squid if present
if [ -f /etc/squid/squid.conf ]; then
	sed -i -e 's?^#acl localnet src 20.0.0.0/?acl localnet src 20.0.0.0/?' \
		-e 's?^#http_access allow localnet?http_access allow localnet?' \
		-e 's/^# maximum_object_size 4 MB/maximum_object_size 256 MB/' \
		-e 's?^#cache_dir ufs /var/spool/squid .*?cache_dir ufs /var/spool/squid 16384 16 256?' \
		/etc/squid/squid.conf
fi

# Configure squid-deb-proxy if present
if [ -f /etc/squid-deb-proxy/squid-deb-proxy.conf ]; then
	sed -i	-e 's/^#http_access allow !to_archive_mirrors/http_access allow !to_archive_mirrors/' \
		-e 's/^http_access deny !to_archive_mirrors/#http_access deny !to_archive_mirrors/' \
		-e 's/^cache deny !to_archive_mirrors/#cache deny !to_archive_mirrors/' \
		/etc/squid-deb-proxy/squid-deb-proxy.conf
fi

# Configure dnsmask if present
if [ -d /etc/dnsmasq.d ]; then
	# Create PXE boot directories
	mkdir -p /var/tftp/preseed
	cd /var/tftp
	# Download appropriate official archives
	for f in netboot.tar.gz mini.iso; do
		wget -q http://archive.ubuntu.com/ubuntu/dists/xenial/main/installer-amd64/current/images/netboot/$f -O /var/tftp/xenial_$f
	done
	# Extract, rename and configure pxeboot archive
	tar zxf xenial_netboot.tar.gz
	rm -f ldlinux.c32 pxelinux.0 pxelinux.cfg
	mv ubuntu-installer xenial-installer
	ln -s xenial-installer/amd64/pxelinux.0
	ln -s xenial-installer/amd64/pxelinux.cfg
	ln -s xenial-installer/amd64/boot-screens/ldlinux.c32
	for f in `find xenial-installer -type f -print | xargs grep ubuntu-installer | awk -F: '{print $1}' | sort | uniq`; do
		sed -i -e 's/ubuntu-installer/xenial-installer/g' $f
	done
	wget -q http://www.olivierbourdon.com/preseed_slaves.cfg -O preseed/preseed.cfg
	(cd preseed ; find preseed.cfg -print0 | cpio --create --null -H newc --quiet) | gzip -9 >preseed/pfffui.gz
	# Insert 5sec timeout
	sed -i -e 's/^timeout 0/timeout 50/' pxelinux.cfg/default
	cp xenial-installer/amd64/boot-screens/txt.cfg xenial-installer/amd64/boot-screens/txt-orig.cfg
	# Keep only 1st menu entry
	awk '/^label /{n++} n>1{exit} {print}' xenial-installer/amd64/boot-screens/txt-orig.cfg >xenial-installer/amd64/boot-screens/txt.cfg
	sed -i -e 's/ install/ xenial-install/g' -e 's? --- quiet?,preseed/pfffui.gz --- quiet priority=critical?' xenial-installer/amd64/boot-screens/txt.cfg

	# Enable config files ending in .conf in appropriate subdir to be used
	sed -i -e 's?^#conf-dir=/etc/dnsmasq.d/,\*.conf?conf-dir=/etc/dnsmasq.d/,\*.conf?' /etc/dnsmasq.conf

	cat >/etc/dnsmasq.d/deploy.conf <<_EOF
listen-address=127.0.0.1,${SECOND_IF_IP_PREFIX}.1
domain-needed
bogus-priv
no-resolv
local=/vagrantup.com/
domain=vagrantup.com
server=8.8.8.8
server=8.8.4.4

dhcp-authoritative
dhcp-range=vagrantup.com,${SECOND_IF_IP_PREFIX}.100,${SECOND_IF_IP_PREFIX}.199,255.255.255.0,1h
dhcp-option=option:router,${SECOND_IF_IP_PREFIX}.1
dhcp-option=option:dns-server,0.0.0.0
dhcp-option=option:domain-search,vagrantup.com

enable-tftp
tftp-root=/var/tftp
dhcp-vendorclass=set:pxe,PXEClient
dhcp-boot=tag:pxe,/pxelinux.0
_EOF

	# Configure rsyslog to use dedicated file for dnsmsasq
	echo -e "# Log kernel generated dnsmasq log messages to file\n:programname, isequal, "dnsmasq" /var/log/dnsmasq.log" >/etc/rsyslog.d/70-dnsmasq.conf
fi

# Vagrant user priviledges
echo -e 'vagrant\tALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/vagrant_user

# Populate vagrant user home with OSA git repositories and ssh keys
su - vagrant -c 'touch .sudo_as_admin_successful && mkdir -p .cache && chmod 700 .cache && touch .cache/motd.legal-displayed && \
 	mkdir -p .ssh && chmod 700 .ssh && ssh-keygen -b 2048 -t rsa -f .ssh/id_rsa -N "" && sed -i -e "s/@ubuntu/@master/" .ssh/id_rsa.pub && cp .ssh/id_rsa.pub .ssh/authorized_keys && \
 	wget -q -O - http://www.olivierbourdon.com/ssh-keys >>.ssh/authorized_keys && \
	wget -q -O - https://raw.githubusercontent.com/hashicorp/vagrant/master/keys/vagrant.pub >>.ssh/authorized_keys && \
 	echo -e "Host ${SECOND_IF_IP_PREFIX}.*\nUser vagrant\nStrictHostKeyChecking no\nUserKnownHostsFile /dev/null" >.ssh/config'
if [ -d /var/www/html ] && [ -f ~vagrant/.ssh/id_rsa.pub ]; then
	cp ~vagrant/.ssh/id_rsa.pub /var/www/html/ssh-keys
fi

# Eject CD-ROM to avoid boot loop
eject

exit 0
