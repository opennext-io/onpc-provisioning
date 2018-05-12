from ansible.plugins.action import ActionBase


class ActionModule(ActionBase):

    def run(self, tmp=None, task_vars=None):

        if task_vars is None:
            task_vars = dict()

        result = super(ActionModule, self).run(tmp, task_vars)

        fres = {}
        res = {}
        result = self._execute_module(
            module_name='setup',
            module_args={},
            task_vars=task_vars,
            tmp=tmp)
        res['mounts'] = result.get(
            'ansible_facts',
            {}).get(
            'ansible_mounts',
            {})
        res['device_links'] = result.get(
            'ansible_facts',
            {}).get(
            'ansible_device_links',
            {})
        res['devices'] = {
            k: v for k, v in result.get(
                'ansible_facts',
                {}).get(
                'ansible_devices',
                {}).iteritems() if not k.startswith("loop")
        }

        # Retrieve device ID of mount points retrieve via facts
        mount_points = {}
        mount_devices = {}
        for mnt in res['mounts']:
            mount_points[mnt['mount']] = {
                'path': mnt['mount'],
                'size_available': mnt['size_available'],
                'size_total':  mnt['size_total'],
                }
            mount_point_stat = self._execute_module(
                module_name='stat',
                module_args={
                    'path': mnt['mount'],
                    'follow': True,
                    'get_checksum': False,
                    },
                task_vars=task_vars,
                tmp=tmp)
            mount_points[mnt['mount']]['device'] = mount_point_stat.get(
                'stat',
                {}).get(
                    'dev')
            mount_devices[mount_points[mnt['mount']]['device']] = dict(
                mount_points[mnt['mount']]
            )
        fres['before'] = mount_points.values()
        fres['errors'] = []

        # Check each disk size requirements in turn
        for v in self._task.args.get('paths_sizes_requirements', []):
            lpath = v.get('path')
            lsize = v.get('size')
            # Mandatory path dict key
            # TODO: may be fill error in else
            if lpath:
                # Get stat on this file/path to retrieve device ID
                path_stat = self._execute_module(
                    module_name='stat',
                    module_args={
                        'path': lpath,
                        'follow': True,
                        'get_checksum': False,
                        },
                    task_vars=task_vars,
                    tmp=tmp)
                ldev = path_stat.get('stat', {}).get('dev')
                tdev = mount_devices.get(ldev)
                # Find matching device ID in remote mount
                # points discovered above
                if not tdev:
                    # Should never happen but who knows ...
                    lerror = ('Error retrieving device' +
                              ' for path={}').format(lpath)
                    fres['errors'].append(lerror)
                else:
                    rsize = tdev.get('size_available', 0)
                    # Check if required size can be allocated in mount point
                    if rsize < lsize:
                        lerror = ('Not enough space on {} for path {}:' +
                                  ' {} required {} remaining').format(
                            tdev.get('path'),
                            lpath,
                            lsize,
                            rsize)
                        fres['errors'].append(lerror)
                    else:
                        mount_devices[ldev]['size_available'] -= lsize

        fres['after'] = mount_devices.values()
        fres['changed'] = False
        fres['failed'] = len(fres['errors']) > 0
        return fres
