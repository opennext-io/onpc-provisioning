#!/usr/bin/env python

# Requires the following modules to work
#
# pip install -U flask
# pip install -U apscheduler
# pip install -U shade
# pip install flask_httpauth

# System imports
import os
import pprint
import ast
import time
import datetime

# Flask web service imports
from flask import Flask, jsonify, request, abort
from functools import wraps

# HTTP Basic Authentication
from flask_httpauth import HTTPBasicAuth

# Asynchronous "background" job(s) imports
from apscheduler.schedulers.background import BackgroundScheduler

# Shade Cloud library
import shade

# Light Persistence
import shelve

# JSON library
import json

# Main Flask application handle
app = Flask(__name__)
# Authentication
auth = HTTPBasicAuth()

# List of (un)registered machines
registered_machines = {}
todo_machines = {}
first_call_to_shade = True
shelve_db = None


# Update objects to be persisted
def _update_persisted_objects():
    global shelve_db, registered_machines, todo_machines
    if not shelve_db is None:
        shelve_db['registered_machines'] = registered_machines
        shelve_db['todo_machines'] = todo_machines


# Get shade library credentials
def _get_shade_auth():
    """Return shade credentials"""
    options = dict(
        auth_type="None",
        auth=dict(endpoint="http://localhost:6385/",)
    )
    if os.environ.get('OS_AUTH_URL'):
        options['auth_type'] = "password"
        options['auth'] = dict(
            username=os.getenv('OS_USERNAME', ""),
            password=os.getenv('OS_PASSWORD', ""),
            auth_url=os.getenv('OS_AUTH_URL', ""),
            project_name=os.getenv('OS_PROJECT_NAME', ""),
            domain_id=os.getenv('OS_USER_DOMAIN_NAME', ""),
        )
    return options


# Compute it only once
shade_opts = _get_shade_auth()


# HTTP Authentication
@auth.verify_password
def verify_password(username, password):
    global shade_opts
    app.logger.debug('******************** Checking user {} password {}'.format(username, password))

    # No auth aka keystone not configured: service is left unsecured
    if shade_opts.get('auth_type', None) == "None":
        # Authorized access
        return True

    # Keystone authentication required
    if shade_opts.get('auth_type', None) == "password":
        my_auth = _get_shade_auth()
        my_auth['auth']['username'] = username
        my_auth['auth']['password'] = password
        # TODO: see if the following line should be uncommented and add
        # more security but simple HTTP Auth only supports user:passwd
        # my_auth['auth']['project_name'] = os.getenv('OS_PROJECT_NAME', "")
        try:
            cloud = shade.operator_cloud(**my_auth)
            machines = cloud.list_machines()
        except Exception as e:
            app.logger.error('verify_password Got exception: {}'.format(e))
            return False
        # Authorized access
        return True
    # Unauthorized access
    return False


# Alternate authentication solution which allows
# access to incoming request informations
# using @requires_auth annotations for REST entrypoints
# below instead of @auth.login_required
def requires_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        global shade_opts
        # Keystone authentication required
        if shade_opts.get('auth_type', None) == "password":
            auth = request.authorization
            if not auth:  # no header set
                app.logger.error('requires_auth no auth info from {}'.format(
                    request.remote_addr))
                abort(401)
            if not verify_password(auth.username, auth.password):
                app.logger.error('requires_auth bad auth info from {} user {}'.format(
                    request.remote_addr, auth.username))
                abort(401)
        return f(*args, **kwargs)
    return decorated


def _find_machine(mac_addr):
    global registered_machines
    app.logger.debug('******************** Looking for machine with MAC address {}'.format(mac_addr))
    if not mac_addr:
        return None
    for key, value in registered_machines.items():
        if mac_addr in value.get('nics', []):
            app.logger.debug('Found {} in {}'.format(mac_addr, key))
            return key
    return None


