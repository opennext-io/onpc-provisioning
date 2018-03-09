#!/bin/bash

while true; do
	if nc -w 2 $1 $2 >/dev/null 2>&1; then
		vncviewer ${1}:$2
	fi
	sleep 2
done
