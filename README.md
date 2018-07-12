onpc-provisioning
=================

Node provisioning automation to get hosts and network ready to install OpenStack
with OSA

You can also have a look at the file scripts/complete_scenario.sh to have a less
detailed version of the steps to be carried out during provisioning phase.

`create_infra_master_vm.sh` is a script used to bootstrap the infra-master/config node as a
VirtualBox or KVM VM:

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
PROXY=http://192.168.0.116:8080/ ./scripts/create_infra_master_vm.sh
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Creating the ISO for lab machines with static IP adress and network information, use
something like follows:

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ISO_ONLY=y STATICIP=172.31.0.58 NETMASK=255.255.255.0 GATEWAY=172.31.0.254 DNSSERVERS=213.246.33.144,213.246.36.14,80.93.83.11 NTPSERVERS=213.246.33.221 ./scripts/create_infra_master_vm.sh
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Look at the first lines of the file to have an idea on which parameters can be
customized.

Once completed successfully, the script should also have created the following
Once done, the script should also have created the following file (of course IP
address(es) will not be identical):

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ansible/inventory/master

[infra-master]
192.168.0.131

[all:vars]
ansible_user=vagrant
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

### Step 0: Install ansible

Please note that it is strongly recommended to NOT use any packaged version
of ansible that may be located on the ansible-master machine where all playbooks
will be launched. Instead, use a virtualenv evnironment as described hereafter.

