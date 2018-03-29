#!/bin/bash

# Exit on errors
set -e

# Import some utilities
. $(dirname $0)/functions.sh

CMDDIR=$(dirname $(dirname $($linkcmd -f $0)))

# VM parameters
vmname=${SLAVE_VM_NAME:-"slave"}
vmmem=${SLAVE_VM_MEM:-8192}
vmcpus=${SLAVE_VM_CPUS:-4}
vmdisk=${SLAVE_VM_DISK:-61440}
maxvms=${MAX_SLAVES:-5}
startingvmid=${START:-0}
vmvncbindip=${SLAVE_VM_VNC_IP:-"0.0.0.0"}
vmvncport=${SLAVE_VM_VNC_PORT:-5900}
vbmcport=${SLAVE_VM_VBMC_PORT:-6000}
vbmcuser=${VBMC_USER:-"admin"}
vbmcpasswd=${VBMC_PASSWORD:-"password"}
masterip=${MASTER_VM_IP:-"127.0.0.1"}
masterport=${MASTER_VM_PORT:-7777}
register=${REGISTER_URI:-"register"}
unregister=${UNREGISTER_URI:-"unregister"}
authuser=${KEYSTONE_USER:-${OS_USERNAME:-""}}
authpasswd=${KEYSTONE_PASSWORD:-${OS_PASSWORD:-""}}

authcreds=""
if [ -n "$authuser" ] && [ -n "$authpasswd" ]; then
	authcreds="-u ${authuser}:${authpasswd}"
fi

