#!/bin/bash

# Extracts Connection events for VNC server activity occuring in the past 24 hours
# and emails results via patmail.sh and pat
#
# Usage: vnc-server-activity.sh [email-address[,email-address]...]
#

VERSION="1.1.1"

# Pat and patmail.sh must be installed.  If they are not, exit.
command -v pat >/dev/null 2>&1 || exit 1
command -v patmail.sh >/dev/null 2>&1 || exit 1

declare -i AGE=24 # Specify Age in hours.  Events older than AGE will not be included.
FILES="/var/log/user.log*"
# Mail VNC Server login activity for last 24 hours.
# MAILTO can contain multiple destination email addresses.  Separate addresses with a
# comma.
MAILTO="${1:-w7ecg.wecg@gmail.com}"
FILTERED="$(mktemp)"
OUTFILE="$(mktemp)"
grep -h Connections $FILES 2>/dev/null 1>$FILTERED
NOW="$(date +'%s')"
if [ -s $FILTERED ]
then 
	while IFS= read -r LINE
	do
		D="${LINE%% $HOSTNAME*}" # Extract date from log message
		E="$(date --date="$D" +'%s')" # Convert date to epoch
      if [ $E -gt $NOW ]
		then # Now in new year.  (Log messages don't include year, so it's a problem going from December to January.)
		   # Account for leap years
		   date -d $(date +%Y)-02-29 >/dev/null 2>&1 && SEC_IN_YEAR=$((60 * 60 * 24 * 366)) || SEC_IN_YEAR=$((60 * 60 * 24 * 365))
		   # Make it December again ;)
			E=$(( $E - $SEC_IN_YEAR ))
		fi
		let DIFF=$NOW-$E
		if [ $DIFF -le $(($AGE * 3600)) ] # Print events <= AGE hours old
		then # Print selected fields only
      	echo "$LINE" | tr -s ' ' | cut -d' ' -f1,2,3,7- >> $OUTFILE
		fi
	done < $FILTERED
fi
[ -s $OUTFILE ] || echo "No VNC Server activity." > $OUTFILE
#{
#   echo To: $MAILTO
#   echo From: $MAILFROM
#   echo Subject: $HOSTNAME VNC Server activity for 24 hours preceding `date`
#   echo 
#   cat $OUTFILE
#} | /usr/sbin/ssmtp $MAILTO

cat $OUTFILE | sort | uniq | $(command -v patmail.sh) $MAILTO "$HOSTNAME VNC Server activity for 24 hours preceding `date`" telnet
rm $OUTFILE
rm $FILTERED