Make sure your python version is proper and use virtualenv on your main system.
On my MacOSX MacBook, I had to make sure to use the Homebrew version of Python
and not the default system one :-(:

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
brew install python brew-pip pyenv-virtualenv
/usr/local//Cellar/pipenv/11.9.0_1/libexec/bin/virtualenv ~/.venvs/ansible-brew-py27 -p /opt/local/bin/python
. ~/.venvs/ansible-brew-py27/bin/activate
pip install -r requirements.txt
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Then, you need to install the Ansible Galaxy roles which are required for some of the
OpenNext playbooks:

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ansible-galaxy install -r ansible/playbooks/requirements.yml 
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

If you want ansible to display time information on each and every task executed
in playbooks and get a summary of tasks which takes most of the deployment time
you can add the following environment variable before running any of the
ansible-playbook command hereaafter

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
export ANSIBLE_CALLBACK_WHITELIST="profile_tasks"
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Some tasks take a very long time to complete. Even though we took great care to
try to make the playbooks wait properly when required, there may be cases where
the underlying ssh utilities used by Ansible to communicate with remote assets
will timeout due to what is considered as "inactivity". Use the following
environment variable settings to prevent this from happening:

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
export ANSIBLE_SSH_ARGS="-C -o ControlMaster=auto -o ControlPersist=60s -o ServerAliveInterval=120 -o ServerAliveCountMax=10"
usual default being:
ansible-config dump | grep ANSIBLE_SSH_ARGS
ANSIBLE_SSH_ARGS(default) = -C -o ControlMaster=auto -o ControlPersist=60s
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Please also note that a summary of all playbooks to be launched can also be found
under scripts/complete_scenario.sh

Another important note to keep in mind is that steps 1-6 are launched on ansible-master
node (where the current repository has been extracted and ansible installed) whereas
7 and followers are launched on the OSA master machine

It is recommended to have your ansible-master node and your infra-master node not refering
to the same machine because we are computing potential collisions in IP addresses so that
networking issues can be detected/prevented very early and some packages like KVM/libvirt
often configure the NAT bridge with the same IP address on all machines (192.168.122.1).

### Step 1: System configuration

you are now able to launch the infra-master configuration via:

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ansible-playbook -i ansible/inventory/master ansible/playbooks/infra-master-configure-system.yml
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

You can now customize the distribution which will be used in Ironic "reference images" aka the
image which will be deployed on the future OpenStack Ansible nodes:

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ansible-playbook -i ansible/inventory/master ansible/playbooks/infra-master-configure-system.yml -e deployed_distribution=centos
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

By default Ubuntu (xenial) is used, using centos will install CentOS 7 on OSA nodes.

If you launch the playbook from a node where KVM/libvirt is already installed and on which infra-master and other
VMs will be spawned, you need to change kvm_on_ansible_master variable to true:

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ansible-playbook -i ansible/inventory/master ansible/playbooks/infra-master-configure-system.yml --extra-vars "kvm_on_ansible_master=true"
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

If you don't want infra-master node to use KVM/libvirt for running VMs you can add and extra flag

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ansible-playbook -i ansible/inventory/master ansible/playbooks/infra-master-configure-system.yml --extra-vars "kvm_on_infra_master=false"
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

You can customize the IP settings of the secondary network interface using:

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ansible-playbook -i ansible/inventory/master ansible/playbooks/infra-master-configure-system.yml --extra-vars "ip_prefix=192.168.1 ip_suffix=123 ip_netmask_bits=20"
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Look into `ansible/vars/infra-master-configure-system_vars.yml` to see what can be
configured and the associated default values.

Note that you may need to add **-K** option for running this playbook so that
the Ansible user sudo permissions are properly set. If you do not provide it in
the first run and suoders are not yet configured properly, you will get the
following output:

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
TASK [Gathering Facts] **************************************************************************************************************************************************************************************
fatal: [192.168.0.131]: FAILED! => {"changed": false, "module_stderr": "Shared connection to 192.168.0.131 closed.\r\n", "module_stdout": "sudo: a password is required\r\n", "msg": "MODULE FAILURE", "rc": 1}
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Just rerun the same playbook adding -K option and provide the Ubuntu system user
password at the prompt.

##### If the ssh-keys are not set up correctly yet you might use the following:

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Download vagrant default ssh key into your home directory
wget -q -O - https://raw.githubusercontent.com/hashicorp/vagrant/master/keys/vagrant.pub >~/.ssh/vagrant.pub

# Copy force it on your remote machine (may be you'll need to change ubuntu user and IP below ;-))
ssh-copy-id -f -i ~/.ssh/vagrant.pub ubuntu@192.168.0.131

# Or use any other key you might already have
ssh-copy-id -i ~/.ssh/my-key ubuntu@192.168.0.131

# Verify ssh connection is successfull:
ssh -i ~/.ssh/my-key ubuntu@192.168.0.131 uname -a

# You'll need python to be installed on the remote system:
ssh -t -i ~/.ssh/my-key ubuntu@192.168.0.131 'sudo apt-get update && sudo apt-get install -y python'
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

You can now rerun the playbook with proper options:

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ansible-playbook --private-key ~/.ssh/my-key -K -i ansible/inventory/min-ubu-master-meylan ansible/playbooks/infra-master-configure-system.yml
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

### Step 2: Bifrost environment configuration & pre-deployment

You can now prepare Bifrost environment properly:

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ansible-playbook -i ansible/inventory/master ansible/playbooks/infra-master-deploy-bifrost.yml
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Note that right now the only way Bifrost deployment is supported is with keystone=true

Do not forget to add `kvm_on_infra_master=false` if you added this option in step 1 above

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ansible-playbook -i ansible/inventory/master ansible/playbooks/infra-master-deploy-bifrost.yml --extra-vars "kvm_on_infra_master=false"
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

At the very end of this Ansible deployment, you'll see a debug message which
will tell you what you have to do next like:

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ssh user@192.168.0.131 -t 'cd ~vagrant/bifrost/playbooks && . ~vagrant/.venv/bifrost/bin/activate && .  ../env-vars && https_proxy= ansible-playbook -i inventory/target install.yaml -e extra_dib_elements=devuser -e ipa_upstream_release=stable-pike -e dib_os_release=xenial -e dib_os_element=ubuntu-minimal -e network_interface=enp0s8 -e enable_keystone=true -e noauth_mode=false'
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

this is because the Ansible deployment needs to run on the host where Bifrost
will be configured and installed.

You can now choose which version of OpenStack you want to deploy by adding an extra deployment variable:

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ansible-playbook -i ansible/inventory/master ansible/playbooks/infra-master-deploy-bifrost.yml -e openstack_release=queens
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Please note that the default used when nothing is specified is pike. You can also put this variable in ansible/inventory/master
for more safety an not forget it in following steps (see steps 5 and 7 part 2)

### Step 3: Launch Bifrost deployment using command returned by last debug message of step 2

You could remove the last 2 options `-e enable_keystone=true -e noauth_mode=false` if you
do not want to use keystone service:

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ssh user@192.168.0.131 -t 'cd ~vagrant/bifrost/playbooks && . ~vagrant/.venv/bifrost/bin/activate && .  ../env-vars && https_proxy= ansible-playbook -i inventory/target install.yaml -e extra_dib_elements=devuser -e ipa_upstream_release=stable-pike -e dib_os_release=xenial -e dib_os_element=ubuntu-minimal -e network_interface=enp0s8'
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

but again this is not supported at this point in time.

### Step 4: Launch post-deployment

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ansible-playbook -i ansible/inventory/master ansible/playbooks/infra-master-post-deploy-bifrost.yml
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

This step will add some informations into Ironic database like checksum of image to deploy,
Ironic introspection rules.

It will also place the openNext customized ipxe executables which wait a bit longer
for network connectivity and also for network switches to propagate packets
(debug messages on deployed VM/baremetal machine console).

Finally, it will also install and launch the register-helper utility which is
responsible for changing the Ironic states of registered machines automatically and
provide a REST API for VM/machines registration as well as status information.

### Step 5: Launch VMs to be provisioned

IMPORTANT NOTE: like explained in Step 0 above, some of the tasks executed by the
current step take a very long time and you need to adapt the Ansible environment
variable in the exact same way on the infra-master node prior to run the following
VM provisioning playbooks (ANSIBLE_SSH_ARGS).

Once everything is deployed successfully, you can start a huge slave VM using:

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ansible-playbook -i ansible/inventory/master ansible/playbooks/infra-master-create-osa-aio-vm.yml
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

This will provide ground for a proper single box aka all-in-one aka AIO OSA deployment.
You can also customize the AIO VM and specify values for #CPUs, memory, #HDDs, HDD-size

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ansible-playbook -i ansible/inventory/master-ikoula-56 ansible/playbooks/infra-master-create-osa-aio-vm.yml -e aio_cpus=8 -e aio_disks=1 -e aio_disk_size=500
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

You can also choose to have a multi-vm deployment using:

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ansible-playbook -i ansible/inventory/master ansible/playbooks/infra-master-create-osa-multi-vm.yml
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

This will provide ground for a proper multi (4) VMs OSA deployment.
You can also customize the OSA VMs and specify values for #CPUs, memory, #HDDs, HDD-size

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ansible-playbook -i ansible/inventory/master ansible/playbooks/infra-master-create-osa-multi-vm.yml -e osa_nodes_disks=2 -e osa_nodes_disk_size=200
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Please play very close attention also to the IMPORTANT NOTE in step 7 concerning disks partitions in advance
to specify your disks numbers and sizes.

Anyhow, all VMs will get provisioned with IPA image (Ironic Python Agent) and register
automatically into ironic to wait for proper provisioning.

IMPORTANT NOTE: if you have specified a value for openstack_release on the command line and not in the Ansible inventory file at step 2 above,
you MUST add it to any of the command written in this paragraph for step 5.

If you are provisioning baremetal machines the playbook to be used is

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ansible-playbook -i ansible/inventory/master ansible/playbooks/infra-master-create-osa-baremetal-node.yml -e node_name="<NODE_NAME>" \
    -e node_ip="<NODE_IP>" -e node_mac_address="<NODE_MAC_@>" -e node_bmc_ip="<NODE_BMC_IP>" -e node_bmc_user="<NODE_BMC_USER>" \
    -e node_bmc_passwd="<NODE_BMC_PASSWD>" -e node_roles="['compute','ceph']" \
    -e storage_partition_size="<CINDER_LVM_SIZE_GB>" | ceph_partition_size="<CEPH_OSD_SIZE_GB>" \
    -e compute_partition_size="<NOVA_INSTANCE_SIZE_GB>"
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

and it is to be called for each machine you want to add in your final infrastructure.
The command line above should provide IPMI/BMC IP address, user+password and mac address
as well as the roles you want to assign to the node

Valid/supported node roles are at the present time:
 - control
 - storage
 - compute
 - ceph

After machines have been provisioned using this stage 5, node roles are stored as facts on the infra-master
machine under /etc/ansible/facts.d/opennext_infra_master_create_osa_nodes.fact
The playbooks called further down use these facts to retrieve node roles and build appropriate variables
which will in turn be used for instance to create disks partitions according to role during
osa-nodes-configure-system.yml

### Step 6: OpenNext Bootstrap for final OSA deployment

Now that your VM(s) is(are) available, you need to finalize some modifications on
infra-master node prior to launch the effective OSA deployment:

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ansible-playbook -i ansible/inventory/master ansible/playbooks/infra-master-opennext-pre-deploy.yml
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

This step install Squid on infra-master system for VM based (aka non-baremetal) usage.

It also retrieve the OpenNext onpc-provisioning Github repository which will be used in step 7 below.

Finally, it creates the ansible virtualenv which will be used in step 7 below for further machine
deployments.

### Step 7: Configure system of VMs to be deployed

IMPORTANT NOTE: this step has to occur when logged onto infra-master node. You will
also need to activate the ansible virtualenv which has been setup by step 6 above using:
. ~/.venv/ansible/bin/activate

Now that your VM(s) is(are) available, you need to finalize some modifiations on
it(them) prior to launch the effective OSA deployment. To do so, you need to log
into infra-master and launch the following:

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ansible-playbook -i ~vagrant/osa-inventory /opt/onpc-provisioning/ansible/playbooks/osa-nodes-configure-system.yml
ansible-playbook -i ~vagrant/osa-inventory /opt/onpc-provisioning/ansible/playbooks/osa-master-opennext-deploy.yml
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Concerning the  1st phase (osa-nodes-configure-system), please note that in case of a virtualized environment,
and depending on the disk(s) you have specified for you VMs, you might want to customize the base_system_disk_device
deployment parameter which is used to specify on which disk OSA partitioning requirements will be applied.
The default value is defined in ansible/vars/osa-disks-partitions_vars.yml and is set to /dev/sda which is
supposed to be sound for baremetal cases. For virtualized environment it should most probably match /dev/vdX.

IMPORTANT NOTE: please pay very close attention to the fact that the partition template defined in
ansible/vars/osa-disks-partitions_vars.yml should be adapted to the disk(s) you have defined in step
6 when deploying you VMs. The default template tries to put all partitions in a single disk
whereas you might want to configure this over several if applicable.

Please note that the final task in osa-master-opennext-deploy.yml can take a very long time to complete.
If you want to see progress on this task, log into the osa-master node (which IP you will find in ~vagrant/osa-inventory)
and, as root, do a tail -f /var/log/osa_run_playbooks*.logs.

If you do NOT want to run the tempest tests at the very end of the deployment, you can add the following option:

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ansible-playbook -i ~vagrant/osa-inventory /opt/onpc-provisioning/ansible/playbooks/osa-master-opennext-deploy.yml -e run_tempest_tests=no
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

IMPORTANT NOTE: if you have specified a value for openstack_release on the command line and not in the Ansible inventory file at step 2 above,
you MUST add it to any of the command written in this paragraph for step 5. You might also want to make sure it got written appropriately
into osa-inventory file in which case you do not need to add it on the command lines.

### Step 8: OpenNext post OSA deployment

Now that OpenStack Ansible is successfully deployed, the following
command run on your ansible-master node deploys some additional services

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ansible-playbook -i ansible/inventory/master ansible/playbooks/infra-master-opennext-post-osa-deploy.yml
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Namingly, it installs and configures an OpenVPN service on the infra-master node which
allows complete access to local network, provisioning network and management network (br-mgmt).
To use this VPN, fetch the zip file created automatically under /etc/openvpn/keys/*.zip and fetch
it into your prefered VPN client. Example for OpenVPN CLI:

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
rsync infra-master:/etc/openvpn/keys/*.zip /tmp
mkdir /etc/openvpn/infra-master %% cd /etc/openvpn/infra-master
unzip -q /tmp/*.zip
openvpn2 /etc/openvpn/infra-master/*.ovpn
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Route to infra-master networks should be added (pushed) automatically and
you should now be able to access any IP on those networks behind the VPN.

You might want to add additional routes to some other networks
ansible-playbook -i ansible/inventory/master ansible/playbooks/infra-master-opennext-post-osa-deploy.yml -e additional_openvpn_client_routes="['172.29.248.0 255.255.252.0','1.2.3.4 255.255.255.0']"
Be carefull however to NOT add spaces before or after the comma in the list

Note that the previous installation and configuration of Nginx as a reverse proxy
to access to Horizon and Grafana is now disabled by default and can be reinstated
using -e opennext_reverse_nginx=True

### Getting informations, interacting with OpenStack utilities, ...

To get the status of the registered machines of your current provisioned infrastructure
log onto infra-master machine and run the following commands:

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Activate new venv and credentials
cd ~vagrant && . .venv/bifrost/bin/activate && . openrc bifrost-admin
# See Bifrost registered nodes
openstack baremetal node list
# You can also query the regist-helper agent utility to get informations
# and format the JSON response for human readability
curl -s -u ${OS_USERNAME}:${OS_PASSWORD} -H 'Content-Type: application/json' -X GET http://localhost:7777/status | jq -S . -
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
