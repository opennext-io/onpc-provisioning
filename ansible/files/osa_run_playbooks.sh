#!/bin/bash

# Exits on errors
set -ex
# Trace everything into specific log file
exec > >(tee -i /var/log/"$(basename "$0" .sh)"_"$(date '+%Y-%m-%d_%H-%M-%S')".log) 2>&1

# Move to proper dir
cd /opt/openstack-ansible/playbooks
# Run host setup
openstack-ansible setup-hosts.yml
# Run infra setup
openstack-ansible setup-infrastructure.yml
# Check Galera in infra
ansible galera_container -m shell -a "mysql -h localhost -e 'show status like \"%wsrep_cluster_%\";'"
# Run OpenStack setup
openstack-ansible setup-openstack.yml

# All done
touch /opt/.osa_playbooks_done
