#!/bin/bash

if [ ! -f /etc/hosts.tmpl ]; then
	echo -e "127.0.0.1\tlocalhost" >/etc/hosts.tmpl
fi

host=$(cat /etc/hostname)
fqdn=${host}.vagrantup.com

(echo "# Dynamically added at startup by $0 script" ; \
 ip a | awk -v h=${fqdn}=${host},${host}-priv 'BEGIN{n=0;split(h,a,",");} /^[1-9][0-9]*: .* state UP/{ok=1;next} /^[1-9]/{ok=0} ok && /inet /{split($2,b,"/");n++;printf "%s\t%s\n",b[1],a[n]}' ; \
 echo '# Standard entries' ; \
 cat /etc/hosts.tmpl \
) | sed -e 's/=/ /g' >/etc/hosts
