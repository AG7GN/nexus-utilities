#!/bin/bash

VERSION="1.0.7"

# This script allows sending Winlink messages via the command line or script.
# It requires pat (a Winlink client) and the dos2unix programs.

function Usage () {
	echo
	echo "ERROR: $1"
	echo
	echo "$(basename $0) version $VERSION"
   echo
	echo "Usage: $(basename $0) To Subject Transport"
	echo 
	echo "Where:"
	echo 
	echo "   To        One or more destination email addresses, separated"
	echo "             by a comma.  Winlink addresses need only be the call sign,"
	echo "             no need to include '@winlink.org'."
	echo
	echo "   Subject   The subject of the message.  Put double quotes"
	echo "             around it if it contains spaces."
	echo
	echo "   Transport The pat transport type.  Examples:"
	echo
	echo "             telnet"
	echo "             ax25:///call-ssid"
	echo "                where call-ssid is the RMS Gateway.  Example: W7ECG-10"
	echo
	echo "             Run 'pat connect help' for more examples."
	echo 
	echo "Pass the body of the message to the script from stdin.  Examples:"
   echo 
   echo "   echo -e \"1st line of body\\n2nd line\" | $(basename $0) N0ONE \"My Subject\" telnet"
	echo "   cat myfile.txt | $(basename $0) me@example.com,W7ABC \"My Important Message\" telnet"
	echo "   $(basename $0) me@example.com,W7ABC \"My Important Message\" telnet < myfile.txt"
	echo
	exit 1
}

(( $# != 3 )) && Usage "3 arguments are required."

PAT="$(command -v pat)" 
[[ $? == 0 ]] || Usage "pat winlink client is not installed."
UNIX2DOS="$(command -v unix2dos)"
[[ $UNIX2DOS == "" ]] && Usage "dos2unix tools are not installed."

PATDIR="$HOME/.wl2k"
CALL="$(cat $PATDIR/config.json | grep "\"mycall\":" | tr -d ' ",' | cut -d: -f2)"
[[ $CALL == "" ]] && Usage "Could not obtain call sign from $PATDIR/config.json.  Is pat configured?"
OUTDIR="$PATDIR/mailbox/$CALL/out"

TO="$1"
SUBJECT="$2"

[[ $TO =~ "," ]] || TO="$TO\n"

export EDITOR=ed
TFILE="$(mktemp)"
echo -e "$CALL\n$TO\n\n$SUBJECT" | pat compose 2>/dev/null 1> $TFILE
MSG="$(grep "MID:" $TFILE | tr -d ' \t' | cut -d':' -f3)" 
[[ $MSG == "" ]] && Usage "Could not find the MID (Message ID)"
MSG="$OUTDIR/$MSG.b2f"
sed -i -e 's/<No message body>//' $MSG
$UNIX2DOS -q $MSG
cat - > $TFILE
$UNIX2DOS -q $TFILE
COUNT="$(wc -c $TFILE | cut -d' ' -f1)" 
cat $TFILE >> $MSG
rm $TFILE
sed -i -e "s/^Body: .*/Body: $COUNT/" $MSG
$PAT --send-only --event-log /dev/null connect $3 >/dev/null 2>&1
exit $?

