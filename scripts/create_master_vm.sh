#!/bin/bash

# Do not exit on errors
set +e

# This script can run only on MacOSX and Linux
# The readlink command needs to support -f option
os=$(uname -s)
case $os in
	Darwin)	linkcmd=greadlink;;
	Linux)	linkcmd=readlink;;
	*)	echo -e "\nERROR $(basename $0): unsupported platform $os\n"; exit 1;;
esac

CMDDIR=$(dirname $(dirname $($linkcmd -f $0)))

# VM parameters
virtprovider=${VIRT:-vbox}
vmname=${MASTER_VM_NAME:-"master"}
vmmem=${MASTER_VM_MEM:-2048}
vmcpus=${MASTER_VM_CPUS:-2}
vmdisk=${MASTER_VM_DISK:-10240}

# ISO parameters
preseed=${PRESEED_URL:-http://www.olivierbourdon.com/preseed_master.cfg}
noipv6=${NOIPV6:+"1"}
httpproxy=${PROXY:-""}
passwd=${PASSWD:-"vagrant"}

# Check virtuzalization mode
case $virtprovider in
	vbox)	;;
	kvm)	;;
	*)	echo -e "\nERROR $(basename $0): unsupported virtualization $virtprovider\n"; exit 1;;
esac

# Check command line arguments
if [ $# -ne 0 ]; then
	echo -e "\nUsage: $(basename $0)\n"
	exit 1
fi

getcmd() {
	cmds="$*"
	while [ -n "$1" ]; do
		type "$1" >/dev/null 2>&1
		if [ $? -eq 0 ]; then
			echo $1
			return 0
		fi
		shift
	done
	echo -e "\nERROR $(basename $0): please install any of missing command(s): $cmds\n"
	return 1
}

iso=$CMDDIR/isos/custom.iso
# Check existence of ISO
if [ ! -r $iso ]; then
	echo "Using docker to build custom ISO ..."
	# Fetch some required commands
	dockercmd=$(getcmd docker)
	if [ $? -ne 0 ]; then
		echo -e "$dockercmd"
		exit 1
	fi
	if [ ! -d $CMDDIR/docker/build_custom_iso ]; then
		echo -e "\nERROR $(basename $0): missing dir $CMDDIR/docker/build_custom_iso\n"
		exit 1
	fi
	tag=custom-iso:latest
	(cd $CMDDIR/docker/build_custom_iso ; docker build -t $tag .)
	dir=/tmp
	mkdir -p $(dirname $iso)
	opts=""
	if [ -n "$preseed" ]; then
		opts="-s $preseed "
	fi
	if [ -n "$noipv6" ]; then
		opts="${opts}-i "
	fi
	if [ -n "$httpproxy" ]; then
		opts="${opts}-p $httpproxy "
	fi
	if [ -n "$passwd" ]; then
		opts="${opts}-w $passwd "
	fi
	if [ -n "$opts" ]; then
		opts=$(echo "$opts" | sed -e 's/  *$//')
		opts="-e opts=\"$opts\""
	fi
	eval docker run -t $opts -e "iso=$dir/custom.iso" -v $(dirname $iso):$dir $tag
fi

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
	VBoxManage storageattach $vmname --storagectl IDE --type dvddrive --port 1 --device 0 --medium "$iso"
	# VM HDD
	VBoxManage storagectl $vmname --name SATA --add sata --controller IntelAHCI --portcount 1 --hostiocache off
	eval $(VBoxManage showvminfo $vmname --machinereadable | grep ^CfgFile=)
	vmdir=$(dirname "$CfgFile")
	vmdiskuuid=$(VBoxManage createmedium disk --filename "$vmdir"/$vmname --size $vmdisk | egrep "^.* UUID: " | awk '{print $NF}')
	VBoxManage storageattach $vmname --storagectl SATA --type hdd --port 0 --device 0 --medium "$vmdir"/$vmname.vdi
	# Start VM
	VBoxManage startvm $vmname
	sleep 5
	# Do not exit on errors (use of grep)
	set +e
	# Expressed in minutes
	i=${TIMEOUT:-30}
	# Because sleep step below is 15s
	i=$((i*4))
	while true; do
		if [ $(VBoxManage guestproperty enumerate $vmname | wc -l) -eq 1 ]; then
			echo "VM $vmname was killed or is not running any more"
			exit 1
		fi
		netinfos=$(VBoxManage guestproperty enumerate $vmname | grep '/VirtualBox/GuestInfo/Net/0/V4/IP')
		if [ -n "$netinfos" ]; then
			break
		fi
		i=$((i-1))
		if [ $i -eq 0 ]; then
			echo "VM $vmname took too long to start"
			exit 1
		fi
		echo -en "\rWaiting a bit longer ... ($i)"
		sleep 15
	done
	ip=$(echo $netinfos | awk '{print $4}' | sed -e 's/,.*$//')
	echo -e "\n\nAll done, VM $vmname IP is $ip"
	echo -e "[master]\n$ip\n" > $CMDDIR/ansible/inventory/master
	type ansible >/dev/null 2>&1
	if [ $? -eq 0 ]; then
		echo -e "\n\nTry running the following: ansible -i ansible/inventory/master -m ping all -u vagrant\n"
	fi
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
