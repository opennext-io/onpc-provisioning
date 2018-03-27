#!/usr/bin/python
# -*- coding: utf-8 -*-
#
# (c) 2016, Roman Belyakovsky <ihryamzik () gmail.com>
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

from __future__ import absolute_import, division, print_function
__metaclass__ = type


ANSIBLE_METADATA = {'metadata_version': '1.1',
                    'status': ['stableinterface'],
                    'supported_by': 'community'}

DOCUMENTATION = '''
---
module: interfaces_file
short_description: Tweak settings in /etc/network/interfaces files
extends_documentation_fragment: files
description:
     - Manage (add, remove, change) individual interface options in an interfaces-style file without having
       to manage the file as a whole with, say, M(template) or M(assemble). Interface has to be presented in a file.
     - Read information about interfaces from interfaces-styled files
     - Remove interface if state set to absent and option and value are omitted
version_added: "2.4"
options:
  src:
    description:
      - Path to the source interfaces file
    default: /etc/network/interfaces
  dest:
    description:
      - Path to the interfaces file
    default: /etc/network/interfaces
  iface:
    description:
      - Name of the interface, required for value changes, option remove or interface removal
  option:
    description:
      - Name of the option, required for value changes or option remove
  value:
    description:
      - If I(option) is not presented for the I(interface) and I(state) is C(present) option will be added.
        If I(option) already exists and is not C(pre-up), C(up), C(post-up) or C(down), it's value will be updated.
        C(pre-up), C(up), C(post-up) and C(down) options can't be updated, only adding new options, removing existing
        ones or cleaning the whole option set are supported
  backup:
    description:
      - Create a backup file including the timestamp information so you can get
        the original file back if you somehow clobbered it incorrectly.
    type: bool
    default: 'no'
  state:
    description:
      - If set to C(absent) the option or section will be removed if present instead of created.
        If set to C(absent) and no option nor value is set, interface will be deleted
    default: "present"
    choices: [ "present", "absent" ]

notes:
   - If option is defined multiple times last one will be updated but all will be deleted in case of an absent state
requirements: []
author: "Roman Belyakovsky (@hryamzik)"
'''

RETURN = '''
src:
    description: source file/path
    returned: success
    type: string
    sample: "/etc/network/interfaces"
dest:
    description: destination file/path
    returned: success
    type: string
    sample: "/etc/network/interfaces"
ifaces:
    description: interfaces dictionary
    returned: success
    type: complex
    contains:
      ifaces:
        description: interface dictionary
        returned: success
        type: dictionary
        contains:
          eth0:
            description: Name of the interface
            returned: success
            type: dictionary
            contains:
              address_family:
                description: interface address family
                returned: success
                type: string
                sample: "inet"
              method:
                description: interface method
                returned: success
                type: string
                sample: "manual"
              mtu:
                description: other options, all values returned as strings
                returned: success
                type: string
                sample: "1500"
              pre-up:
                description: list of C(pre-up) scripts
                returned: success
                type: list
                sample:
                  - "route add -net 10.10.10.0/24 gw 10.10.10.1 dev eth1"
                  - "route add -net 10.10.11.0/24 gw 10.10.11.1 dev eth2"
              up:
                description: list of C(up) scripts
                returned: success
                type: list
                sample:
                  - "route add -net 10.10.10.0/24 gw 10.10.10.1 dev eth1"
                  - "route add -net 10.10.11.0/24 gw 10.10.11.1 dev eth2"
              post-up:
                description: list of C(post-up) scripts
                returned: success
                type: list
                sample:
                  - "route add -net 10.10.10.0/24 gw 10.10.10.1 dev eth1"
                  - "route add -net 10.10.11.0/24 gw 10.10.11.1 dev eth2"
              down:
                description: list of C(down) scripts
                returned: success
                type: list
                sample:
                  - "route del -net 10.10.10.0/24 gw 10.10.10.1 dev eth1"
                  - "route del -net 10.10.11.0/24 gw 10.10.11.1 dev eth2"
...
'''

EXAMPLES = '''
# Set eth1 mtu configuration value to 8000
- interfaces_file:
    dest: /etc/network/interfaces.d/eth1.cfg
    iface: eth1
    option: mtu
    value: 8000
    backup: yes
    state: present
  register: eth1_cfg

# Move lo configuration from /etc/network/interfaces
# to /etc/network/interfaces.d/lo.cfg
- interfaces_file:
    src: /etc/network/interfaces
    dest: /etc/network/interfaces.d/lo.cfg
    iface: lo
    state: move
'''

