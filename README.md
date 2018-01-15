# openstack-ansible-bootstrap
Node provisioning automation to get hosts and network ready to install OpenStack with OSA

create_master_vm.sh is a script used to bootstrap the master/config node as a VirtualBox or KVM VM
Example:
PROXY=http://192.168.0.116:8080/ ./scripts/create_master_vm.sh custom.iso

Look at the first lines of the file to have an idea on which parameters can be customized.