def _patch_machine(uuid, vid, changes):
    global registered_machines, shade_opts
    # Convert unicode to string
    # uuid = uuid.encode('ascii', 'ignore')
    app.logger.error('==================== _patch_machine {} {} {}'.format(uuid, vid, changes))
    patch = []
    if 'name' in changes:
        registered_machines[uuid]['kvm-name'] = changes['name']
    if 'virt-uuid' in changes:
        registered_machines[uuid]['virt-uuid'] = changes['virt-uuid']
    if 'vnc_host' in changes and 'vnc_port' in changes:
        registered_machines[uuid]['vnc-info'] = "{}:{}".format(
            changes['vnc_host'], changes['vnc_port'])

    # TODO: see later as it seems like changing name always lead to error 406
    if 'name1' in changes:
        patch.append({
            'op': 'replace',
            'path': '/name',
            'value': changes['name']
        })
    if 'bmc_user' in changes:
        patch.append({
            'op': 'add',
            'path': '/driver_info/ipmi_username',
            'value': changes['bmc_user']
        })
    if 'bmc_password' in changes:
        patch.append({
            'op': 'add',
            'path': '/driver_info/ipmi_password',
            'value': changes['bmc_password']
        })
    if 'bmc_host' in changes:
        patch.append({
            'op': 'add',
            'path': '/driver_info/ipmi_address',
            'value': changes['bmc_host']
        })
    if 'bmc_port' in changes:
        patch.append({
            'op': 'add',
            'path': '/driver_info/ipmi_port',
            'value': changes['bmc_port']
        })
    if 'roles' in changes:
        patch.append({
            'op': 'add',
            'path': '/extra/roles',
            'value': changes['roles']
        })
    if len(patch) > 0:
        cloud = shade.operator_cloud(**shade_opts)
        cloud.patch_machine(uuid, patch)
    return True


# Retrieve baremetal informations via shade library
def _get_shade_infos():
    global registered_machines, todo_machines, shade_opts
    """Retrieve inventory utilizing Shade"""
    app.logger.error('==================== _get_shade_infos')
    try:
        cloud = shade.operator_cloud(**shade_opts)
        machines = cloud.list_machines()
        app.logger.error('Found {} machines'.format(len(machines)))
        for machine in machines:
            app.logger.debug('Machine: {}'.format(machine))
            if 'properties' not in machine:
                machine = cloud.get_machine(machine['uuid'])

            new_machine = {}
            if machine['name'] is None:
                name = machine['uuid']
                new_machine['name_from_uuid'] = True
            else:
                name = machine['name']
                new_machine['name_from_uuid'] = False

            app.logger.debug('-----> Parsing machine infos')
            keys = machine.keys()
            keys.sort()
            for key in keys:
                value = machine[key]
                if key in ['extra']:
                    dict_value = {}
                    v = value.get('all', None)
                    if v:
                        v = ast.literal_eval(v)
                        dict_value['all'] = v
                    v = value.get('roles')
                    if v:
                        dict_value['roles'] = v
                    value = dict_value

                # Only keep usefull informations
                if key not in ['links', 'ports']:
                    new_machine[key] = value
                    app.logger.debug('Parsing key={} Value={}'.format(key, value))

            # NOTE(TheJulia): Collect network information, enumerate through
            # and extract important values, presently MAC address. Once done,
            # return the network information to the inventory.
            nics = cloud.list_nics_for_machine(machine['uuid'])
            new_nics = []
            for nic in nics:
                if 'address' in nic:
                    new_nics.append(nic['address'])
            new_machine['nics'] = new_nics
            new_machine['addressing_mode'] = "dhcp"
            # Machine has just been discovered, store it
            if not new_machine['uuid'] in registered_machines:
                new_machine['agent-stored-ts'] = time.time()
                new_machine['agent-stored'] = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
                app.logger.debug('-----> New machine stored: {}'.format(new_machine))
                registered_machines[new_machine['uuid']] = new_machine
            else:
                # Store UUID for later use
                uuid = new_machine['uuid']
                new_machine['agent-last-seen-ts'] = time.time()
                new_machine['agent-last-seen'] = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
                # Machine was previously discovered
                app.logger.debug('-----> Merging new machine: {} {} with former data {}'.format(
                    new_machine, '\n++++++++++\n----------\n', registered_machines[uuid]))
                # Remove common values
                for key, value in registered_machines[uuid].items():
                    if key in new_machine and new_machine[key] == value:
                        del new_machine[key]
                # Update changed values
                for key, value in new_machine.items():
                    app.logger.error('Updating key {} old {} new {}'.format(
                        key, registered_machines[uuid].get(key, ""), value))
                    registered_machines[uuid][key] = value
                    new_machine['agent-last-modified-ts'] = time.time()
                    new_machine['agent-last-modified'] = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            # Check if machine changes have been requested
            modified = []
            for key, value in todo_machines.items():
                app.logger.error('Machine vid {} needs to be updated with {}'.format(
                    key, pprint.pformat(value)))
                rkey = _find_machine(value.get('mac_addr', None))
                # Machine with same MAC address has been found
                if rkey:
                    # Patch was successfull
                    if _patch_machine(rkey, key, value):
                        modified.append(key)
            # Remove patched machines
            for key in modified:
                del todo_machines[key]

        for uuid, machine in registered_machines.items():
            app.logger.error('Checking machine uuid {}  => {}'.format(uuid, pprint.pformat(machine)))
            mstate = machine.get('provision_state', None)
            app.logger.error('Checking for state: {}'.format(mstate))
            try:
                if mstate == 'enroll':
                    app.logger.error('Changing to state: {}'.format('manage'))
                    state_res = cloud.node_set_provision_state(uuid, 'manage')
                    app.logger.error('Changing node state {} gave {}'.format(uuid, pprint.pformat(state_res)))
                elif mstate == 'manageable':
                    app.logger.error('Changing to state: {}'.format('provide'))
                    state_res = cloud.node_set_provision_state(uuid, 'provide')
                    app.logger.error('Changing node state {} gave {}'.format(uuid, pprint.pformat(state_res)))
                elif mstate == 'available':
                    app.logger.error('Changing to state: {}'.format('active'))
                    state_res = cloud.node_set_provision_state(uuid, 'active')
                    app.logger.error('Changing node state {} gave {}'.format(uuid, pprint.pformat(state_res)))
            except Exception as e:
                app.logger.error('Got exception changing node to state {}: {}'.format(mstate, e))

        # Update objects to be persisted
        _update_persisted_objects()

    except Exception as e:
        app.logger.error('Got exception in _get_shade_infos: {}'.format(e))


