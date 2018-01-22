#!/bin/bash

tmpiso=/tmp/mini.iso
tmpdir=/tmp/mini

# Cleanup function called on any exit condition
trap cleanup EXIT
cleanup() {
	# Cleanup
	echo "Cleaning up ..."
	rm -rf $tmpdir $tmpiso
}

usage() {
	echo -e "\nUsage: $(basename $0) [-i] [-p proxy-url] [-s preseed-url] [-w admin-user-passwd] <path>/<bootable-ISO>\n"
}

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

while getopts "h?ip:s:w:" opt; do
    case "$opt" in
    h|\?)
        usage
        exit 0
        ;;
    i)  noipv6=1
        ;;
    p)  httpproxy=$OPTARG
        ;;
    s)  preseed=$OPTARG
        ;;
    w)  passwd=$OPTARG
        ;;
    *)	echo "Unknown option $opt"
	usage
	exit 1
	;;
    esac
done

shift $((OPTIND-1))

[ "$1" = "--" ] && shift

preseed=${preseed:-http://www.olivierbourdon.com/preseed_master.cfg}
noipv6=${noipv6:+" ipv6.disable=1"}
httpproxy=${httpproxy:-""}
passwd=${passwd:-"vagrant"}

# Check command line arguments
if [ $# -ne 1 ]; then
	usage
	exit 1
fi
echo $1 | egrep -q '\.iso$'
if [ $? -ne 0 ]; then
	echo -e "\nUsage: $(basename $0) <path>/<bootable-ISO> must end with .iso\n"
	exit 1
fi

# Check existence of ISO
if [ -r $1 ]; then
	echo "$i already exist. Nothing done"
	exit 0
fi
# Complete path of target ISO
vmiso=$(readlink -f $1)
if [ -z "$vmiso" ]; then
	touch $1
	vmiso=$(readlink -f $1)
	rm -f $1
fi

# Exit on errors
set -e

echo -e "\nERROR $(basename $0): file $1 does not exists or is not readable !!!\n"
echo "Trying to rebuild it. Downloading ..."
# Set default vagrant user password
if [ -n "$passwd" ]; then
	if [ ! -r ./passwd/bin/activate ]; then
		virtualenv passwd
	fi
	. ./passwd/bin/activate
	pip install -U pip passlib
	vpasswd=$(python -c "from passlib.hash import sha512_crypt; import getpass,string,random; \
		print sha512_crypt.using(salt=''.join([random.choice(string.ascii_letters + string.digits) for _ in range(16)]),rounds=5000).hash(\"${passwd}\")")
	pass=" passwd/user-password-crypted=$vpasswd"
fi
# Retrieve official ISO from net
isourl=http://archive.ubuntu.com/ubuntu/dists/xenial/main/installer-amd64/current/images/netboot/mini.iso
http_proxy=$httpproxy wget -c -q --show-progress $isourl -O $tmpiso
# Cleanup
rm -rf $tmpdir
# Extract ISO
echo "Extracting ..."
xorriso -osirrox on -indev $tmpiso -extract / $tmpdir >/dev/null 2>&1
chmod +w $tmpdir
# Extracting ISO MBR
dd if=$tmpiso bs=512 count=1 of=$tmpdir/isohdpfx.bin >/dev/null 2>&1
echo "Modifying ..."
# Boot menu timeout changed to 3 seconds
sed -i -e 's?timeout 0?timeout 30?' $tmpdir/isolinux.cfg
# Menu item update
if [ -n "$httpproxy" ]; then
	proxy=" mirror/http/proxy=${httpproxy}"
fi
addonsflags="preseed/url=${preseed} netcfg/choose_interface=auto locale=en_US keyboard-configuration/layoutcode=us priority=critical${noipv6}${proxy}${pass}"
sed -i -e 's?default install?default net?' -e 's?label install?label net?' \
	-e 's?menu label ^Install?menu label ^Net Install (fully automated)?' \
	-e "s?append vga=788 initrd=initrd.gz --- quiet?append vga=788 initrd=initrd.gz $addonsflags --- quiet?" \
	$tmpdir/txt.cfg
echo "Rebuilding ..."
(cd $tmpdir ; xorriso -as mkisofs -isohybrid-mbr isohdpfx.bin -c boot.cat -b isolinux.bin -no-emul-boot \
	-boot-load-size 4 -boot-info-table -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot -isohybrid-gpt-basdat \
	-o $vmiso . >/dev/null 2>&1)
find $tmpdir -type d | xargs chmod +w

exit 0
