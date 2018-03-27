#!/bin/bash

if [ ! -f /etc/hosts.tmpl ]; then
	echo -e "127.0.0.1\tlocalhost" >/etc/hosts.tmpl
fi

eval $(awk -F. '{d="";for(i=2;i<=NF;i++) d=sprintf("%s.%s",d,$i);printf"host=%s\ndomain=%s\n",$1,d ; exit}' /etc/hostname)
fqdn=${host}${domain}
echo "$fqdn" >/etc/hostname

(echo "# Dynamically added at startup by $0 script" ; \
 ip a | awk -v h=${fqdn}=${host} 'BEGIN{n=0;split(h,a,"=");} /^[1-9][0-9]*: .* state UP/{ok=1;itf=$2;gsub(":$","",itf);next} /^[1-9]/{ok=0} ok && /inet /{split($2,b,"/");n++;printf "%s\t",b[1]; if (n==1) {printf "%s ",a[1]; };printf "%s-%s\n",a[2],itf}' ; \
 echo '# Standard entries' ; \
 cat /etc/hosts.tmpl \
) | sed -e 's/=/ /g' >/etc/hosts
