#!/bin/bash

# Stage 0.1 => create installation ISO
# Stage 0.2 => provision baremetal machine (or VM) infra-master using ISO from 0.1

# Stage 1 => configure infra-master system 
ansible-playbook -i ansible/inventory/master ansible/playbooks/infra-master-configure-system.yml
# Stage 2 => prepare infra-master node for Bifrost
ansible-playbook -i ansible/inventory/master ansible/playbooks/infra-master-deploy-bifrost.yml

# Stage 3 => Effective Bifrost deployment. This is what you get when you use bifrost by yourself
# (plus a little bit of Stage 2). However you'll have to change a lot of parameters to
# get stuff right and coherent
ssh vagrant@80.93.82.50 -t 'cd /home/vagrant/bifrost/playbooks && . /home/vagrant/.venv/bifrost/bin/activate && . ../env-vars && https_proxy= ansible-playbook -i inventory/target install.yaml -e @/home/vagrant/deploy_args.yml'

# Stage 4 => add some ironic introspection rules and agent for managing ironic state auto-magically
ansible-playbook -i ansible/inventory/master ansible/playbooks/infra-master-post-deploy-bifrost.yml

# Stage 5 => test scenarios 1 all-in-one one with 3 vms
#ansible-playbook -i ansible/inventory/master ansible/playbooks/infra-master-create-osa-aio-vm.yml
ansible-playbook -i ansible/inventory/master ansible/playbooks/infra-master-create-osa-multi-vm.yml

#  Stage 6 => Add some OpenNext specifics services (Squid) and associated configurations
ansible-playbook -i ansible/inventory/master ansible/playbooks/infra-master-opennext-pre-deploy.yml

# Stage 7 => configure provisioned VMs system and services for OSA deployment
# From this step onwards, you need to be logged on the infra-master node where the osa-inventory file
# has been generated for you
ansible-playbook -i ~vagrant/osa-inventory /opt/onpc-bootstrap/ansible/playbooks/osa-vms-configure-system.yml

# Stage 8 => effective OSA deployment. A fair part of this is what you use when deploying OSA by your own
# means. However a lot of hidden potential issues are delt with here
ansible-playbook -i ~vagrant/osa-inventory /opt/onpc-bootstrap/ansible/playbooks/osa-master-opennext-deploy.yml
