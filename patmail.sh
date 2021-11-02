#!/usr/bin/env bash
#================================================================
# HEADER
#================================================================
#% SYNOPSIS
#+   ${SCRIPT_NAME} [-hv] 
#+   ${SCRIPT_NAME} TO SUBECT TRANSPORT
#+   ${SCRIPT_NAME} [-d DIRECTORY] [-m DIRECTORY] [-l FILE] 
#+                  [-f FILE] TO SUBECT TRANSPORT
#%
#% DESCRIPTION
#%   This script allows sending Winlink messages via the command line or script.
#%   It requires pat (a Winlink client) and the dos2unix program.
#%   The body of the message is supplied to the script from STDIN.  See EXAMPLES below.
#%
#% OPTIONS
#%    -h, --help                  Print this help
#%    -v, --version               Print script information
#%    -d, --dir=DIRECTORY         Path to directory containing config.json file
#%                                and mailbox directory. Default: $HOME/.config/pat
#%                                If default location, will use mailbox in 
#%                                $HOME/.local/pat/mailbox.
#%		-m, --mailbox=DIRECTORY  	 Override mailbox location. 
#% 										 Default: $HOME/.local/share/pat/mailbox
#%    -l FILE, --log=FILE         Send pat event log output to FILE.  FILE will be 
#%                                overwritten if it exists. To send output to stdout,
#%                                use /dev/stdout. Default: /dev/null
#%		-o FILE, --olog=File			 Override pat log file. 
#%											 Default: $HOME/.local/state/pat/pat.log
#%    -f FILE, --file=FILE        Attach file to message where file is full path to
#%                                file.  To attach multiple files, use multiple -f FILE
#%                                arguments, one per attached file.
#% 
#% COMMANDS (All 3 COMMANDS are required)
#%    TO                          One or more recipient email addresses 
#%                                (comma separated). Winlink email addresses 
#%                                (CALL@winlink.org) do not need to include 
#%                                '@winlink.org', just the call sign.
#%                                
#%    SUBJECT                     Email subject enclosed in "double quotes".
#%
#%    TRANSPORT                   pat transport method or alias.  For example:
#%                                   outbox
#%                                      Don't immediately send the message. Just put 
#%                                      it in the outbox.
#%                                   telnet
#%                                   ax25://portname/call-ssid
#%                                      where portname is as defined in /etc/ax25/axports
#%                                      and the same as the ax25 port configured in
#%                                      config.json. This is usually 'wl2k'.
#%
#%                                      where call-ssid is the RMS gateway.  Example:
#%                                      ax25://wl2k/W7ECG-10
#%                                   Run 'pat connect help' to see more transport
#%                                   types.
#%
#% EXAMPLES
#%    Send two lines of text to callsign N0ONE@winlink.org via telnet:
#%
#%      echo -e "1st line\n2nd line" | ${SCRIPT_NAME} N0ONE "My Subject" telnet
#%
#%    Send the contents of file 'myfile.txt' to me@example.com and W7ABC@winlink.org
#%    via telnet:
#%    
#%      cat myfile.txt | ${SCRIPT_NAME} me@example.com,W7ABC "My Important Message" telnet
#%    
#%    Send the contents of file 'myfile.txt' to W7ABC@winlink.org via telnet and log 
#%    output to stdout:
#%    
#%      cat myfile.txt | ${SCRIPT_NAME} -l /dev/stdout me@example.com,W7ABC "My Important Message" telnet
#%    
#%    Send the contents of 'myfile.txt' to me@example.com and W7ABC@winlink.org using
#%    packet radio via RMS gateway ax25://wl2k/W7ECG-10
#%
#%      ${SCRIPT_NAME} me@example.com,W7ABC "My Important Message" ax25://wl2k/W7ECG-10 < myfile.txt 
#%
#%    Same as previous example, but just put message in the outgoing mailbox:
#%
#%      ${SCRIPT_NAME} me@example.com,W7ABC "My Important Message" outbox < myfile.txt
#%
#================================================================
#- IMPLEMENTATION
#-    version         ${SCRIPT_NAME} 2.5.3
#-    author          Steve Magnuson, AG7GN
#-    license         CC-BY-SA Creative Commons License
#-    script_id       0
#-
#================================================================
#  HISTORY
#     20190920 : Steve Magnuson : Script creation
#     20200204 : Steve Magnuson : Added script template
#     20200227 : Steve Magnuson : Added option to send pat log text to a file or stdout
#     20200730 : Steve Magnuson : Added ability to specify pat config & mailbox folder
#     20211102 : Steve Magnuson : Updated default pat config folder for pat 0.12
# 
#================================================================
#  DEBUG OPTION
#    set -n  # Uncomment to check your syntax, without execution.
#    set -x  # Uncomment to debug this shell script
#
#================================================================
# END_OF_HEADER
#================================================================

SYNTAX=false
DEBUG=false
Optnum=$#

#============================
#  FUNCTIONS
#============================

function TrapCleanup() {
  [[ -d "${TMPDIR}" ]] && rm -rf "${TMPDIR}/"
  exit 0
}

