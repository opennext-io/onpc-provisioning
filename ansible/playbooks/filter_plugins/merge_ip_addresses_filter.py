#!/usr/bin/env python

from __future__ import (absolute_import, division, print_function)
__metaclass__ = type


ANSIBLE_METADATA = {
    'metadata_version': '1.0',
    'status': ['preview'],
    'supported_by': 'OpenNext'
}

from netaddr import *

from ansible.errors import AnsibleFilterError
from ansible.module_utils.six import iteritems, string_types, integer_types

def cmd_ip_addresses(x, y):

    if ',' in x:
        a = IPAddress(x.split(',')[0])
    else:
        a = IPAddress(x)
    if ',' in y:
        b = IPAddress(y.split(',')[0])
    else:
        b = IPAddress(y)
    if a > b:
        return 1
    if a < b:
        return -1
    return 0

# ---- Ansible filters ----
class FilterModule(object):
    ''' IP adresses and ranges merge filter '''

    def __init__(self):
        self.ip_dict = {}
        self.network_list = []

    def filters(self):
        return {
            'merge_ip_addresses': self.merge_ip_addresses
        }

    # Check validity of IP network string
    # Expected format: x.x.x.x/y.y.y.y
    def is_valid_network(self, network_str):
        try:
            ok_net = IPNetwork(network_str)
        except Exception as e:
            return False
        self.network_list.append(ok_net)
        return True

    # Only accept valid IP addresses or pairs of valid addresses
    # separated by a comma
    def is_valid_ip_or_range(self, ip_str):
        ips = ip_str.split(',')
        if len(ips) > 2:
            return False
        tmp_ips = []
        for ip in ips:
            try:
                ok_ip = IPAddress(ip)
            except Exception as e:
                return False
            tmp_ips.append(ok_ip)
        if len(ips) == 1:
            self.ip_dict[ip_str] = tmp_ips
        else:
            self.ip_dict[ip_str] = list(iter_iprange(ips[0], ips[1]))
        return True

    def merge_ip_addresses(self, ips, networks = []):
        # Check network parameter type
        if not isinstance(networks, list):
            raise AnsibleFilterError('Invalid value type (%s) for merge_ip_addresses network list parameter (%s)' % (type(networks), networks))
        # Networks list with CIDR notation
        if len(networks) > 0:
            # Check validity of individual network list elements
            bad_networks = filter(lambda x: not self.is_valid_network(x), networks)
            if len(bad_networks) > 0:
                raise AnsibleFilterError('Invalid network addresses (not a valid network address) for merge_ip_addresses network list parameter (%s)' % (bad_networks))
        # Check ips parameter type
        if not isinstance(ips, list):
            raise AnsibleFilterError('Invalid value type (%s) for merge_ip_addresses IP list (%s)' % (type(ips), ips))
        if len(ips) == 0:
            raise AnsibleFilterError('IP addresses list can not be both empty for merge_ip_addresses')
        # Check individual ips list elements type
        not_strings = filter(lambda x: not isinstance(x, string_types), ips)
        if len(not_strings) > 0:
            raise AnsibleFilterError('Invalid IP address type (not strings) for merge_ip_addresses items (%s)' % (not_strings))
        # Check validity of individual ips list elements
        bad_ranges = filter(lambda x: not self.is_valid_ip_or_range(x), ips)
        if len(bad_ranges) > 0:
            raise AnsibleFilterError('Invalid IP addresses (not a valid IP address or address range) for merge_ip_addresses items (%s)' % (bad_ranges))
        # Check if single ips belong to some range ips
        single_ips = filter(lambda x: ',' not in x, self.ip_dict.keys())
        range_ips = filter(lambda x: ',' in x, self.ip_dict.keys())
        for ip in single_ips:
            # Not deleted already (safety)
            if self.ip_dict.get(ip):
                for range in range_ips:
                    if self.ip_dict[ip][0] in self.ip_dict[range]:
                        del self.ip_dict[ip]
                        break
        ret_ips = self.ip_dict.keys()
        ret_ips.sort(cmd_ip_addresses)
        return ret_ips