# Check command line arguments
if [ $# -ne 1 ]; then
	echo -e "\nUsage: $(basename $0) #nb-vms-to-launch\n"
	exit 1
fi

checkstring SLAVE_VM_NAME   "$vmname"      false
checkstring SLAVE_VM_VNC_IP "$vmvncbindip" false '^([0–9]{1,3}\.){3}([0–9]{1,3})$'

checknumber '#nb-vms-to-launch' $1         1    $maxvms
checknumber SLAVE_VM_MEM        $vmmem     1024 ""      8
checknumber SLAVE_VM_DISK       $vmdisk    2048 ""      1024
checknumber SLAVE_VM_CPUS       $vmcpus    1    16      1
checknumber SLAVE_VM_VNC_PORT   $vmvncport 5900 ""      1

# Launch VM(s) according to provider
for i in $(seq 1 $1); do
	idx=$(($startingvmid + $i))
	lvmname=${vmname}-$idx
	if [ "$virtprovider" == "vbox" ]; then
		# Check if VM already exists
		if $vboxcmd list vms | egrep -q "^\"${lvmname}\" "; then
			yesorno "VirtualBox VM with name [$lvmname] already exists" "Do you want to erase it [y/n] "
			if $vboxcmd controlvm $lvmname poweroff 2>/dev/null; then
				echo "$lvmname was powered off successfully"
				# Wait a bit for poweroff to occur
				sleep 2
			else
				echo "$lvmname was already powered off"
			fi
			$vboxcmd unregistervm $lvmname --delete
		fi

		# Base of VM is Ubuntu 64bits
		vmuuid=$($vboxcmd createvm --name $lvmname --ostype Ubuntu_64 --register | egrep "^UUID: " | awk '{print $NF}')
		echo "Created $lvmname: $vmuuid"
		# VM basics
		$vboxcmd modifyvm $lvmname --memory $vmmem --cpus $vmcpus --boot1 net --boot2 disk --boot3 none --audio none --usb off --rtcuseutc on --vram 16 --pae off
		# VM networks
		$vboxcmd modifyvm $lvmname --nic1 intnet
		# VM HDD
		$vboxcmd storagectl $lvmname --name SATA --add sata --controller IntelAHCI --portcount 1 --hostiocache off
		eval $($vboxcmd showvminfo $lvmname --machinereadable | grep ^CfgFile=)
		vmdir=$(dirname "$CfgFile")
		vmdiskuuid=$($vboxcmd createmedium disk --filename "$vmdir"/$lvmname --size $vmdisk | egrep "^.* UUID: " | awk '{print $NF}')
		$vboxcmd storageattach $lvmname --storagectl SATA --type hdd --port 0 --device 0 --medium "$vmdir"/$lvmname.vdi
		# Start VM
		$vboxcmd startvm $lvmname --type headless
	elif [ "$virtprovider" == "kvm" ]; then
		# Check if VM already exists
		if $virshcmd list --all --name 2>/dev/null | egrep -q "^${lvmname}$"; then
			yesorno "KVM VM with name [$lvmname] already exists" "Do you want to erase it [y/n] "
			eval $(getvminfos $lvmname)
			jsoninfos="{ \
				\"name\": \"${lvmname}\", \
				\"mac_addr\": \"${macaddr}\", \
				\"virt-uuid\": \"${uuid}\" \
			}"
			if  curl -s $authcreds -H 'Content-Type: application/json' -X DELETE -d "$jsoninfos" http://${masterip}:${masterport}/${unregister}/${uuid}; then
				echo "VM unregistration infos sent successfully"
			else
				echo "Failed to send VM unregistration infos"
			fi
			if $virshcmd destroy $lvmname 2>/dev/null; then
				echo "$lvmname was powered off successfully"
				# Wait a bit for poweroff to occur
				sleep 2
			else
				echo "$lvmname was already powered off"
			fi
			if vbmc stop $lvmname 2>/dev/null; then
				echo "vbmc endpoint for $lvmname was stopped successfully"
			else
				echo "vbmc endpoint was already stopped for $lvmname"
			fi
			if vbmc delete $lvmname 2>/dev/null; then
				echo "$lvmname was removed successfully from vbmc"
			else
				echo "vbmc was already deleted for $lvmname"
			fi
			$virshcmd undefine $lvmname --snapshots-metadata --remove-all-storage
		fi
		# As VNC is much more performant than virt-viewer, unsetting DISPLAY
		# will prevent from launching the latest unless FORCEX environment
		# variable is set
		if [ -z "$FORCEX" ]; then
			unset DISPLAY
		fi
		lvmvncport=$(($vmvncport + $idx))
		echo -e "\nYou can attach to VNC console at ${vmvncbindip}:$lvmvncport (local IP address is $localip)\n"
		# Start VM
		$virtinstallcmd -v --virt-type kvm --name $lvmname --ram $vmmem --vcpus $vmcpus --os-type linux --os-variant ubuntu16.04 \
			--disk path=/var/lib/libvirt/images/${lvmname}-1.qcow2,size=$(($vmdisk / 1024)),bus=virtio,format=qcow2 \
			--disk path=/var/lib/libvirt/images/${lvmname}-2.qcow2,size=$(($vmdisk / 1024)),bus=virtio,format=qcow2 \
			--network bridge=br-prov,model=virtio \
			--pxe --boot network,hd --noautoconsole \
			--graphics vnc,listen=$vmvncbindip,port=$lvmvncport
		sleep 2
		lvbmcport=$(($vbmcport + $idx))
		vbmc add $lvmname --port $lvbmcport
		vbmc start $lvmname
		eval $(getvminfos $lvmname)
		jsoninfos="{ \
			\"name\": \"${lvmname}\", \
			\"mac_addr\": \"${macaddr}\", \
			\"virt-uuid\": \"${uuid}\", \
			\"bmc_port\": ${lvbmcport}, \
			\"bmc_host\": \"${localip}\", \
			\"bmc_user\": \"${vbmcuser}\", \
			\"bmc_password\": \"${vbmcpasswd}\", \
			\"vnc_host\": \"${localip}\", \
			\"vnc_port\": ${lvmvncport} \
		}"
		if  curl -s $authcreds -H 'Content-Type: application/json' -X POST -d "$jsoninfos" http://${masterip}:${masterport}/${register}; then
			echo "VM registration infos sent successfully"
		else
			echo "Failed to send VM registration infos"
		fi
	fi
done

exit 0