function SafeExit() {
  # Delete temp files, if any
  [[ -d "${TMPDIR}" ]] && rm -rf "${TMPDIR}/"
  trap - INT TERM EXIT
  exit
}

function ScriptInfo() { 
	HEAD_FILTER="^#-"
	[[ "$1" = "usage" ]] && HEAD_FILTER="^#+"
	[[ "$1" = "full" ]] && HEAD_FILTER="^#[%+]"
	[[ "$1" = "version" ]] && HEAD_FILTER="^#-"
	head -${SCRIPT_HEADSIZE:-99} ${0} | grep -e "${HEAD_FILTER}" | \
	sed -e "s/${HEAD_FILTER}//g" \
	    -e "s/\${SCRIPT_NAME}/${SCRIPT_NAME}/g" \
	    -e "s/\${SPEED}/${SPEED}/g" \
	    -e "s/\${DEFAULT_PORTSTRING}/${DEFAULT_PORTSTRING}/g"
}

function Usage() { 
	printf "Usage: "
	ScriptInfo usage
	exit
}

function Die () {
	echo "${*}"
	SafeExit
}

#============================
#  FILES AND VARIABLES
#============================

# Set Temp Directory
# -----------------------------------
# Create temp directory with three random numbers and the process ID
# in the name.  This directory is removed automatically at exit.
# -----------------------------------
TMPDIR="/tmp/${SCRIPT_NAME}.$RANDOM.$RANDOM.$RANDOM.$$"
(umask 077 && mkdir "${TMPDIR}") || {
  Die "Could not create temporary directory! Exiting."
}

  #== general variables ==#
SCRIPT_NAME="$(basename ${0})" # scriptname without path
SCRIPT_DIR="$( cd $(dirname "$0") && pwd )" # script directory
SCRIPT_FULLPATH="${SCRIPT_DIR}/${SCRIPT_NAME}"
SCRIPT_ID="$(ScriptInfo | grep script_id | tr -s ' ' | cut -d' ' -f3)"
SCRIPT_HEADSIZE=$(grep -sn "^# END_OF_HEADER" ${0} | head -1 | cut -f1 -d:)
VERSION="$(ScriptInfo version | grep version | tr -s ' ' | cut -d' ' -f 4)" 

#============================
#  PARSE OPTIONS WITH GETOPTS
#============================
  
#== set short options ==#
SCRIPT_OPTS=':d:f:l:m:o:hv-:'

#== set long options associated with short one ==#
typeset -A ARRAY_OPTS
ARRAY_OPTS=(
	[help]=h
	[version]=v
	[dir]=d
	[file]=f
	[log]=l
	[olog]=o
	[mailbox]=m
)

declare -a ATTACHMENTS=()

LONG_OPTS="^($(echo "${!ARRAY_OPTS[@]}" | tr ' ' '|'))="

# Parse options
while getopts ${SCRIPT_OPTS} OPTION
do
	# Translate long options to short
	if [[ "x$OPTION" == "x-" ]]
	then
		LONG_OPTION=$OPTARG
		LONG_OPTARG=$(echo $LONG_OPTION | egrep "$LONG_OPTS" | cut -d'=' -f2-)
		LONG_OPTIND=-1
		[[ "x$LONG_OPTARG" = "x" ]] && LONG_OPTIND=$OPTIND || LONG_OPTION=$(echo $OPTARG | cut -d'=' -f1)
		[[ $LONG_OPTIND -ne -1 ]] && eval LONG_OPTARG="\$$LONG_OPTIND"
		OPTION=${ARRAY_OPTS[$LONG_OPTION]}
		[[ "x$OPTION" = "x" ]] &&  OPTION="?" OPTARG="-$LONG_OPTION"
		
		if [[ $( echo "${SCRIPT_OPTS}" | grep -c "${OPTION}:" ) -eq 1 ]]; then
			if [[ "x${LONG_OPTARG}" = "x" ]] || [[ "${LONG_OPTARG}" = -* ]]; then 
				OPTION=":" OPTARG="-$LONG_OPTION"
			else
				OPTARG="$LONG_OPTARG";
				if [[ $LONG_OPTIND -ne -1 ]]; then
					[[ $OPTIND -le $Optnum ]] && OPTIND=$(( $OPTIND+1 ))
					shift $OPTIND
					OPTIND=1
				fi
			fi
		fi
	fi

	# Options followed by another option instead of argument
	if [[ "x${OPTION}" != "x:" ]] && [[ "x${OPTION}" != "x?" ]] && [[ "${OPTARG}" = -* ]]
	then 
		OPTARG="$OPTION" OPTION=":"
	fi

	# Finally, manage options
	case "$OPTION" in
		h) 
			ScriptInfo full
			exit 0
			;;
		v) 
			ScriptInfo version
			exit 0
			;;
		d)
			PAT_DIR="$OPTARG"
			;;
		f)
			ATTACHMENTS+=("$OPTARG")
			;;
		l)
			EVENT_LOG="$OPTARG"
			;;
		m)
			MBOX="$OPTARG"
			;;
		m)
			LOG_FILE="$OPTARG"
			;;
		:) 
			Die "${SCRIPT_NAME}: -$OPTARG: option requires an argument"
			;;
		?) 
			Die "${SCRIPT_NAME}: -$OPTARG: unknown option"
			;;
	esac
