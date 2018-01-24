# openstack-ansible-bootstrap
Node provisioning automation to get hosts and network ready to install OpenStack with OSA

create_master_vm.sh is a script used to bootstrap the master/config node as a VirtualBox or KVM VM
Example:
PROXY=http://192.168.0.116:8080/ ./scripts/create_master_vm.sh

Look at the first lines of the file to have an idea on which parameters can be customized.

Once done, the script should also have created the following file (of course IP will not be identical):
ansible/inventory/master
[master]
172.20.20.80

[all:vars]
ansible_user=vagrant

and you'll be able to launch the master configuration via:
ansible-playbook -i ansible/inventory/master ansible/playbooks/master-configure.yml

You can customize the IP settings of the secondary network interface using:
ansible-playbook -i ansible/inventory/master ansible/playbooks/master-configure.yml --extra-vars "ip_prefix=10.11.12 ip_suffix=123 ip_netmask_bits=20"

Look into ansible/vars/master-configure_vars.yml to see what can be configured
