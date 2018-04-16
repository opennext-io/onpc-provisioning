openstack-ansible-bootstrap
===========================

Node provisioning automation to get hosts and network ready to install OpenStack
with OSA

`create_infra_master_vm.sh` is a script used to bootstrap the infra-master/config node as a
VirtualBox or KVM VM:

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
PROXY=http://192.168.0.116:8080/ ./scripts/create_infra_master_vm.sh
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

### Step 1: System configuration

you are now able to launch the infra-master configuration via:

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ansible-playbook -i ansible/inventory/master ansible/playbooks/infra-master-configure-system.yml
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

If you launch the playbook from a node where KVM/libvirt is already installed and on which infra-master and other
VMs will be spawned, you need to change ansible_master_using_kvm variable to true:

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ansible-playbook -i ansible/inventory/master ansible/playbooks/infra-master-configure-system.yml --extra-vars "ansible_master_using_kvm=true"
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

If you don't want infra-master node to use KVM/libvirt for running VMs you can add and extra flag

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ansible-playbook -i ansible/inventory/master ansible/playbooks/infra-master-configure-system.yml --extra-vars "master_running_kvm=false"
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

Do not forget to add `master_running_kvm=false` if you added this option in step 1 above

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ansible-playbook -i ansible/inventory/master ansible/playbooks/infra-master-deploy-bifrost.yml --extra-vars "master_running_kvm=false"
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

At the very end of this Ansible deployment, you'll see a debug message which
will tell you what you have to do next like:

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ssh user@192.168.0.131 -t 'cd ~vagrant/bifrost/playbooks && . ~vagrant/.venv/bifrost/bin/activate && .  ../env-vars && https_proxy= ansible-playbook -i inventory/target install.yaml -e extra_dib_elements=devuser,cloud-init-nocloud -e ipa_upstream_release=stable-pike -e dib_os_release=xenial -e dib_os_element=ubuntu-minimal -e network_interface=enp0s8 -e enable_keystone=true -e noauth_mode=false'
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

this is because the Ansible deployment needs to run on the host where Bifrost
will be configured and installed.

### Step 3: Launch Bifrost deployment using command returned by last debug message of step 2

You could remove the last 2 options `-e enable_keystone=true -e noauth_mode=false` if you
do not want to use keystone service:

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ssh user@192.168.0.131 -t 'cd ~vagrant/bifrost/playbooks && . ~vagrant/.venv/bifrost/bin/activate && .  ../env-vars && https_proxy= ansible-playbook -i inventory/target install.yaml -e extra_dib_elements=devuser,cloud-init-nocloud -e ipa_upstream_release=stable-pike -e dib_os_release=xenial -e dib_os_element=ubuntu-minimal -e network_interface=enp0s8'
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

but again this is not supported at this point in time.

### Step 4: Launch post-deployment

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ansible-playbook -i ansible/inventory/master ansible/playbooks/infra-master-post-deploy-bifrost.yml
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

### Step 5: Launch VMs to be provisioned

Once everything is deployed successfully, you can start a huge slave VM using:

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ansible-playbook -i ansible/inventory/master ansible/playbooks/infra-master-create-osa-aio-vm.yml
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

This will provide ground for a proper single box aka all-in-one aka AIO OSA deployment.

You can also choose to have a multi-vm deployment using:

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ansible-playbook -i ansible/inventory/master ansible/playbooks/infra-master-create-osa-multi-vm.yml
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

This will provide ground for a proper single box aka all-in-one aka AIO OSA deployment.

You can also still use the formerly available script and start 3 slave VMs using:

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
./scripts/create_slave_vms.sh 3
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Anyhow, all VMs will get provisioned with IPA image (Ironic Python Agent) and register
automatically into ironic to wait for proper provisioning.

### Step 6: OpenNext Bootstrap for final OSA deployment

Now that your VM(s) is(are) available, you need to finalize some modifiations on
infra-master node prior to launch the effective OSA deployment:

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ansible-playbook -i ansible/inventory/master ansible/playbooks/infra-master-opennext-pre-deploy.yml
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

### Step 7: Configure system of VMs to be deployed

Now that your VM(s) is(are) available, you need to finalize some modifiations on
it(them) prior to launch the effective OSA deployment. To do so, you need to log
into infra-master and launch the following:

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ansible-playbook -i ~vagrant/osa-inventory /opt/onpc-bootstrap/ansible/playbooks/osa-vms-configure-system.yml
ansible-playbook -i ~vagrant/osa-inventory /opt/onpc-bootstrap/ansible/playbooks/osa-master-opennext-deploy.yml
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

