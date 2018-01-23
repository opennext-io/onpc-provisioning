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
Description=Configure secondary network interface

[Service]
ExecStart=/usr/local/bin/network-hosts.sh

[Install]
WantedBy=default.target
_EOF
chmod 644 /lib/systemd/system/network-hosts.service
systemctl enable network-hosts.service

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

# Do not exit on errors (calls to grep)
set +e

# Function to install VirtualBox Guest Addditions according to proper version
vbox() {
	echo "Handling VirtualBox platform"
	vboxversion=`dmidecode | grep vboxVer | awk '{print $NF}' | sed -e 's/.*_//'`
	if [ -n "$vboxversion" ]; then
		echo "Found version $vboxversion"
		wget -q -c http://download.virtualbox.org/virtualbox/$vboxversion/VBoxGuestAdditions_${vboxversion}.iso -O /root/VBoxGuestAdditions.iso
		# The software can only be added after 1st boot so that proper kernel is detected and not installation kernel
		cat >/lib/systemd/system/vbox_guest_additions.service <<_EOF
[Unit]
After=sshd.service
Before=systemd-logind.service
Description=Install VirtualBox Guest Additions

[Service]
Type=oneshot
ExecStart=/etc/init.d/configure_vbox_guest_additions.sh
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
_EOF
		chmod 644 /lib/systemd/system/vbox_guest_additions.service
		systemctl enable vbox_guest_additions.service
		# The script itself
		cat >/etc/init.d/configure_vbox_guest_additions.sh <<_EOF
#!/bin/bash

echo "Running \$0"
mkdir -p /tmp/mnt
if [ -r /root/VBoxGuestAdditions.iso ]; then
	mount -o loop /root/VBoxGuestAdditions.iso /tmp/mnt
	/tmp/mnt/VBoxLinuxAdditions.run
fi
echo "Done running \$0"
systemctl disable vbox_guest_additions.service
rm -f /root/VBoxGuestAdditions.iso
reboot
_EOF
		chmod 755 /etc/init.d/configure_vbox_guest_additions.sh
	fi
	echo "Done handling VirtualBox platform"
}

hosttype=`type dmidecode >/dev/null 2>&1 && dmidecode -s system-product-name`
# dmidecode is available
if [ $? -eq 0 ]; then
	case $hosttype in
		VirtualBox) vbox;;
		*)      echo -e "\nWARNING $(basename $0): unsupported platform $hosttype\n";;
	esac
fi

# Eject CD-ROM to avoid boot loop
eject

exit 0
