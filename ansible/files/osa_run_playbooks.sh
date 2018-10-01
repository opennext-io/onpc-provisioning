#!/bin/bash

# Exits on errors
set -ex
# Trace everything into specific log file
exec > >(tee -i /var/log/"$(basename "$0" .sh)"_"$(date '+%Y-%m-%d_%H-%M-%S')".log) 2>&1

# Move to proper dir
cd /opt/openstack-ansible/playbooks
# Run host setup
openstack-ansible setup-hosts.yml
# In queens some playbooks have been added for extra checks
if [ -r healthcheck-hosts.yml ]; then
	openstack-ansible healthcheck-hosts.yml
fi
# Run YAML config files syntax checks
openstack-ansible setup-infrastructure.yml --syntax-check
# Run infra setup
openstack-ansible setup-infrastructure.yml
# Check Galera in infra
ansible galera_container -m shell -a "mysql -h localhost -e 'show status like \"%wsrep_cluster_%\";'"
# In queens some playbooks have been added for extra checks
if [ -r healthcheck-infrastructure.yml ]; then
	openstack-ansible healthcheck-infrastructure.yml -e rabbit_test_prompt=no
fi
# In rocky some playbooks have been added for extra checks
if [ -r healthcheck-openstack.yml ]; then
	openstack-ansible healthcheck-openstack.yml
fi
# Run OpenStack setup
openstack-ansible setup-openstack.yml

# All done
touch /opt/.osa_playbooks_done
