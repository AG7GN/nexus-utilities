#!/bin/bash

VERSION="1.5.1"

#
# This script removes log files from the $HOME/.flmsg* folder(s) and subfolders.
# Files with "last modified" timestamps that are before the specified time 
# are deleted.  Files that match the elements of $SDIRS below are examined.
#
# Parameter 1 is a date reference e.g. "10 days ago" or "1 hour ago"
#
# This script will not run if Flmsg is running.  It must be run
# prior to starting Flmsg.  If you want to run it every time you start
# Flmsg on a Raspberry Pi, change the File Properties
# of the Flmsg menu item to run this script and then Flmsg as follows:
#
# Click on the Raspberry and navigate to the menu containing Flmsg.  Right-click
# on the Flmsg menu item, click Properties then select the "Desktop Entry" tab.
# In the Command field, replace 'flmsg' with the following (change the
# time period as desired):
#
# sh -c '/usr/local/bin/trim-flmsg-log.sh "1 week ago"';flmsg ...
#
# Leave the "Execute in Terminal" box unchecked, then click OK.
#

# Exit if Flmsg is already running
pgrep flmsg >/dev/null && exit 0

DIRS="$HOME/.nbems $HOME/.nbems-left $HOME/.nbems-right"
SDIRS="/log_files/* /temp_files/* /ICS/*.htm /ICS/*.csv /ICS/messages/* /ICS/messages/archive/* /ICS/log_files/* /WRAP/auto/* /WRAP/recv/* /WRAP/send/* /TRANSFERS/* /FLAMP/*log* /FLAMP/rx/* /FLAMP/tx/* /ARQ/files/* /ARQ/mail/* /ARQ/recv/* /ARQ/send/*"

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
	for S in $SDIRS
	do
		for F in ${D}${S}
		do
			[ -e "$F" ] && [ -f "$F" ] || continue
			STAMP="$(stat -c %Y $F)"
			[ $STAMP -lt $(date -u --date="$1" +%s) ] && rm -f $F
		done
	done
done