import os
import re
import tempfile

from ansible.module_utils.basic import AnsibleModule
from ansible.module_utils._text import to_bytes


def lineDict(line):
    return {'line': line, 'line_type': 'unknown'}


def optionDict(line, iface, option, value):
    return {'line': line, 'iface': iface, 'option': option, 'value': value, 'line_type': 'option'}


def getValueFromLine(s):
    spaceRe = re.compile(r'\s+')
    for m in spaceRe.finditer(s):
        pass
    valueEnd = m.start()
    option = s.split()[0]
    optionStart = s.find(option)
    optionLen = len(option)
    valueStart = re.search(r'\s', s[optionLen + optionStart:]).end() + optionLen + optionStart
    return s[valueStart:valueEnd]


def read_interfaces_file(module, filename):
    f = open(filename, 'r')
    return read_interfaces_lines(module, f)


# Function to keep comments within the same line
#
def handle_comment(comment, idict, lines):
    idict['comment'] = comment
    # We will be looking into previous lines
    # starting by the last one
    idx = -1
    # Just remove the trailing \n to get the list or previous comments
    rcomments = comment.strip('\n').split('\n')
    # Revert the list for proper and easy handling
    rcomments.reverse()
    for elem in rcomments:
        # Previous line is not a comment or does not match
        # => stop processing
        if (lines[idx]['line_type'] != 'comment' or
                elem not in lines[idx]['line']):
            break
        # We can get rid of this comment line as it is now
        # properly attached to idict
        del(lines[idx])


def read_interfaces_lines(module, line_strings):
    lines = []
    ifaces = {}
    currently_processing = None
    i = 0
    comment = ""
    for line in line_strings:
        i += 1
        words = line.split()
        if len(words) < 1:
            lines.append({'line': line, 'line_type': 'empty'})
            comment = ""
            continue
        if words[0][0] == "#":
            lines.append({'line': line, 'line_type': 'comment'})
            comment = "%s%s" % (comment, line)
            continue
        if words[0] == "mapping":
            # currmap = calloc(1, sizeof *currmap);
            lines.append(lineDict(line))
            currently_processing = "MAPPING"
        elif words[0] == "source":
            lines.append(lineDict(line))
            currently_processing = "NONE"
        elif words[0] == "source-dir":
            lines.append(lineDict(line))
            currently_processing = "NONE"
        elif words[0] == "iface":
            iface_name = words[1]
            currif = ifaces.get(
                iface_name,
                {
                    "pre-up": [],
                    "up": [],
                    "down": [],
                    "post-up": []
                })
            if len(comment) > 0:
                handle_comment(comment, currif, lines)
                comment = ""
            try:
                currif['address_family'] = words[2]
            except IndexError:
                currif['address_family'] = None
            try:
                currif['method'] = words[3]
            except IndexError:
                currif['method'] = None

            ifaces[iface_name] = currif
            lines.append({'line': line, 'iface': iface_name, 'line_type': 'iface', 'params': currif})
            currently_processing = "IFACE"
        elif words[0] == "auto":
            prefix = re.sub("auto .*\\n$", "", line)
            for w in words[1:]:
                # Should not occur if interface file complies to official rules
                # But we stop processing auto interfaces in this case
                if w.find('#') >= 0:
                    break
                iface_name = w
                currif = ifaces.get(
                    iface_name,
                    {
                        "pre-up": [],
                        "up": [],
                        "down": [],
                        "post-up": []
                    })
                currif['auto'] = True
                ifaces[iface_name] = currif
                # Behaves like multiple dedicated lines instead of all on one
                nline = '%sauto %s\n' % (prefix, w)
                # Auto lines are also linked to an interface
                line_dict = {'line': nline, 'iface': w, 'line_type': 'auto'}
                if len(comment) > 0:
                    handle_comment(comment, line_dict, lines)
                lines.append(line_dict)
            if len(comment) > 0:
                comment = ""
            currently_processing = "NONE"
        elif words[0] == "allow-":
            lines.append(lineDict(line))
            currently_processing = "NONE"
        elif words[0] == "no-auto-down":
            lines.append(lineDict(line))
            currently_processing = "NONE"
        elif words[0] == "no-scripts":
            lines.append(lineDict(line))
            currently_processing = "NONE"
        else:
            if currently_processing == "IFACE":
                option_name = words[0]
                # TODO: if option_name in currif.options
                value = getValueFromLine(line)
                lines.append(optionDict(line, iface_name, option_name, value))
                if option_name in ["pre-up", "up", "down", "post-up"]:
                    currif[option_name].append(value)
                else:
                    currif[option_name] = value
            elif currently_processing == "MAPPING":
                lines.append(lineDict(line))
            elif currently_processing == "NONE":
                lines.append(lineDict(line))
            else:
                module.fail_json(msg="misplaced option %s in line %d" % (line, i))
                return None, None
    return lines, ifaces


