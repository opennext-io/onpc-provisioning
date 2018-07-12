onpc-provisioning HOWTO
=======================

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

### To restart clean from a VM based AIO existing deployment

### Step 1: Log onto infra-master machine and stop existing VM

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
virsh destroy aio1 ; virsh undefine aio1 --snapshots-metadata --remove-all-storage
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Note that the extra options also remove the existing disk(s) attached the VM from the libvirt pool

### Step 2: activate VBMC environment to de-register VM

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Activate venv
cd ~vagrant && . .venv/vbmc/bin/activate
vbmc delete aio1
# Verify
vbmc list
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Note that this is important as the VMs are allocated random MAC addresses

### Step 3: Activate Bifrost environment and de-register Ironic node

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# If you have activated VBMC virtual environment above
deactivate
# Activate new venv and credentials
cd ~vagrant && . .venv/bifrost/bin/activate && . openrc bifrost-admin
# See active nodes
openstack baremetal node list
# Set node in maintenance state prior to delete it (else delete fails)
openstack baremetal node maintenance set $(openstack baremetal node list -f value | awk '{print $1;exit}')
openstack baremetal node delete $(openstack baremetal node list -f value | awk '{print $1;exit}')
openstack baremetal node list
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

### Step 4: Restart register-helper utility

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
sudo service register-helper restart
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

This step is mandatory as today, this utility has no cleanup functionnality

### Step 5: Do facts cleanup on infra-master

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
sudo rm -f /etc/ansible/facts.d/opennext_infra_master_create_osa_nodes* \
           /etc/ansible/facts.d/opennext_osa_nodes_configure_system* \
           /etc/ansible/facts.d/opennext_osa_master_opennext_deploy* \
           /etc/ansible/facts.d/opennext_infra_master_opennext_post_osa_deploy*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

### Step 6: Restart provisioning

Cf. README.md Step 5
