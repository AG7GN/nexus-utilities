#!/bin/bash

# Extracts Connection events for VNC server activity occuring in the past 24 hours
# and emails results via patmail.sh and pat
#
# Usage: vnc-server-activity.sh [email-address[,email-address]...]
#

VERSION="1.2.1"

# Pat and patmail.sh must be installed.  If they are not, exit.
command -v pat >/dev/null 2>&1 || exit 1
command -v patmail.sh >/dev/null 2>&1 || exit 1

declare -i AGE=24 # Specify Age in hours.  Events older than AGE will not be included.
# Mail VNC Server login activity for last 24 hours.
# MAILTO can contain multiple destination email addresses.  Separate addresses with a
# comma.
MAILTO="${1:-w7ecg.wecg@gmail.com}"
FILTERED="$(mktemp)"
OUTFILE="$(mktemp)"
TEMPOUT="$(mktemp)"
NOW="$(date +'%s')"

# Check VNC logs
FILES="/var/log/user.log"
if [[ -s $FILES ]]
then
   echo "VNC Activity" > $OUTFILE
	grep -h Connections $FILES* 2>/dev/null 1>$FILTERED
   if [[ -s $FILTERED ]]
   then
      while IFS= read -r LINE
      do
         D="${LINE%% $HOSTNAME*}" # Extract date from log message
         E="$(date --date="$D" +'%s')" # Convert date to epoch
         if (( $E > $NOW ))
         then # Now in new year.  (Log messages don't include year, so it's a problem going from December to January.)
            # Account for leap years
            date -d $(date +%Y)-02-29 >/dev/null 2>&1 && SEC_IN_YEAR=$((60 * 60 * 24 * 366)) || SEC_IN_YEAR=$((60 * 60 * 24 * 365))
            # Make it December again ;)
            E=$(( $E - $SEC_IN_YEAR ))
         fi
         let DIFF=$NOW-$E
         if [ $DIFF -le $(($AGE * 3600)) ] # Print events <= 24 hours old
         then
            echo "$LINE" | tr -s ' ' | cut -d' ' -f1,2,3,7- >> $TEMPOUT
         fi
      done < $FILTERED
   fi
else
   echo "No $FILES log" >> $OUTFILE
fi
if [ -s $TEMPOUT ]
then
   cat $TEMPOUT | sort | uniq >> $OUTFILE
else
   echo "     No VNC activity." >> $OUTFILE
fi

> $TEMPOUT

# Check DWService logs
FILES="/usr/share/dwagent/dwagent.log"
if [[ -s $FILES ]]
then
   echo -e "\nDWService Activity" >> $OUTFILE
   grep -Ihs session $FILES* | grep "^[0-9]*" 2>/dev/null 1>$FILTERED
   if [[ -s $FILTERED ]]
   then
      while IFS= read -r LINE
      do
         D="${LINE%% INFO*}" # Extract date from log message
         E="$(date --date="$D" +'%s')" # Convert date to epoch
         if [ $E -gt $NOW ]
         then # Now in new year.  (Log messages don't include year, so it's a problem going from December to January.)
            # Account for leap years
            date -d $(date +%Y)-02-29 >/dev/null 2>&1 && SEC_IN_YEAR=$((60 * 60 * 24 * 366)) || SEC_IN_YEAR=$((60 * 60 * 24 * 365))
            # Make it December again ;)
            E=$(( $E - $SEC_IN_YEAR ))
         fi
         let DIFF=$NOW-$E
         if [ $DIFF -le $(($AGE * 3600)) ] # Print events <= 24 hours old
         then
            echo "$LINE" | tr -s ' ' | cut -d' ' -f1,2,5- >> $TEMPOUT
         fi
      done < $FILTERED
   fi
else
   echo -e "\nNo $FILES log" >> $OUTFILE
fi
if [ -s $TEMPOUT ]
then
   cat $TEMPOUT | sort | uniq >> $OUTFILE
else
   echo "     No DWService activity." >> $OUTFILE
fi
#[ -s $OUTFILE ] || echo "No VNC activity." > $OUTFILE
#{
#   echo To: $MAILTO
#   echo From: $MAILFROM
#   echo Subject: $HOSTNAME VNC Server activity for 24 hours preceding `date`
#   echo 
#   cat $OUTFILE
#} | /usr/sbin/ssmtp $MAILTO
#cat $OUTFILE
cat $OUTFILE | $(command -v patmail.sh) $MAILTO "$HOSTNAME remote access activity for 24 hours preceding `date`" telnet
rm $OUTFILE
rm $FILTERED
rm $TEMPOUT

