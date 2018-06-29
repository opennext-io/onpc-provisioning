#!/bin/bash

# Exits on errors
set -ex
# Trace everything into specific log file
exec > >(tee -i /var/log/"$(basename "$0" .sh)"_"$(date '+%Y-%m-%d_%H-%M-%S')".log) 2>&1

if [ ! -r /opt/onpc-basic-model/ansible_role_requirements.yml ]; then
	echo "Missing or unreadable file -e role_file=/opt/onpc-basic-model/ansible_role_requirements.yml"
	exit 1
fi
# Import the ansible role dependencies
cd /opt/openstack-ansible
openstack-ansible ./tests/get-ansible-role-requirements.yml -e role_file=/opt/onpc-basic-model/ansible_role_requirements.yml

# All done
touch /opt/.onpc_roles_done
