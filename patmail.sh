#!/bin/bash
#================================================================
# HEADER
#================================================================
#% SYNOPSIS
#+   ${SCRIPT_NAME} [-hv] TO SUBECT TRANSPORT
#+   ${SCRIPT_NAME} [-l FILE] TO SUBECT TRANSPORT
#%
#% DESCRIPTION
#%   This script allows sending Winlink messages via the command line or script.
#%   It requires pat (a Winlink client) and the dos2unix program.
#%   The body of the message is supplied to the script from STDIN.  See EXAMPLES below.
#%
#% OPTIONS
#%    -h, --help                  Print this help
#%    -v, --version               Print script information
#%    -l FILE, --log=FILE         Send pat diagnostic output to FILE.  FILE will be 
#%                                overwritten if it exists.  
#%                                To send output to stdout, use /dev/stdout.
#%                                Default: /dev/null
#% 
#% COMMANDS (All 3 COMMANDS are required)
#%    TO                          One or more recipient email addresses 
#%                                (comma separated).
#%                                Winlink email addresses (CALL@winlink.org)
#%                                do not need to include '@winlink.org', just the 
#%                                call sign.
#%                                
#%    SUBJECT                     Email subject enclosed in "double quotes".
#%
#%    TRANSPORT                   pat transport method.  For example:
#%                                   telnet
#%                                   ax25://portname/call-ssid
#%                                      where portname is as defined in /etc/ax25/axports
#%                                      and the same as the ax25 port in
#%                                      ~/.wl2k/config.json.  This is usually 'wl2k'.
#%
#%                                      where call-ssid is the RMS gateway.  Example:
#%                                      ax25://wl2k/W7ECG-10
#%
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
#%    ${SCRIPT_NAME} me@example.com,W7ABC "My Important Message" ax25://wl2k/W7ECG-10 < myfile.txt 
#%
#================================================================
#- IMPLEMENTATION
#-    version         ${SCRIPT_NAME} 2.2.7
#-    author          Steve Magnuson, AG7GN
#-    license         CC-BY-SA Creative Commons License
#-    script_id       0
#-
#================================================================
#  HISTORY
#     20190920 : Steve Magnuson : Script creation
#     20200204 : Steve Magnuson : Added script template
#     20200227 : Steve Magnuson : Added option to send pat log text to a file or stdout
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
SCRIPT_OPTS=':l:hv-:'

#== set long options associated with short one ==#
typeset -A ARRAY_OPTS
ARRAY_OPTS=(
	[help]=h
	[version]=v
	[log]=l
)

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
	if [[ "x${OPTION}" != "x:" ]] && [[ "x${OPTION}" != "x?" ]] && [[ "${OPTARG}" = -* ]]; then 
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
		l)
			EVENT_LOG="$OPTARG"
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
set -o errexit

# Check Syntax if set
$SYNTAX && set -n
# Run in debug mode, if set
$DEBUG && set -x 

(( $# != 3 )) && Die "3 parameters, TO, SUBJECT and TRANSPORT are required."

PAT="$(command -v pat)" 
[[ $? == 0 ]] || Die "pat winlink client is not installed."
UNIX2DOS="$(command -v unix2dos)"
[[ $UNIX2DOS == "" ]] && Die "dos2unix tools are not installed."

PATDIR="$HOME/.wl2k"
CALL="$(cat $PATDIR/config.json | grep "\"mycall\":" | tr -d ' ",' | cut -d: -f2)"
[[ $CALL == "" ]] && Die "Could not obtain call sign from $PATDIR/config.json.  Is pat configured?"
OUTDIR="$PATDIR/mailbox/$CALL/out"
EVENT_LOG="${EVENT_LOG:-/dev/null}"

TO="$1"
SUBJECT="$2"

[[ $TO =~ "," ]] || TO="$TO\n"

export EDITOR=ed
TFILE="${TMPDIR}/message"
echo -e "$CALL\n$TO\n\n$SUBJECT" | $PAT compose 2>/dev/null 1> $TFILE
MSG="$(grep "MID:" $TFILE | tr -d ' \t' | cut -d':' -f3)" 
[[ $MSG == "" ]] && Die "Could not find the MID (Message ID)"
MSG="$OUTDIR/$MSG.b2f"
sed -i -e 's/<No message body>//' $MSG
$UNIX2DOS -q $MSG
cat - > $TFILE
$UNIX2DOS -q $TFILE
COUNT="$(wc -c $TFILE | cut -d' ' -f1)" 
cat $TFILE >> $MSG
#rm $TFILE
sed -i -e "s/^Body: .*/Body: $COUNT/" $MSG
echo > "$EVENT_LOG"
$PAT --send-only --event-log "$EVENT_LOG" connect $3 >> "$EVENT_LOG"
exit $?

