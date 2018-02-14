#!/bin/bash

# This script can run only on MacOSX and Linux
# The readlink command needs to support -f option
os=$(uname -s)
case $os in
	Darwin)	linkcmd=greadlink;;
	Linux)	linkcmd=readlink;;
	*)	echo -e "\nERROR $(basename $0): unsupported platform $os\n"; exit 1;;
esac

virtprovider=${VIRT:-kvm}
vboxcmd=NONE
virshcmd=NONE
virtinstallcmd=NONE

# Function which checks availability of commands in list
# Inputs:
#	$1 : list of command names to find in order
#
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
	# Need to redirect to current tty for message to appear on screen or in script output
	echo -e "\nERROR $(basename $0): please install any of missing command(s): $cmds\n" >/dev/tty
	return 1
}

# Check virtualization mode & fetch some required commands
case $virtprovider in
	vbox)
		vboxcmd=$(getcmd VBoxManage)
		;;
	kvm)
		virshcmd=$(getcmd virsh)
		virtinstallcmd=$(getcmd virt-install)
		;;
	*)	echo -e "\nERROR $(basename $0): unsupported virtualization $virtprovider\n"; exit 1;;
esac
xmllintcmd=$(getcmd xmllint)

# Function which returns variable assignments corresponding
# to VM informations
# Inputs:
# $1: machine name/ID
getvminfos() {
	macaddr=""
	uuid=""
	case $virtprovider in
		kvm)
			macaddr=$($virshcmd dumpxml $1 | $xmllintcmd --xpath 'string(//interface[@type="bridge"]/mac/@address)' -)
			uuid=$($virshcmd dumpxml $1 | $xmllintcmd --xpath 'string(//uuid)' -)
			;;
		*) ;;
	esac
	nuuid=$(python -c "import sys;import uuid;print str(uuid.uuid3(uuid.NAMESPACE_DNS,sys.argv[1]))" $1)
	echo "uuid=$uuid"
	if [ -n "$macaddr" ]; then
		echo "macaddr=\"$macaddr\""
	fi
	if [ -n "$uuid" ]; then
		echo "uuid=\"$uuid\""
	fi
}

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
localip=$(ifconfig $activenetitf | grep 'inet ' | awk '{print $2}' | sed -e 's/.*://')

# Function which validates text parameter according to some criteria
# Inputs:
#	$1           : field name
#	$2           : field value to check
#	$3           : boolean which states if field can be empty (true)
#	$4 (optional): egrep regexp which should be matched against
#	$5 (optional): egrep regexp which should NOT be matched
#
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

# Function which validates number parameter according to some criteria
# Inputs:
#	$1           : field name
#	$2           : field value to check
#	$3 (optional): min value which field can take
#	$4 (optional): max value which field can take
#	$5 (optional): number for which field value must be a multiple of
#
checknumber() {
	if ! echo "$2" | egrep -q '^[0-9][0-9]*$'; then
		echo -e "\nUsage: $(basename $0): $1 variable error\n\n\tinvalid integer $2\n"
		exit 1
	fi
	if [ -n "$3" ] && [ $2 -lt $3 ]; then
		echo -e "\nUsage: $(basename $0) $1 variable error\n\n\t$2 too small, must be greater than $3\n"
		exit 1
	fi
	if [ -n "$4" ] && [ $2 -gt $4 ]; then
		echo -e "\nUsage: $(basename $0) $1 variable error\n\n\t$2 too big, must be smaller than $4\n"
		exit 1
	fi
	if [ -n "$5" ] && [ $(expr $2 % $5) -ne 0 ]; then
		echo -e "\nUsage: $(basename $0) $1 variable error\n\n\tinvalid integer $2, must be multiple of $5\n"
		exit 1
	fi
}

# Function which ask user input for yes or no input (Yy/Nn)
# Inputs:
#	$1 : error message
#   $2 : question message
#
yesorno() {
	echo -e "\nERROR $(basename $0): $1 !!!\n"
	echo -e -n "$2"
	ans=${YES:+"y"}
	test -n "$ans" || read ans
	ans=$(echo "$ans" | tr '[A-Z]' '[a-z]')
	if [ "$ans" != 'y' ]; then
		exit 1
	fi
}
