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
from ansible.module_utils.six import string_types

# ---- Ansible filters ----
class FilterModule(object):
    ''' hostvars entries filter '''

    def filters(self):
        return {
            'hostvars_filter': self.hostvars_filter
        }

    def hostvars_filter(self, value, include_keys = [], exclude_keys = []):
        if not isinstance(value, string_types):
            raise AnsibleFilterError('Invalid value type (%s) for hostvars_filter (%s)' % (type(value), value))
        if not isinstance(include_keys, list):
            raise AnsibleFilterError('Invalid matching keys type (%s) for hostvars_filter (%s)' % (type(include_keys), include_keys))
        if not isinstance(exclude_keys, list):
            raise AnsibleFilterError('Invalid non matching keys type (%s) for hostvars_filter (%s)' % (type(exclude_keys), exclude_keys))
        if len(include_keys) == 0 and len(exclude_keys) == 0:
            raise AnsibleFilterError('List of matching and non matching keys can not be both empty for hostvars_filter')
        if len(include_keys) > 0:
            not_strings = list(filter(lambda x: not isinstance(x, string_types), include_keys))
            if len(not_strings) > 0:
                raise AnsibleFilterError('Invalid matching keys type (not strings) for hostvars_filter items (%s)' % (not_strings))
        if len(exclude_keys) > 0:
            not_strings = list(filter(lambda x: not isinstance(x, string_types), exclude_keys))
            if len(not_strings) > 0:
                raise AnsibleFilterError('Invalid non matching keys type (not strings) for hostvars_filter items (%s)' % (not_strings))
        ret = {}
        try:
            to_parse = json.loads(value)
            # Level 1 is host key
            for k,v in iter(to_parse.items()):
                lret = {}
                # Level 2 is entries to be matched
                for lk,lv in iter(v.items()):
                    # Exclude has precedence over include
                    to_exclude = False
                    for m in exclude_keys:
                        if re.match(m, lk):
                            to_exclude = True
                            break
                    # Go on with next key, this one is excluded
                    if to_exclude:
                        continue
                    if len(include_keys):
                        for m in include_keys:
                            if re.match(m, lk):
                                lret[lk] = lv
                                break
                    else:
                        lret[lk] = lv
                if len(lret.keys()) > 0:
                    ret[k] = lret
        except Exception as e:
            raise AnsibleFilterError('Invalid JSON value for hostvars_filter (%s): %s' % (not_strings, e)) 
        return ret

