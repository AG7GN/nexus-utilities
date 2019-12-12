#!/bin/bash

VERSION="1.5"

# This script trims the fsq_audit_log.txt file
# in the ~/.fldigi/temp folder by removing content added aded earlier 
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
# sh -c '/usr/local/bin/trim-fsq-audit.sh "30 days ago"';fldigi ...
#
# Leave the "Execute in terminal" box unchecked, then click OK.
#
# If you want to run both this script and the trim-fsq-heard.sh script in the
# same way, use this line in the Command field instead (change the time period
# as desired):
#
# sh -c '/usr/local/bin/trim-fsq-audit.sh "30 days ago";/usr/local/bin/trim-fsq-heard.sh "1 hour ago"';fldigi
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
	echo >&2 "Date requested is in the future.  No change to file."
	exit 1
fi
TARGET="$(date -u --date="$1" +"%s")"

for D in $DIRS
do
	AUDIT="$D/fsq_audit_log.txt"

	# Some error checking
	[ -e "$AUDIT" ] && [ -f "$AUDIT" ] && [ -s "$AUDIT" ] || continue # $AUDIT not found or empty

	T="$(mktemp)"
	declare -i LINE=0
	while read -r ATAG1 ATAG2 DTAG TTAG REMAINDER
	do
		(( LINE++ ))
		if [[ "$ATAG1 $ATAG2" == "Audit log:" ]]
		then # Determine logged timestamp
			TTAG="$(echo $TTAG | tr -d ',')" # strip out comma
			DTAG="$(echo $DTAG | tr -d ',')" # strip out comma
			# convert to a time format that date command undertands
			TTAG="$(echo $TTAG | sed -E 's|([0-9]{2})([0-9]{2})([0-9]{2})|\1:\2:\3|')"
			STAMP="$(date -u -d"$DTAG $TTAG" +"%s")"
			if  (( TARGET < STAMP )) 
			then # Save everything after this $LINE in $AUDIT
				echo "==================================================" > $T
				tail -n +$LINE $AUDIT >> $T
				break
			fi
		fi
	done < $AUDIT
	mv $T $AUDIT
	chmod 644 $AUDIT
done


