#!/bin/bash

# Script to print Nexus version and other info

VERSION="1.1.1"

if [ ! -s /boot/nexus.txt ]
then
	echo "NEXUS_VERSION=unknown" > /tmp/nexus.txt
	sudo mv /tmp/nexus.txt /boot/nexus.txt
fi

source /boot/nexus.txt

yad --center --title="Nexus Version - version $VERSION" --info --borders=30 --no-wrap \
    --text="<b>Nexus Version $NEXUS_VERSION</b>" --buttons-layout=center --button=Close:0
exit 0
