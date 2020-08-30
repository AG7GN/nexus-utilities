#!/bin/bash

# Script to print Nexus version and other info

VERSION="1.1.0"

[ -s /boot/nexus.txt ] || exit 0

source /boot/nexus.txt

yad --center --title="Nexus Version - version $VERSION" --info --borders=30 --no-wrap \
    --text="<b>Nexus Version $NEXUS_VERSION</b>" --buttons-layout=center --button=Close:0
exit 0
