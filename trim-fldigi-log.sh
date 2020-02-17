#!/bin/bash

VERSION="1.5.1"

#
# This script removes log files from the $HOME/.fldigi* folder(s) and subfolders.
# Files with "last modified" timestamps that are before the specified time 
# are deleted.  Files that match *log*, except for file names containing 'logbook'
# are examined.
#
# Parameter 1 is a date reference e.g. "10 days ago" or "1 hour ago"
#
# This script will not run if Fldigi is running.  It must be run
# prior to starting Fldigi.  If you want to run it every time you start
# Fldigi on a Raspberry Pi, change the File Properties
# of the Fldigi menu item to run this script and then Fldigi as follows:
#
# Click on the Raspberry and navigate to the menu containing Fldigi.  Right-click
# on the Fldigi menu item, click Properties then select the "Desktop Entry" tab.
# In the Command field, replace 'fldigi' with the following (change the
# time period as desired):
#
# sh -c '/usr/local/bin/trim-fldigi-log.sh "1 week ago"';fldigi ...
#
# Leave the "Execute in Terminal" box unchecked, then click OK.
#

# Exit if Fldigi is already running
pgrep fldigi >/dev/null && exit 0

DIRS="$HOME/.fldigi $HOME/.fldigi-left $HOME/.fldigi-right"

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
	for F in ${D}/*log*
	do
		[ -e $F ] && [ -f "$F" ] && ! [[ $F =~ logbook ]] || continue
		STAMP="$(stat -c %Y $F)"
		[ $STAMP -lt $(date -u --date="$1" +%s) ] && rm -f $F
	done
done