# Try to restore state from shelve backup or JSON bootstrapping file
try:
    # Retrieve base directory of Python script
    script_base_dir = os.path.dirname(os.path.realpath(__file__))
    script_filename = os.path.basename(__file__)
    # Shelve file will be stored in same directory with the prefix of Python
    # script name (without .py extension) with additional .db extension
    shelve_file = os.path.join(script_base_dir, os.path.splitext(script_filename)[0] + ".db")
    has_shelve = os.path.isfile(shelve_file)
    # Retrieve saved variables if they exist in shelve store
    if has_shelve:
        # Check proper access (but may be this should have failed in the shelve.open call above)
        if not os.access(shelve_file, os.R_OK):
            app.logger.error('Can not read saved state from: {}'.format(shelve_file))
        else:
            app.logger.error('Restoring saved state from: {}'.format(shelve_file))
            shelve_db = shelve.open(shelve_file, writeback=True)
            # Restore persited objects into current memory
            registered_machines = shelve_db.get('registered_machines', {})
            todo_machines = shelve_db.get('todo_machines', {})
            # Empty list of machines, call shade to get update from Ironic current state
            if len(registered_machines.keys()) == 0 and first_call_to_shade:
                _get_shade_infos()
                first_call_to_shade = False
    else:
        # No shelve backup but may be a JSON bootstrapping status file can be found
        bootstrap_file = os.path.join(script_base_dir, os.path.splitext(script_filename)[0] + ".json")
        has_bootstrap = os.path.isfile(bootstrap_file)
        if has_bootstrap:
            if not os.access(bootstrap_file, os.R_OK):
                app.logger.error('Can not read bootstrap state from: {}'.format(bootstrap_file))
            else:
                app.logger.error('Restoring bootstrap state from: {}'.format(bootstrap_file))
                data = {}
                # Load JSON informations into local data object
                with open(bootstrap_file) as bootstrap_fd:
                    data = json.load(bootstrap_fd)
                    bak_extension = time.strftime("_%Y-%m-%d-%H-%M-%S.bak")
                    # Moving file so it does not get reparsed on next restart
                    os.rename(bootstrap_file, os.path.splitext(bootstrap_file)[0] + bak_extension)
                app.logger.debug('Restored bootstrap data: {}'.format(pprint.pformat(data)))
                # 1st call performed right away at start call shade to get update from Ironic current state
                if first_call_to_shade:
                    _get_shade_infos()
                    first_call_to_shade = False
                    # JSON needs to be merged into Ironic structures
                    if len(data.keys()) != 0:
                        for k, v in data.items():
                            machine_uuid = v.get('ironic-uuid')
                            # We can not do much without ironic-uuid information
                            if not machine_uuid:
                                app.logger.error('Can not process machine {}: (missing ironic-uuid) {}'.format(k, pprint.pformat(v)))
                            else:
                                # Get the Ironic informations corresponding to current UUID
                                shade_machine = registered_machines.get(machine_uuid)
                                if not shade_machine:
                                    app.logger.error('Can not retrieve machine {} UUID {}'.format(k, machine_uuid))
                                else:
                                    # Restore defaults attributes
                                    m_changes = {'name': k, 'virt-uuid': v.get('virt-uuid')}
                                    vnc_infos = v.get('vnc-info', '').split(':')
                                    # If VNC information is retrieved it need to be re-splitted for proper processing
                                    if len(vnc_infos) == 2:
                                        m_changes['vnc_host'] = vnc_infos[0]
                                        m_changes['vnc_port'] = vnc_infos[1]
                                    roles = v.get('extra/roles')
                                    if roles:
                                        m_changes['roles'] = roles
                                    app.logger.debug('Updating bootstrap registered_machines: {}'.format(pprint.pformat(m_changes)))
                                    # Call same procedure than when machine is 1st registered into register-helper utility
                                    _patch_machine(machine_uuid, v.get('virt-uuid'), m_changes)
                                    app.logger.debug('Restored bootstrap registered_machines: {}'.format(pprint.pformat(shade_machine)))
    app.logger.debug('Restored registered_machines: {}'.format(pprint.pformat(registered_machines)))
    app.logger.debug('Restored todo_machines: {}'.format(pprint.pformat(todo_machines)))