def setInterfaceOption(module, lines, iface, ifaces, option, raw_value, state, bridge_options = None):
    value = str(raw_value)
    changed = False
    removed_lines = None

    iface_lines = [item for item in lines if "iface" in item and item["iface"] == iface]

    if len(iface_lines) < 1:
        # interface not found
        module.fail_json(msg="Error: interface %s not found" % iface)
        return changed, None, None

    iface_options = list(filter(lambda i: i['line_type'] == 'option', iface_lines))
    target_options = list(filter(lambda i: i['option'] == option, iface_options))

    if state == "present":
        if len(target_options) < 1:
            changed = True
            # add new option
            last_line_dict = iface_lines[-1]
            lines = addOptionAfterLine(option, value, iface, lines, last_line_dict, iface_options)
        else:
            if option in ["pre-up", "up", "down", "post-up"]:
                if len(list(filter(lambda i: i['value'] == value, target_options))) < 1:
                    changed = True
                    lines = addOptionAfterLine(option, value, iface, lines, target_options[-1], iface_options)
            else:
                # if more than one option found edit the last one
                if target_options[-1]['value'] != value:
                    changed = True
                    target_option = target_options[-1]
                    old_line = target_option['line']
                    old_value = target_option['value']
                    prefix_start = old_line.find(option)
                    optionLen = len(option)
                    old_value_position = re.search(r"\s+".join(old_value.split()), old_line[prefix_start + optionLen:])
                    start = old_value_position.start() + prefix_start + optionLen
                    end = old_value_position.end() + prefix_start + optionLen
                    line = old_line[:start] + value + old_line[end:]
                    index = len(lines) - lines[::-1].index(target_option) - 1
                    lines[index] = optionDict(line, iface, option, value)
    elif state == "absent" or state == "move":
        if len(target_options) >= 1:
            if option in ["pre-up", "up", "down", "post-up"] and value is not None and value != "None":
                for target_option in filter(lambda i: i['value'] == value, target_options):
                    changed = True
                    lines = list(filter(lambda ln: ln != target_option, lines))
            else:
                changed = True
                for target_option in target_options:
                    lines = list(filter(lambda ln: ln != target_option, lines))
        # Interface to be deleted from config file
        if not option:
            changed = True
            lines = list(filter(lambda ln: ln.get('iface') != iface, lines))
            removed_lines = iface_lines
    elif state == "bridge":
        changed = True
        lines = list(filter(lambda ln: ln.get('iface') != iface, lines))
        removed_lines = iface_lines
        res_lines = []
        # Copy the removed lines corresponding to the interface to be moved
        # to bridge and  change method to 'manual'
        # Add comment to mention that this is the 'ethernet' interface part
        # of th bridge
        for ln in removed_lines:
            if ln.get('line_type') == 'auto':
                new_ln = dict(ln)
                comment = new_ln.get('comment')
                if comment:
                    new_ln['comment'] = re.sub("\n$", " (ethernet)\n", comment)
                res_lines.append(new_ln)
            elif ln.get('line_type') == 'iface':
                new_method = 'manual'
                new_ln = dict(ln)
                comment = new_ln.get('comment')
                if comment:
                    new_ln['comment'] = re.sub("\n$", " (ethernet)\n", comment)
                new_ln['line'] = re.sub(ln.get('params', {}).get('method', '')  + '$', new_method, ln.get('line'))
                new_ln['params']['method'] = new_method
                res_lines.append(new_ln)

        # Add the 'bridge_ports' option with interface name as its value
        new_opt = 'bridge_ports'
        new_ln = {
            'line': "\t%s %s\n" % (new_opt, iface),
            'iface': iface,
            'line_type': 'option',
            'option': new_opt,
            'value': iface,
        }
        removed_lines.append(new_ln)

        # Add the other bridge options and store new bridge name
        br_name = None
        for opt in bridge_options:
            for k in opt:
                if k == 'name':
                    br_name = opt[k]
                else:
                    new_ln = {
                        'line': "\t%s %s\n" % (k, opt[k]),
                        'iface': iface,
                        'line_type': 'option',
                        'option': k,
                        'value': opt[k],
                    }
                    removed_lines.append(new_ln)

        # Check that all necessary information is provided
        if not br_name:
            module.fail_json(msg="Error: migrating interface to bridge requires at least a bridge 'name' option")

        # Modify all interfaces name references to new bridge name
        for ln in removed_lines:
            if ln.get('line_type') in ['auto', 'iface']:
                comment = ln.get('comment')
                if comment:
                    ln['comment'] = re.sub("\n$", " (bridge)\n", comment)
            if ln.get('option') != 'bridge_ports':
                ln['line'] = re.sub(iface, br_name, ln.get('line'))
            ln['iface'] = br_name
            res_lines.append(ln)
        removed_lines = res_lines
    else:
        module.fail_json(msg="Error: unsupported state %s, has to be either present, absent, move or bridge" % state)

    return changed, lines, removed_lines


