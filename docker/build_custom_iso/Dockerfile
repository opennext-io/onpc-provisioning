FROM alpine:latest

MAINTAINER Olivier Bourdon <obourdon@opennext.io>

LABEL Description="This image is used to build custom ISOs" \
		Vendor="OpenNext" \
		Version="0.1"

ADD custom_iso.sh /root/

RUN apk update && \
	apk add bash py2-pip py2-virtualenv sed wget xorriso

CMD bash /root/custom_iso.sh $opts $iso