except Exception as e:
    app.logger.error('Got exception while restoring state: {}'.format(e))

# 1st call performed right away at start call shade to get update from Ironic current state
if first_call_to_shade:
    _get_shade_infos()
    first_call_to_shade = False

# Update objects to be persisted
_update_persisted_objects()

# Define and  start asynchronous scheduler after
# registering job
scheduler = BackgroundScheduler()
job = scheduler.add_job(_get_shade_infos, 'interval', seconds=30)
scheduler.start()


# GET full dump of agent infos
@app.route('/dump')
@requires_auth
def get_dump():
    return jsonify({
        'todo': todo_machines,
        'registered': registered_machines,
    })


# GET request handler to list machines registered but not handled yet by Ironic
@app.route('/waiting')
@requires_auth
def get_waiting():
    return jsonify(todo_machines)


# GET request handler to list already registered machines
@app.route('/machines')
@requires_auth
def get_machines():
    # Copy dictionnary
    ret = {}
    for k, v in registered_machines.items():
        vname = v.get('kvm-name')
        if not vname:
            continue
        ret[vname] = v
    return jsonify(ret)


# GET request handler to get current status of machines
@app.route('/status')
@requires_auth
def get_status():
    ret = {}
    for k, v in registered_machines.items():
        vname = v.get('kvm-name')
        if not vname:
            continue
        ret[vname] = {'ironic-uuid': k}
        for f in ['vnc-info', 'virt-uuid', 'power_state', 'target_power_state',
                  'provision_state', 'last_error', 'properties/cpus',
                  'properties/local_gb', 'properties/memory_mb', 'target_provision_state',
                  'extra/roles', 'extra/all/macs', 'extra/all/interfaces/eth0/ip',
                  'agent-created', 'agent-last-seen', 'agent-last-modified',
                  ]:
            if '/' not in f:
                v1 = v.get(f)
            else:
                v1 = None
                v2 = v
                for f1 in f.split('/'):
                    v2 = v2.get(f1)
                    if not v2:
                        break
#                    if f1 == 'all':
#                        try:
#                            v2 = ast.literal_eval(v2)
#                        except Exception as e:
#                            v2 = None
#                            break
                if v2:
                    v1 = v2
            if v1:
                ret[vname][f] = v1
    return jsonify(ret)


# POST request handler to register new machines
@app.route('/register', methods=['POST'])
@requires_auth
def add_machine():
    global todo_machines
    app.logger.error("Request headers: {}".format(pprint.pformat(request.headers)))
    app.logger.error("Request data: {}".format(pprint.pformat(request.get_data())))
    mime_header = request.headers.get('Content-Type', "dummy/dummy").split('/')
    # return '', 301
    newm = request.get_json()
    app.logger.error("adding machine: {}".format(newm))
    todo_machines[newm['virt-uuid']] = newm
    # Update objects to be persisted
    _update_persisted_objects()
    return '', 201


# PUT request handler to modify machines
@app.route('/update/<machineid>', methods=['PUT'])
@requires_auth
def update_machine(machineid):
    app.logger.debug("updating machine: {}".format(machineid))
    return '', 204


# DELETE request handler to unregister machines
@app.route('/unregister/<machineid>', methods=['DELETE'])
@requires_auth
def delete_machine(machineid):
    app.logger.debug("removing machine: {}".format(machineid))
    return '', 200


# Called on each incoming request
@app.before_request
def _log_request_info():
    app.logger.debug('Method: %s', request.method)
    app.logger.debug('Headers: %s', request.headers)
    app.logger.debug('Body: %s', request.get_data())
    if request.method in ['DELETE', 'POST', 'PUT']:
        mime_header = request.headers.get('Content-Type', "dummy/dummy").split('/')
        if (mime_header[0] not in ['text', 'application'] or
                mime_header[1] not in ['csv', 'x-csv', 'json', 'yaml', 'x-yaml']):
            abort(400)