done
shift $((${OPTIND} - 1)) ## shift options

#============================
#  MAIN SCRIPT
#============================

# Trap bad exits with cleanup function
trap SafeExit EXIT INT TERM

# Exit on error. Append '||true' when you run the script if you expect an error.
#set -o errexit

# Check Syntax if set
$SYNTAX && set -n
# Run in debug mode, if set
$DEBUG && set -x 

(( $# != 3 )) && Die "3 parameters, TO, SUBJECT and TRANSPORT are required."

PAT="$(command -v pat)" 
[[ $? == 0 ]] || Die "pat winlink client is not installed."
UNIX2DOS="$(command -v unix2dos)"
[[ $? == 0 ]] || Die "dos2unix tools are not installed."

if [[ -z $PAT_DIR ]]
then
	if [[ -d $HOME/.config/pat ]]
	then
		PAT_DIR="$HOME/.config/pat"
		[[ -d $MBOX ]] || MBOX="$HOME/.local/share/pat/mailbox"
		LOG_FILE="$HOME/.local/state/pat/pat.log"
	elif [[ -d $HOME/.wl2k ]]
	then
		PAT_DIR="$HOME/.wl2k"
		[[ -d $MBOX ]] || MBOX="$PAT_DIR/mailbox"
		LOG_FILE="$PAT_DIR/pat.log"
	else
		Die "Could not find a pat configuration. Run 'pat configure' to set up."
	fi
fi
[[ -d "$PAT_DIR" ]] || Die "Directory $PAT_DIR does not exist or is not a directory."
PAT_CONFIG="$PAT_DIR/config.json"
[[ -d "$MBOX" ]] || Die "Mailbox directory $MBOX does not exist or is not a directory."
EVENT_LOG="${EVENT_LOG:-/dev/null}"
[[ -w "$EVENT_LOG" ]] || EVENT_LOG="/dev/null"
[[ -f "$LOG_FILE" ]] || touch "$LOG_FILE" || Die "Cannot write to log file $LOG_FILE"

CALL="$(cat $PAT_CONFIG | grep "\"mycall\":" | tr -d ' ",' | cut -d: -f2)"
[[ $CALL == "" ]] && Die "Could not obtain call sign from $PAT_CONFIG.  Is pat configured?"
OUTDIR="$MBOX/$CALL/out"

TO="$1"
SUBJECT="$2"
DELIVERY="$3"

[[ $TO =~ "," ]] || TO="$TO\n" # There's only one recipient, so append \n

echo > "$EVENT_LOG"

# Compose an empty email message
export EDITOR=ed
TFILE="${TMPDIR}/message"
HEADER="$CALL\n$TO\n\n$SUBJECT"
echo -e "$HEADER" | $PAT --config "$PAT_CONFIG" --log "$LOG_FILE" --event-log "$EVENT_LOG" --mbox $MBOX compose 2>/dev/null 1> $TFILE

MSG="$(grep "MID:" $TFILE | tr -d ' \t' | cut -d':' -f3)" 
[[ $MSG == "" ]] && Die "Could not find the MID (Message ID)"
MSG="$OUTDIR/$MSG.b2f"
sed -i -e 's/<No message body>//' $MSG
if (( ${#ATTACHMENTS[@]} ))
then # Add attached file(s) size and name to header
	for F in "${ATTACHMENTS[@]}"
	do
		if [ -s "$F" ]
		then
			SIZE=$(stat -L --printf="%s" "$F")
			HEADER="File: $SIZE ${F##*/}"
			sed -i "/^From: .*/i $HEADER" "$MSG"
		else
			rm "$MSG"
			Die "Attachment \"$F\" empty or not found. Message not posted/sent."
		fi
	done
fi
# Add carriage returns to empty message (Winlink requires this)
$UNIX2DOS -q $MSG
# Read message text from stdin
cat - > $TFILE
echo >> $TFILE
# Add carriage returns to user message (Winlink requires this)
$UNIX2DOS -q $TFILE
# Append message body to message and add character count to message (required by Winlink)
COUNT="$(wc -c $TFILE | cut -d' ' -f1)"
cat $TFILE >> $MSG
sed -i -e "s/^Body: .*/Body: $COUNT/" $MSG
if (( ${#ATTACHMENTS[@]} ))
then # Append file(s) to message
	for F in "${ATTACHMENTS[@]}"
	do
		cat "$F" >> "$MSG"
		echo -e -n "\r\n" >> "$MSG"
	done
fi

if [[ ${DELIVERY,,} != "outbox" ]]
then  # Send the message
	$PAT --config $PAT_CONFIG --mbox $MBOX --send-only --log "$LOG_FILE" --event-log "$EVENT_LOG" connect $DELIVERY >> $EVENT_LOG
	exit $?
fi
exit


