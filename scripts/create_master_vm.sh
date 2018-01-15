#!/bin/bash

virtprovider=${VIRT:-vbox}
vmname=${MASTER_VM_NAME:-"master"}
vmmem=${MASTER_VM_MEM:-2048}
vmcpus=${MASTER_VM_CPUS:-2}
vmdisk=${MASTER_VM_DISK:-10240}
preseed=${PRESEED_URL:-http://www.olivierbourdon.com/preseed_master.cfg}
noipv6=${NOIPV6:+" ipv6.disable=1"}
httpproxy=${PROXY:-""}
passwd=${PASSWD:-"vagrant"}

# Check virtuzalization mode
case $virtprovider in
	vbox)	;;
	kvm)	;;
	*)	echo -e "\nERROR $(basename $0): unsupported virtualization $virtprovider\n"; exit 1;;
esac

# This script can run only on MacOSX and Linux
# The readlink command needs to support -f option
os=$(uname -s)
case $os in
	Darwin)	linkcmd=greadlink;;
	Linux)	linkcmd=readlink;;
	*)	echo -e "\nERROR $(basename $0): unsupported platform $os\n"; exit 1;;
esac

# Check command line arguments
if [ $# -ne 1 ]; then
	echo -e "\nUsage: $(basename $0) <path>/<bootable-ISO>\n"
	exit 1
fi
echo $1 | egrep -q '\.iso$'
if [ $? -ne 0 ]; then
	echo -e "\nUsage: $(basename $0) <path>/<bootable-ISO> must end with .iso\n"
	exit 1
fi

getcmd() {
	cmds="$*"
	while [ -n "$1" ]; do
		type "$1" >/dev/null 2>&1
		if [ $? -eq 0 ]; then
			echo $1
			return
		fi
		shift
	done
	echo -e "\nERROR $(basename $0): please install any of missing command(s): $cmds\n"
	exit 1
}

# Exit on errors
set -e

# Complete path of target ISO
lcmd=$(getcmd $linkcmd)
vmiso=$($lcmd -f $1)
# Check validity of ISO
if [ ! -r $1 ]; then
	echo -e "\nERROR $(basename $0): file $1 does not exists or is not readable !!!\n"
	echo "Trying to rebuild it. Downloading ..."
	# Fetch some required commands
	urlcmd=$(getcmd curl wget)
	isocmd=$(getcmd xorriso)
	# Set default vagrant user password
	if [ -n "$passwd" ]; then
		venvcmd=$(getcmd virtualenv)
		if [ ! -r ./passwd/bin/activate ]; then
			$venvcmd passwd
		fi
		. ./passwd/bin/activate
		pip install -U pip passlib
		vpasswd=$(python -c "from passlib.hash import sha512_crypt; import getpass,string,random; \
			print sha512_crypt.using(salt=''.join([random.choice(string.ascii_letters + string.digits) for _ in range(16)]),rounds=5000).hash(\"${passwd}\")")
		pass=" passwd/user-password-crypted=$vpasswd"
	fi
	# Retrieve official ISO from net
	tmpiso=/tmp/mini.iso
	tmpdir=/tmp/mini
	isourl=http://archive.ubuntu.com/ubuntu/dists/xenial/main/installer-amd64/current/images/netboot/mini.iso
	if [ "$urlcmd" == "wget" ]; then
		$urlcmd -nc -q --show-progress $isourl -O $tmpiso
	else
		$urlcmd -C - --progress-bar $isourl -o $tmpiso
	fi
	# Cleanup
	sudo rm -rf $tmpdir
	# Extract ISO
	echo "Extracting ..."
	$isocmd -osirrox on -indev $tmpiso -extract / $tmpdir >/dev/null 2>&1
	chmod +w $tmpdir
	# Extracting ISO MBR
	dd if=$tmpiso bs=512 count=1 of=$tmpdir/isohdpfx.bin >/dev/null 2>&1
	echo "Modifying ..."
	# Boot menu timeout changed to 3 seconds
	sed -i "" -e 's?timeout 0?timeout 30?' $tmpdir/isolinux.cfg
	# Menu item update
	if [ -n "$httpproxy" ]; then
		proxy=" mirror/http/proxy=${httpproxy}"
	fi
	addonsflags="preseed/url=${preseed} netcfg/choose_interface=auto locale=en_US keyboard-configuration/layoutcode=us priority=critical${noipv6}${proxy}${pass}"
	sed -i "" -e 's?default install?default net?' -e 's?label install?label net?' \
		-e 's?menu label ^Install?menu label ^Net Install (fully automated)?' \
		-e "s?append vga=788 initrd=initrd.gz --- quiet?append vga=788 initrd=initrd.gz $addonsflags --- quiet?" \
		$tmpdir/txt.cfg
	echo "Rebuilding ..."
	(cd $tmpdir ; $isocmd -as mkisofs -isohybrid-mbr isohdpfx.bin -c boot.cat -b isolinux.bin -no-emul-boot \
		-boot-load-size 4 -boot-info-table -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot -isohybrid-gpt-basdat \
		-o $vmiso . >/dev/null 2>&1)
	# Cleanup
	sudo rm -rf $tmpdir $tmpiso
fi

# Do not exit on errors
set +e

# Retrieve 1st active network interface
activenetitf=$(ifconfig | awk '/UP,/{itf=$1}/inet /{print itf,$2}' | egrep -v '^lo|^vbox|^utun' | sed -e 's/: .*//' | head -1)

if [ "$virtprovider" == "vbox" ]; then
	# Check if VM already exists
	VBoxManage list vms | egrep -q "^\"${vmname}\" "
	if [ $? -eq 0 ]; then
		echo -e "\nERROR $(basename $0): VirtualBox VM with name [$vmname] already exists !!!\n"
		exit 1
	fi

	netitf=$(VBoxManage list bridgedifs | grep $activenetitf | grep '^Name: ' | sed -e 's/Name: *//')

	# Exit on errors
	set -e

	# Base of VM is Ubuntu 64bits
	vmuuid=$(VBoxManage createvm --name $vmname --ostype Ubuntu_64 --register | egrep "^UUID: " | awk '{print $NF}')
	echo "Created $vmname: $vmuuid"
	# VM basics
	VBoxManage modifyvm $vmname --memory $vmmem --cpus $vmcpus --boot1 dvd --boot2 disk --boot3 none --audio none --usb off --rtcuseutc on --vram 16 --pae off
	# VM networks
	VBoxManage modifyvm $vmname --nic1 bridged --bridgeadapter1 "$netitf" --nic2 intnet
	# VM CDROM/IDE
	VBoxManage storagectl $vmname --name IDE --add ide --controller PIIX4
	VBoxManage storageattach $vmname --storagectl IDE --type dvddrive --port 1 --device 0 --medium "$vmiso"
	# VM HDD
	VBoxManage storagectl $vmname --name SATA --add sata --controller IntelAHCI --portcount 1 --hostiocache off
	eval $(VBoxManage showvminfo $vmname --machinereadable | grep ^CfgFile=)
	vmdir=$(dirname "$CfgFile")
	vmdiskuuid=$(VBoxManage createmedium disk --filename "$vmdir"/$vmname --size $vmdisk | egrep "^.* UUID: " | awk '{print $NF}')
	VBoxManage storageattach $vmname --storagectl SATA --type hdd --port 0 --device 0 --medium "$vmdir"/$vmname.vdi
	# Start VM
	VBoxManage startvm $vmname
elif [ "$virtprovider" == "kvm" ]; then
	# Check if VM already exists
	virsh list --all --name | egrep -q "^${vmname}$"
	if [ $? -eq 0 ]; then
		echo -e "\nERROR $(basename $0): VirtualBox VM with name [$vmname] already exists !!!\n"
		exit 1
	fi

	echo -e "\nNot implemented yet !!!\n"
fi

exit 0
