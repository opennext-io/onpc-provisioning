#!/usr/bin/env python

from __future__ import (absolute_import, division, print_function)
__metaclass__ = type


ANSIBLE_METADATA = {
    'metadata_version': '1.0',
    'status': ['preview'],
    'supported_by': 'OpenNext'
}

import random
import re

from ansible.errors import AnsibleFilterError
from ansible.module_utils.six import iteritems, string_types, integer_types

# ---- Ansible filters ----
class FilterModule(object):
    ''' random MAC address filter '''

    def filters(self):
        return {
            'random_mac': self.random_mac
        }

    def random_mac(self, value):
        if not isinstance(value, string_types):
            raise AnsibleFilterError('Invalid value type (%s) for random_mac (%s)' % (type(value), value))
        value = value.lower()
        mac_items = value.split(':')
        if len(mac_items) > 5:
            raise AnsibleFilterError('Invalid value (%s) for random_mac: 5 colon(:) separated items max' % value)
        err = ""
        for mac in mac_items:
            if len(mac) == 0:
                err += ",empty item"
                continue
            if not re.match('[a-f0-9]{2}', mac):
                err += ",%s not hexa byte" % mac
        err = err.strip(',')
        if len(err):
            raise AnsibleFilterError('Invalid value (%s) for random_mac: %s' % (value, err))
        # Generate random float and make it int
        v = int(random.random() * 10.0**10)
        # Select first n chars to complement input prefix
        remain = 2 * (6 - len(mac_items))
        rnd = ('%x' % v)[:remain]
        return value + re.sub(r'(..)',r':\1',rnd)
