#!/bin/bash

# Exits on errors
set -ex
# Trace everything into specific log file
exec > >(tee -i /var/log/"$(basename "$0" .sh)"_"$(date '+%Y-%m-%d_%H-%M-%S')".log) 2>&1

# Move to proper dir
cd /opt/onpc-monitoring
# Create the monitoring container(s)
openstack-ansible /opt/openstack-ansible/playbooks/lxc-containers-create.yml -e 'container_group=influx_containers:collectd_containers:grafana_containers'
# Create the monitoring user and install various python dependencies
openstack-ansible playbook_setup.yml
# If you are running HAProxy for load balacing you need run the following playbook as well to enable the monitoring services backend and frontend.
openstack-ansible playbook_haproxy.yml
#If you already deployed OSA you also need to rerun the OSA HAProxy playbook to enable the HAProxy stats.
#openstack-ansible /opt/openstack-ansible/playbooks/haproxy-install.yml
# Install InfluxDB and InfluxDB Relay
openstack-ansible playbook_influxdb.yml
openstack-ansible playbook_influxdb_relay.yml
# Install Telegraf
# If you wish to install telegraf and point it at a specific target, or list of targets, set the telegraf_influxdb_targets variable in the
# user_onpc_variables.yml file as a list containing all targets that telegraf should send metrics to.
openstack-ansible playbook_telegraf.yml --forks 50
# Install Grafana
# If you're proxy'ing grafana you will need to provide the full root_path when you run the playbook add the following -e grafana_url='https://cloud.something/grafana/'
# Note: Specifying the Grafana external URL won't work with http_proxy settings in the playbook.
openstack-ansible playbook_grafana.yml

# All done
touch /opt/.onpc_playbooks_done
