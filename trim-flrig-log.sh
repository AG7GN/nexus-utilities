#!/bin/bash

VERSION="1.5.1"

# This script removes log files from the $HOME/.flrig* folder(s) and subfolders.
# Files with "last modified" timestamps that are before the specified time 
# are deleted.  Files that match *log*, except for file names containing 'logbook'
# are examined.
#
# Parameter 1 is a date reference e.g. "10 days ago" or "1 hour ago"
#
# This script will not run if Flrig is running.  It must be run
# prior to starting Flrig.  If you want to run it every time you start
# Flrig on a Raspberry Pi, change the File Properties
# of the Flrig menu item to run this script and then Flrig as follows:
#
# Click on the Raspberry and navigate to the menu containing Flrig.  Right-click
# on the Flrig menu item, click Properties then select the "Desktop Entry" tab.
# In the Command field, replace 'flrig' with the following (change the
# time period as desired):
#
# sh -c '/usr/local/bin/trim-flrig-log.sh "1 week ago"';flrig ...
#
# Leave the "Execute in Terminal" box unchecked, then click OK.
#

# Exit if Fldigi is already running
pgrep flrig >/dev/null && exit 0

DIRS="$HOME/.flrig $HOME/.flrig-left $HOME/.flrig-right"

# Some error checking
[[ $1 == "" ]] && { echo >&2 "Supply a date reference, e.g. \"10 days ago\" or \"1 hour ago\""; exit 1; }

if ! date -u --date="$1" 1>/dev/null 2>&1
then # Invalid date requested 
	exit 1
elif [[ ${1^^} != "NOW" && $(($(date -u --date="$1" +%s))) > $(($(date -u +%s))) ]]
then # Date requested is in the future; invalid
	echo >&2 "Date requested is in the future."
	exit 1
fi

for D in $DIRS
do
	for F in ${D}/*txt*
	do
		[ -e "$F" ] && [ -f "$F" ] || continue
		STAMP="$(stat -c %Y $F)"
		[ $STAMP -lt $(date -u --date="$1" +%s) ] && rm -f $F
	done
done


