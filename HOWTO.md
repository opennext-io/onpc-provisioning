onpc-provisioning HOWTO
=======================

To restart clean from a VM based AIO existing deployment

### Step 1: Log onto infra-master machine and stop existing VM

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
virsh destroy osa-aio ; virsh undefine osa-aio --snapshots-metadata --remove-all-storage
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Note that the extra options also remove the existing disk(s) attached the VM from the libvirt pool

### Step 2: activate VBMC environment to de-register VM

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Activate venv
cd ~vagrant && . .venv/vbmc/bin/activate
vbmc delete osa-aio
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

### Step 5: Restart provisioning

Cf. README.md Step 5
