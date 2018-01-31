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
ansible-playbook -i ansible/inventory/master ansible/playbooks/master-configure-system.yml

You can customize the IP settings of the secondary network interface using:
ansible-playbook -i ansible/inventory/master ansible/playbooks/master-configure-system.yml --extra-vars "ip_prefix=192.168.1 ip_suffix=123 ip_netmask_bits=20"

Look into ansible/vars/master-configure_vars.yml to see what can be configured

Once done, you have to prepare Bifrost environment properly:
ansible-playbook -i ansible/inventory/master ansible/playbooks/master-deploy-bifrost.yml

At the very end of this Ansible deployment, you'll see a debug message which will tell you what you have to do next like:
ssh user@192.168.0.131 -t 'cd /home/user/bifrost/playbooks && . /home/user/.venv/bifrost/bin/activate && . ../env-vars && https_proxy= ansible-playbook -i inventory/target install.yaml -e network_interface=enp0s8'

this is because the Ansible deployment needs to run on the host where Bifrost will be configured and installed

Once everything is deployed successfully, you can start 3 slave VMs using:
./scripts/create_slave_vms.sh 3

which will get provisioned with IPA image (Ironic Python Agent) and register automatically into ironic to wait for proper provisioning
