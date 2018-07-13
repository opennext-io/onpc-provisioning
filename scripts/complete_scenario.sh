#!/bin/bash

# IMPORTANT NOTE: this scenario script is not supposed to be launched as is
# but rather a condensed version of all the instructions given in the README.md file

set -e

export ANSIBLE_CALLBACK_WHITELIST="profile_tasks"
export ANSIBLE_SSH_ARGS="-C -o ControlMaster=auto -o ControlPersist=60s -o ServerAliveInterval=120 -o ServerAliveCountMax=10"

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
# also add some OpenNext specifics services (Squid) and associated configurations
ansible-playbook -i ansible/inventory/master ansible/playbooks/infra-master-post-deploy-bifrost.yml

# Stage 5 => test scenarios all-in-one (one huge VM) or 3 vms
#ansible-playbook -i ansible/inventory/master ansible/playbooks/infra-master-create-osa-aio-vm.yml
#ansible-playbook -i ansible/inventory/master ansible/playbooks/infra-master-create-osa-multi-vm.yml
# You can also use the following playbook to register a real baremetal server providing
# IPMI/BMC IP address, user+password and mac address and node roles
#ansible-playbook -i ansible/inventory/master ansible/playbooks/infra-master-create-osa-baremetal-node.yml -e node_name="<NODE_NAME>" -e node_ip="<NODE_IP>" -e node_mac_address="<NODE_MAC_@>" -e node_bmc_ip="<NODE_BMC_IP>" -e node_bmc_user="<NODE_BMC_USER>" -e node_bmc_passwd="<NODE_BMC_PASSWD>" -e node_roles="['compute','ceph']"

# Valid/supported node roles are at the present time:
# - control
# - storage
# - compute
# - ceph

# After machines have been provisioned using this stage 5, node roles are stored as facts on the infra-master
# machine under /etc/ansible/facts.d/opennext_infra_master_create_osa_nodes.fact
# The playbooks called further down use these facts to retrieve node roles and build appropriate variables
# which will in turn be used for instance to create disks partitions according to role during
# osa-nodes-configure-system.yml

# Stage 6 => configure provisioned VMs system and services for OSA deployment
# For this stage only (2 playbooks to be run), you need to be logged on the infra-master node where
# the osa-inventory file has been generated for you
ansible-playbook -i ~vagrant/osa-inventory /opt/onpc-provisioning/ansible/playbooks/osa-nodes-configure-system.yml

# effective OSA deployment. A fair part of this is what you use when deploying OSA by your own
# means. However a lot of hidden potential issues are delt with here
# Please note that the final task in osa-master-opennext-deploy.yml can take a very long time to complete.
# If you want to see progress on this task, log into the osa-master node
# (which IP you will find in ~vagrant/osa-inventory) and, as root, do a
# tail -f /var/log/osa_run_playbooks*.logs.
export ANSIBLE_SSH_ARGS="-C -o ControlMaster=auto -o ControlPersist=60s -o ServerAliveInterval=120 -o ServerAliveCountMax=10"
ansible-playbook -i ~vagrant/osa-inventory /opt/onpc-provisioning/ansible/playbooks/osa-master-opennext-deploy.yml

# Stage 7 => configure additional services to access Horizon and Grafana from infra-master node
# acting as a reverse proxy to appropriate services in VMs
# This stage is to be run again on ansible-master node, not on infra-master
ansible-playbook -i ansible/inventory/master ansible/playbooks/infra-master-opennext-post-osa-deploy.yml
