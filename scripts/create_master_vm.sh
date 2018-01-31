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
vmname=${MASTER_VM_NAME:-"master"}
vmmem=${MASTER_VM_MEM:-2048}
vmcpus=${MASTER_VM_CPUS:-2}
vmdisk=${MASTER_VM_DISK:-10240}

# ISO parameters
preseed=${PRESEED_URL:-http://www.olivierbourdon.com/preseed_master.cfg}
noipv6=${NOIPV6:+"1"}
httpproxy=${PROXY:-""}
username=${ADMINUSER:-"vagrant"}
passwd=${ADMINPASSWD:-"vagrant"}
domainname=${DOMAIN:-"vagrantup.com"}

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

checkstring() {
	if [ -z "$2" ] && [ -n "$3" ] && ! $3; then
		echo -e "\nUsage: $(basename $0): $1 variable error\n\n\tcan not be empty\n"
		exit 1
	fi
	if [ -n "$4" ] && ! $(echo -e "$2" | egrep -q $4); then
		echo -e "\nUsage: $(basename $0): $1 variable error\n\n\tinvalid input, does not match valid regexp\n"
		exit 1
	fi
	if [ -n "$5" ] && echo -e "$2" | egrep -q $5; then
		echo -e "\nUsage: $(basename $0): $1 variable error\n\n\tinvalid input, matches some invalid regexp\n"
		exit 1
	fi
}

checkstring ADMINUSER   "$username"  false '^[A-Za-z][A-Za-z0-9]*$' '^.*\s.*$|^root$'
checkstring ADMINPASSWD "$passwd"    false '^[A-Za-z0-9/@_=+-]+$' '^.*\s.*$'
checkstring PROXY       "$httpproxy" true

checknumber() {
	if ! echo "$2" | egrep -q '^[1-9][0-9]*$'; then
		echo -e "\nUsage: $(basename $0): $1 variable error\n\n\tinvalid integer $2\n"
		exit 1
	fi
	if [ -n "$3" ] && [ $2 -lt $3 ]; then
		echo -e "\nUsage: $(basename $0) $1 variable error\n\n\t$2 too small, must be greater than $3\n"
		exit 1
	fi
	if [ -n "$4" ] && [ $2 -gt $4 ]; then
		echo -e "\nUsage: $(basename $0) $1 variable error\n\n\t$2 too big, must be smaller than $3\n"
		exit 1
	fi
	if [ -n "$5" ] && [ $(expr $2 % $5) -ne 0 ]; then
		echo -e "\nUsage: $(basename $0) $1 variable error\n\n\tinvalid integer $2, must be multiple of $5\n"
		exit 1
	fi
}

checknumber MASTER_VM_MEM  $vmmem  512  ""  8
checknumber MASTER_VM_DISK $vmdisk 5120 "" 1024
checknumber MASTER_VM_CPUS $vmcpus 1    16  1

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
	echo -e "\nERROR $(basename $0): please install any of missing command(s): $cmds\n" >/dev/tty
	return 1
}

iso=$CMDDIR/isos/custom.iso
# Check existence of ISO
if [ ! -r $iso ]; then
	echo "Using docker to build custom ISO ..."
	# Fetch some required commands
	dockercmd=$(getcmd docker)
	if [ ! -d $CMDDIR/docker/build_custom_iso ]; then
		echo -e "\nERROR $(basename $0): missing dir $CMDDIR/docker/build_custom_iso\n"
		exit 1
	fi
	tag=custom-iso:latest
	if ! docker images $tag | grep -q custom; then
		(cd $CMDDIR/docker/build_custom_iso ; docker build -t $tag .)
	fi
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
	if [ -n "$vmname" ]; then
		opts="${opts}-n $vmname "
	fi
	if [ -n "$domainname" ]; then
		opts="${opts}-d $domainname "
	fi
	if [ -n "$username" ]; then
		opts="${opts}-u $username "
	fi
	if [ -n "$opts" ]; then
		opts=$(echo "$opts" | sed -e 's/  *$//')
		opts="-e opts=\"$opts\""
	fi
	if ! eval docker run -t $opts -e "iso=$dir/custom.iso" -v $(dirname $iso):$dir $tag; then
		echo -e "\nERROR $(basename $0): can not built iso\n"
		exit 1
	fi
fi

# Retrieve 1st active network interface
if type ip >/dev/null 2>&1; then
	cmd="ip a | awk '/,*UP,*/{itf=\$2}/inet /{print itf,\$2}'"
else
	cmd="ifconfig | awk '/,*UP,*/{itf=\$1}/inet /{print itf,\$2}'"
fi
activenetitf=$(eval $cmd | egrep -v '^lo|^vbox|^utun|^docker|^openstack|^lxcbr|^virbr' | sed -e 's/: .*//' | head -1)
if [ -z "$activenetitf" ]; then
	echo -e "\nERROR $(basename $0): can not find network interface\n"
	exit 1
fi

if [ "$virtprovider" == "vbox" ]; then
	# Fetch some required commands
	vboxcmd=$(getcmd VBoxManage)
	# Check if VM already exists
	if VBoxManage list vms | egrep -q "^\"${vmname}\" "; then
		echo -e "\nERROR $(basename $0): VirtualBox VM with name [$vmname] already exists !!!\n"
		exit 1
	fi

	netitf=$(VBoxManage list bridgedifs | grep $activenetitf | grep '^Name: ' | sed -e 's/Name: *//')

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
	# Expressed in minutes
	i=${TIMEOUT:-30}
	# Because sleep step below is 15s
	i=$((i*4))
	while true; do
		if [ $(VBoxManage guestproperty enumerate $vmname 2>/dev/null | wc -l) -le 1 ]; then
			echo "VM $vmname was killed, deleted or is not running any more"
			exit 1
		fi
		if netinfos=$(VBoxManage guestproperty enumerate $vmname | grep '/VirtualBox/GuestInfo/Net/0/V4/IP'); then
			break
		fi
		i=$((i-1))
		if [ $i -eq 0 ]; then
			echo "VM $vmname took too long to start"
			exit 1
		fi
		echo -en "\rWaiting a bit longer ... ($i) \t"
		sleep 15
	done
	ip=$(echo $netinfos | awk '{print $4}' | sed -e 's/,.*$//')
	echo -e "\n\nAll done, VM $vmname IP is $ip"
	echo -e "[master]\n$ip\n\n[all:vars]\nansible_user=$username\n" > $CMDDIR/ansible/inventory/master
	if type ansible >/dev/null 2>&1; then
		echo -e "\n\nTry running the following: ansible all -i ansible/inventory/master -m ping\n"
	fi
elif [ "$virtprovider" == "kvm" ]; then
	# Check if VM already exists
	if virsh list --all --name 2>/dev/null | egrep -q "^${vmname}$"; then
		echo -e "\nERROR $(basename $0): VirtualBox VM with name [$vmname] already exists !!!\n"
		exit 1
	fi

	echo -e "\nNot implemented yet !!!\n"
fi
echo "All done"

exit 0
