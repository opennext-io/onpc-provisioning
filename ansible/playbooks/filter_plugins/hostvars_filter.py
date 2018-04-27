#!/usr/bin/env python

from __future__ import (absolute_import, division, print_function)
__metaclass__ = type


ANSIBLE_METADATA = {
    'metadata_version': '1.0',
    'status': ['preview'],
    'supported_by': 'OpenNext'
}

import json
import re

from ansible.errors import AnsibleFilterError
from ansible.module_utils.six import iteritems, string_types, integer_types

# ---- Ansible filters ----
class FilterModule(object):
    ''' hostvars entries filter '''

    def filters(self):
        return {
            'hostvars_filter': self.hostvars_filter
        }

    def hostvars_filter(self, value, matching_keys = []):
        if not isinstance(value, string_types):
            raise AnsibleFilterError('Invalid value type (%s) for hostvars_filter (%s)' % (type(value), value))
        if not isinstance(matching_keys, list):
            raise AnsibleFilterError('Invalid keys type (%s) for hostvars_filter (%s)' % (type(matching_keys), matching_keys))
        not_strings = filter(lambda x: not isinstance(x, string_types), matching_keys)
        if len(not_strings) > 0:
            raise AnsibleFilterError('Invalid keys type (not strings) for hostvars_filter items (%s)' % (not_strings))
        if len(matching_keys) == 0:
            raise AnsibleFilterError('Empty list of keys specified for hostvars_filter items')
        ret = {}
        try:
            to_parse = json.loads(value)
            # Level 1 is host key
            for k,v in to_parse.iteritems():
                lret = {}
                # Level 2 is entries to be matched
                for lk,lv in v.iteritems():
                    for m in matching_keys:
                        if re.match(m, lk):
                            lret[lk] = lv
                            continue
                if len(lret.keys()) > 0:
                    ret[k] = lret
        except Exception as e:
            raise AnsibleFilterError('Invalid JSON value for hostvars_filter (%s): %s' % (not_strings, e)) 
        return ret

