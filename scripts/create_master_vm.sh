#!/bin/bash

# Exit on errors
set -e

# Import some utilities
. $(dirname $0)/functions.sh

CMDDIR=$(dirname $(dirname $($linkcmd -f $0)))

# VM parameters
vmname=${MASTER_VM_NAME:-"master"}
vmmem=${MASTER_VM_MEM:-2048}
vmcpus=${MASTER_VM_CPUS:-2}
vmdisk=${MASTER_VM_DISK:-10240}
vmvncbindip=${MASTER_VM_VNC_IP:-"0.0.0.0"}
vmvncport=${MASTER_VM_VNC_PORT:-5900}

# ISO parameters
preseed=${PRESEED_URL:-http://www.olivierbourdon.com/preseed_master.cfg}
noipv6=${NO_IPV6:+"1"}
httpproxy=${PROXY:-""}
username=${ADMIN_USER:-"vagrant"}
passwd=${ADMIN_PASSWD:-"vagrant"}
domainname=${DOMAIN:-"vagrantup.com"}

# Check command line arguments
if [ $# -ne 0 ]; then
	echo -e "\nUsage: $(basename $0)\n"
	exit 1
fi

checkstring ADMIN_USER       "$username"    false '^[A-Za-z][A-Za-z0-9]*$' '^.*\s.*$|^root$'
checkstring ADMIN_PASSWD     "$passwd"      false '^[A-Za-z0-9/@_=+-]+$' '^.*\s.*$'
checkstring PROXY            "$httpproxy"   true
checkstring MASTER_VM_NAME   "$vmname"      false
checkstring MASTER_VM_VNC_IP "$vmvncbindip" false '^([0–9]{1,3}\.){3}([0–9]{1,3})$'

checknumber MASTER_VM_MEM      $vmmem     512  "" 8
checknumber MASTER_VM_DISK     $vmdisk    5120 "" 1024
checknumber MASTER_VM_CPUS     $vmcpus    1    16 1
checknumber MASTER_VM_VNC_PORT $vmvncport 5900 "" 1

# Check existence of ISO
iso=$CMDDIR/isos/custom.iso
if [ ! -r $iso ]; then
	echo "Using docker to build custom ISO ..."
	# Fetch some required commands
	dockercmd=$(getcmd docker)
	if [ ! -d $CMDDIR/docker/build_custom_iso ]; then
		echo -e "\nERROR $(basename $0): missing dir $CMDDIR/docker/build_custom_iso\n"
		exit 1
	fi
	tag=custom-iso:latest
	if ! $dockercmd images $tag | grep -q custom; then
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
	if ! eval $dockercmd run -t $opts -e "iso=$dir/custom.iso" -v $(dirname $iso):$dir $tag; then
		echo -e "\nERROR $(basename $0): can not built iso\n"
		exit 1
	fi
fi

# Launch VM according to provider
if [ "$virtprovider" == "vbox" ]; then
	# Check if VM already exists
	if $vboxcmd list vms | egrep -q "^\"$vmname\" "; then
		yesorno "VirtualBox VM with name [$vmname] already exists" "Do you want to erase it [y/n] "
		if $vboxcmd controlvm $vmname poweroff 2>/dev/null; then
			echo "$vmname was powered off successfully"
			# Wait a bit for poweroff to occur
			sleep 2
		else
			echo "$vmname was already powered off"
		fi
		$vboxcmd unregistervm $vmname --delete
	fi

	netitf=$($vboxcmd list bridgedifs | grep $activenetitf | grep '^Name: ' | sed -e 's/Name: *//')

	# Base of VM is Ubuntu 64bits
	vmuuid=$($vboxcmd createvm --name $vmname --ostype Ubuntu_64 --register | egrep "^UUID: " | awk '{print $NF}')
	echo "Created $vmname: $vmuuid"
	# VM basics
	$vboxcmd modifyvm $vmname --memory $vmmem --cpus $vmcpus --boot1 dvd --boot2 disk --boot3 none --audio none --usb off --rtcuseutc on --vram 16 --pae off
	# VM networks
	$vboxcmd modifyvm $vmname --nic1 bridged --bridgeadapter1 "$netitf" --nic2 intnet
	# VM CDROM/IDE
	$vboxcmd storagectl $vmname --name IDE --add ide --controller PIIX4
	$vboxcmd storageattach $vmname --storagectl IDE --type dvddrive --port 1 --device 0 --medium "$iso"
	# VM HDD
	$vboxcmd storagectl $vmname --name SATA --add sata --controller IntelAHCI --portcount 1 --hostiocache off
	eval $($vboxcmd showvminfo $vmname --machinereadable | grep ^CfgFile=)
	vmdir=$(dirname "$CfgFile")
	vmdiskuuid=$($vboxcmd createmedium disk --filename "$vmdir"/$vmname --size $vmdisk | egrep "^.* UUID: " | awk '{print $NF}')
	$vboxcmd storageattach $vmname --storagectl SATA --type hdd --port 0 --device 0 --medium "$vmdir"/$vmname.vdi
	# Start VM
	$vboxcmd startvm $vmname --type headless
	sleep 5
	# Expressed in minutes
	i=${TIMEOUT:-30}
	# Because sleep step below is 15s
	i=$((i*4))
	while true; do
		if [ $($vboxcmd guestproperty enumerate $vmname 2>/dev/null | wc -l) -le 1 ]; then
			echo "VM $vmname was killed, deleted or is not running any more"
			exit 1
		fi
		if netinfos=$($vboxcmd guestproperty enumerate $vmname | grep '/VirtualBox/GuestInfo/Net/0/V4/IP'); then
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
elif [ "$virtprovider" == "kvm" ]; then
	# Check if VM already exists
	if $virshcmd list --all --name 2>/dev/null | egrep -q "^${vmname}$"; then
		yesorno "KVM VM with name [$vmname] already exists" "Do you want to erase it [y/n] "
		if $virshcmd destroy $vmname 2>/dev/null; then
			echo "$vmname was powered off successfully"
			# Wait a bit for poweroff to occur
			sleep 2
		else
			echo "$vmname was already powered off"
		fi
		$virshcmd undefine $vmname --snapshots-metadata --remove-all-storage
	fi
	# As VNC is much more performant than virt-viewer, unsetting DISPLAY
	# will prevent from launching the latest unless FORCEX environment
	# variable is set
	if [ -z "$FORCEX" ]; then
		unset DISPLAY
	fi
	echo -e "\nYou can attach to VNC console at ${vmvncbindip}:$vmvncport (local IP address is $localip)\n"
	# Start VM
	$virtinstallcmd -v --virt-type kvm --name $vmname --ram $vmmem --vcpus $vmcpus --os-type linux --os-variant ubuntu16.04 \
		--disk path=/var/lib/libvirt/images/$vmname.qcow2,size=$(($vmdisk / 1024)),bus=virtio,format=qcow2 \
		--network bridge=br0,model=virtio --network bridge=virbr1,model=virtio \
		--cdrom $iso --graphics vnc,listen=$vmvncbindip,port=$vmvncport
	ip=$(arp -e | grep $(virsh domiflist $vmname | grep vnet0 | awk '{print $NF}') | awk '{print $1}')
fi

echo -e "\n\nAll done, VM $vmname IP is $ip"
echo -e "[master]\n$ip\n\n[all:vars]\nansible_user=$username\n" > $CMDDIR/ansible/inventory/master
if type ansible >/dev/null 2>&1; then
	echo -e "\n\nTry running the following: ansible all -i ansible/inventory/master -m ping\n"
fi

exit 0
