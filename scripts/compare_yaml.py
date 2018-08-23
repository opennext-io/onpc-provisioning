#!/usr/bin/env python
'''

Utility which can be used to compare sets of YAML files

Example usage:

compare_yaml.py etc/openstack_deploy/openstack_user_config.yml etc/openstack_deploy/conf.d/* -- etc/openstack_deploy/openstack_user_config.yml-ONPC

All the files to the left of the -- parameter are loaded as YAML files and merged together as left YAML data
same applies for the files on the right hand side of the -- parameter which compose the right YAML data

Both of these are then converted to ordered dictionnaries for proper comparison and submitted to unified diff

Final output shows differences

'''

import sys
import os
import yaml
import json
import pprint
import difflib

from collections import OrderedDict

script_base_dir = os.path.dirname(os.path.realpath(__file__))
working_dir = os.getcwd()

# Global list of left + right files paths
left_side_files = []
right_side_files= []
# And the associated YAML values
left_side_yaml = {}
right_side_yaml = {}

# Current list is left side
cur_list = left_side_files
for idx, a in enumerate(sys.argv):
	if idx > 0:
		# When -- is met, files are appened to right side list
		if a == '--':
			cur_list = right_side_files
			continue
		cur_file = a
		# non existent path
		if not os.path.exists(cur_file):
			if os.path.isabs(cur_file):
				print 'Error: absolute path {} does not exist'.format(cur_file)
			else:
				print 'Error: file {} does not exist'.format(
					os.path.realpath(
						os.path.join(
							os.path.dirname(os.path.realpath(cur_file)),
							cur_file
							)))
			sys.exit(1)
		# Not a file or not readable
		if not os.path.isfile(cur_file) or not os.access(cur_file, os.R_OK):
			print 'Error: {} is not a file or is not readble'.format(cur_file)
			sys.exit(1)
		# Current file appened to current list
		cur_list.append(cur_file)


# Function to merge 2 YAML values
def merge(y1, y2):
    if not isinstance(y1, dict) or not isinstance(y2, dict):
    	print 'Error: not a dictionnary'
    	sys.exit(1)
    for k, v in iter(y2.items()):
        if k not in y1:
            y1[k] = v
        else:
            y1[k] = merge(y1[k], v)
    return y1


# Function to merge 2 YAML files
def merge_yaml_files(v, files):
    for f in files:
        with open(f, 'r') as stream:
            try:
                f_yaml_data = yaml.load(stream)
                v = merge(v, f_yaml_data)
                # print 'Got YAML from {}: {}'.format(f, pprint.pformat(f_yaml_data))
            except yaml.YAMLError as exc:
            	print(exc)
            	sys.exit(1)


# When dict keys (1st element of pairs) are equal
# use value (2nd element of pairs) as second criteria
def compare_pairs(p1, p2):
    if p1[0] == p2[0]:
        return cmp(p1[1], p2[1])
    return cmp(p1[0], p2[0])


# Sort a list whose element can also be complex objects
def sorted_list(l, level=0):
	loc_list = []
	for v in l:
		if issubclass(type(v), dict):
			loc_list.append(sorted_dict(v, level+1))
		elif issubclass(type(v), list):
			loc_list.append(sorted_list(v, level+1))
		else:
			loc_list.append(v)
	return sorted(loc_list)


# Sort a dict whose values can also be complex objects
def sorted_dict(d, level=0):
	loc_list = []
	for k,v in d.items():
		if issubclass(type(v), dict):
			loc_list.append((k, sorted_dict(v, level+1)))
		elif issubclass(type(v), list):
			loc_list.append((k, sorted_list(v, level+1)))
		else:
			loc_list.append((k, v))
	return OrderedDict(sorted(loc_list, cmp=compare_pairs))


# Main body
merge_yaml_files(left_side_yaml, left_side_files)
merge_yaml_files(right_side_yaml, right_side_files)

# Convert YAML data to OrderedDict
left_dict = sorted_dict(left_side_yaml)
right_dict = sorted_dict(right_side_yaml)

# Compute differences
# as there is no pretty print for OrderedDict use
# JSON dumper which does the job
res = difflib.unified_diff(
	json.dumps(left_dict, indent=4).split('\n'),
	json.dumps(right_dict, indent=4).split('\n')
	)
# Print contextual differences
for s in res:
	print s
