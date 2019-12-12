#!/bin/bash

VERSION="1.5"

# This script trims the fsq_heard_log.txt file
# in the ~/.fldigi/temp folder by removing lines with timestamps earlier 
# than the supplied time (e.g. "10 days ago" or "1 hour ago").
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
# sh -c '/home/pi/trim-fsq-heard.sh "1 week ago"';fldigi ...
#
# Leave the "Execute in Terminal" box unchecked, then click OK.
#
# If you want to run both this script and the trim-fsq-audit.sh script in the
# same way, use this line in the Command field instead (change the time period as
# desired):
#
# sh -c '/usr/local/bin/trim-fsq-audit.sh "30 days ago";/usr/local/bin/trim-fsq-heard.sh "1 week ago"';fldigi
#

# Exit if Fldigi is already running
pgrep fldigi >/dev/null && exit 0

DIRS="$HOME/.fldigi/temp $HOME/.fldigi-left/temp $HOME/.fldigi-right/temp"

[[ $1 == "" ]] && { echo >&2 "Supply a date reference, e.g. \"10 days ago\" or \"1 hour ago\""; exit 1; }
if ! date -u --date="$1" 1>/dev/null
then # Invalid date requested 
	echo >&2 "Invalid date requested.  Supply a date reference, e.g. \"10 days ago\" or \"1 hour ago\""
	exit 1
elif [[ ${1^^} != "NOW" && $(($(date -u --date="$1" +%s))) > $(($(date -u +%s))) ]]
then # Date requested is in the future; invalid
	echo >&2 "Date requested is in the future.  No changes made."
	exit 1
fi

for D in $DIRS
do
	HEARD="$D/fsq_heard_log.txt"
	[ -e "$HEARD" ] && [ -f "$HEARD" ] && [ -s "$HEARD" ] || continue # $HEARD not found or empty
	T="$(mktemp)"
	cat > $T << EOF
==================================================
Heard log: $(date -u --date="$1" "+%Y%m%d, %H%M%S")
==================================================
EOF
	awk -v d=$(date -u --date="$1" "+%Y%m%d,%H%M%S") '($1 "," $2) > d' $HEARD | grep -v "^Heard\|^===" >> $T
	mv $T $HEARD			
	chmod 644 $HEARD
done


