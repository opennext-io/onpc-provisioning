#!/bin/bash

# Exit on errors
set -e

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
vmname=${SLAVE_VM_NAME:-"slave"}
vmmem=${SLAVE_VM_MEM:-512}
vmcpus=${SLAVE_VM_CPUS:-1}
vmdisk=${SLAVE_VM_DISK:-248}
maxvms=${MAX_SLAVES:-5}

# Check virtuzalization mode
case $virtprovider in
	vbox)	;;
	kvm)	;;
	*)	echo -e "\nERROR $(basename $0): unsupported virtualization $virtprovider\n"; exit 1;;
esac

# Check command line arguments
if [ $# -ne 1 ]; then
	echo -e "\nUsage: $(basename $0) #nb-vms-to-launch\n"
	exit 1
fi

if ! echo "$1" | egrep -q '^[1-9][0-9]*$'; then
	echo -e "\nUsage: $(basename $0) #nb-vms-to-launch\n\n\tinvalid integer $1\n"
	exit 1
fi
if [ $1 -gt $maxvms ]; then
	echo -e "\nUsage: $(basename $0) #nb-vms-to-launch\n\n\tinteger too big $1, $maxvms maximum\n"
	exit 1
fi

if [ "$virtprovider" == "vbox" ]; then
	for i in $(seq 1 $1); do
		lvmname=${vmname}-$i
		# Check if VM already exists
		if VBoxManage list vms | egrep -q "^\"${lvmname}\" "; then
			echo -e "\nERROR $(basename $0): VirtualBox VM with name [$lvmname] already exists !!!\n"
			exit 1
		fi

		# Base of VM is Ubuntu 64bits
		vmuuid=$(VBoxManage createvm --name $lvmname --ostype Ubuntu_64 --register | egrep "^UUID: " | awk '{print $NF}')
		echo "Created $lvmname: $vmuuid"
		# VM basics
		VBoxManage modifyvm $lvmname --memory $vmmem --cpus $vmcpus --boot1 net --boot2 disk --boot3 none --audio none --usb off --rtcuseutc on --vram 16 --pae off
		# VM networks
		VBoxManage modifyvm $lvmname --nic1 intnet
		# VM HDD
		VBoxManage storagectl $lvmname --name SATA --add sata --controller IntelAHCI --portcount 1 --hostiocache off
		eval $(VBoxManage showvminfo $lvmname --machinereadable | grep ^CfgFile=)
		vmdir=$(dirname "$CfgFile")
		vmdiskuuid=$(VBoxManage createmedium disk --filename "$vmdir"/$lvmname --size $vmdisk | egrep "^.* UUID: " | awk '{print $NF}')
		VBoxManage storageattach $lvmname --storagectl SATA --type hdd --port 0 --device 0 --medium "$vmdir"/$lvmname.vdi
		# Start VM
		VBoxManage startvm $lvmname
	done
elif [ "$virtprovider" == "kvm" ]; then
	echo -e "\nNot implemented yet !!!\n"
fi

exit 0