def addOptionAfterLine(option, value, iface, lines, last_line_dict, iface_options):
    last_line = last_line_dict['line']
    prefix_start = last_line.find(last_line.split()[0])
    suffix_start = last_line.rfind(last_line.split()[-1]) + len(last_line.split()[-1])
    prefix = last_line[:prefix_start]

    if len(iface_options) < 1:
        # interface has no options, ident
        prefix += "    "

    line = prefix + "%s %s" % (option, value) + last_line[suffix_start:]
    option_dict = optionDict(line, iface, option, value)
    index = len(lines) - lines[::-1].index(last_line_dict)
    lines.insert(index, option_dict)
    return lines


def write_changes(module, lines, dest):
    tmpfd, tmpfile = tempfile.mkstemp()
    f = os.fdopen(tmpfd, 'wb')
    f.write(to_bytes(''.join(lines), errors='surrogate_or_strict'))
    f.close()
    module.atomic_move(tmpfile, os.path.realpath(dest))


def select_lines_and_comments(lines):
    res = []
    for ln in lines:
        if 'line' in ln:
            comment = ln.get('comment') or ln.get('params', {}).get('comment')
            if comment:
                res.append(comment)
            res.append(ln['line'])
    return res


def main():
    module = AnsibleModule(
        argument_spec=dict(
            src=dict(default=None, required=False, type='path'),
            dest=dict(default='/etc/network/interfaces', required=False, type='path'),
            iface=dict(required=False),
            option=dict(required=False),
            value=dict(required=False),
            backup=dict(default='no', type='bool'),
            state=dict(default='present', choices=['present', 'absent', 'move', 'bridge']),
            bridge_options=dict(default=None, required=False, type='list'),
        ),
        add_file_common_args=True,
        supports_check_mode=True
    )

    src = module.params['src']
    dest = module.params['dest']
    iface = module.params['iface']
    option = module.params['option']
    value = module.params['value']
    backup = module.params['backup']
    state = module.params['state']
    bridge_options = module.params['bridge_options']

    if src is None:
        src = dest

    if option is not None and iface is None:
        module.fail_json(msg="Inteface must be set if option is defined")

    if option is not None and state == "present" and value is None:
        module.fail_json(msg="Value must be set if option is defined and state is 'present'")

    if state == "move" and (iface is None or option is not None or value is not None):
        module.fail_json(msg="Iface must be set if state is 'move' but not option nor value")

    if state == "bridge" and (iface is None or option is not None or value is not None or bridge_options is None):
        module.fail_json(msg="Iface and bridge_options must be set if state is 'bridge' but not option nor value")

    lines, ifaces = read_interfaces_file(module, src)

    changed = False

    if option is not None:
        changed, lines, _ = setInterfaceOption(module, lines, iface, ifaces, option, value, state)
    elif state == 'absent' or state == 'move' or state == 'bridge':
        changed, lines, removed_lines = setInterfaceOption(module, lines, iface, ifaces, None, None, state, bridge_options)
        if state == 'bridge' and src == dest:
            lines = lines + removed_lines
            removed_lines = []

    if changed:
        _, ifaces = read_interfaces_lines(module, [d['line'] for d in lines if 'line' in d])

    if changed and not module.check_mode:
        if backup:
            module.backup_local(src)
        if src == dest:
            write_changes(module, select_lines_and_comments(lines), dest)
        else:
            if backup and os.path.exists(dest) and os.path.isfile(dest):
                module.backup_local(dest)
            write_changes(module, select_lines_and_comments(lines), src)
            write_changes(module, select_lines_and_comments(removed_lines), dest)

    module.exit_json(dest=dest, changed=changed, ifaces=ifaces)


if __name__ == '__main__':
    main()
