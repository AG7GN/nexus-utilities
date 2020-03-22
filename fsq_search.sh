#!/bin/bash
#================================================================
# HEADER
#================================================================
#% SYNOPSIS
#+    ${SCRIPT_NAME} [-hv] [-c command] [-w seconds] [-t date_format] [search_string]
#%
#% DESCRIPTION
#%    Searches for text in messages logged in ${FSQ_AUDIT_FILE}.  
#%    The script will print matching lines, with optional timestamp, to stdout
#%    and will optionally launch a command on a match.  The command is run in the 
#%    background.  search_string can be a regular expression.  If no search_string is 
#%    supplied, all messages will match.
#%    
#%    Only one instance of this script will run at a time and only if at least one 
#%    instance of Fldigi is running.  The script will kill itself when no more 
#%    instances of Fldigi are running.  This script can be used as an autostart in
#%    Fldigi.
#%
#%    Messages logged in ${FSQ_AUDIT_FILE} are in a specific format.  In the following 
#%    non-relayed message example w7ecg is the sending station, followed by a colon 
#%    and a 2 character checksum, followed the called station (ag7gn) followed by the
#%    message.
#%
#%    w7ecg:81ag7gn this is my message.
#%
#% OPTIONS
#%    -c COMMAND, --command=COMMAND      
#%                                Launch command if a match is found.  Wrap in 
#%                                double quotes if arguments to command are supplied.  
#%                                See EXAMPLES below.
#%    -t DATE_FORMAT|default, --timestamp=DATE_FORMAT|default
#%                                Precede each message printed to stdout with a 
#%                                timestamp in DATE_FORMAT.  Run 'man date' for 
#%                                available formats.  -t default will use the default
#%                                date format.  Example: -t "+%Y%m%dT%H%M%S"
#%    -w SECONDS, --wait=SECONDS
#%                                Minimum time in seconds between -s script executions. 
#%                                Higher values reduce number of script executions.
#%                                Range: ${MIN_WAIT}-${MAX_WAIT}  Default: ${WAIT}
#%    -h, --help                  Print this help
#%    -v, --version               Print script information
#%
#% EXAMPLES
#%
#%    Match all messages and print them to stdout with no timestamp:  
#%
#%       ${SCRIPT_NAME}
#%
#%    Match messages where callsign ag7gn appears anywhere in the message.  Run script
#%    alert.sh on a match, but don't launch alert.sh again if another match occurs 
#%    within 60 seconds:
#%
#%       ${SCRIPT_NAME} -w 60 -s alert.sh ag7gn
#%
#%    Match messages where callsign ag7gn or wc7hq or n7bel appears anywhere in the
#%    message. Matching lines will be printed to stdout prepended with the default 
#%    timestamp:
#%    
#%       ${SCRIPT_NAME} -t default "ag7gn|wc7hq|n7bel"
#%
#%    Match messages where the called station is any of ag7gn or wc7hq or n7bel.  
#%    Play a WAV file on match.  Don't print matching messages to stdout:
#%
#%       ${SCRIPT_NAME} -c "aplay -q alert.wav" ":..(ag7gn|wc7hq|n7bel)" >/dev/null
#%
#%    Match messages where the called station is ag7gn, followed by the string
#%    'steve' anywhere in the remainder of the message.  
#%    Play an OGG file with 'paplay' to pulseaudio device 'system-audio-playback'
#%    on match.  Don't print matching messages to stdout:
#%
#%       ${SCRIPT_NAME} -c "paplay --device=system-audio-playback fsq_ag7gn.ogg" ":..ag7gn.*steve" >/dev/null
#%
#%    Match messages where the calling station is either wc7hq or n7bel.  Prepend
#%    the messages printed to stdout with a specific timestamp format:
#%
#%       ${SCRIPT_NAME} -t "+%Y%m%dT%H%M%S" "^(wc7hq|n7bel)"
#%
#================================================================
#- IMPLEMENTATION
#-    version         ${SCRIPT_NAME} 1.2.9
#-    author          Steve Magnuson, AG7GN
#-    license         CC-BY-SA Creative Commons License
#-    script_id       0
#-
#================================================================
#  HISTORY
#     20200203 : Steve Magnuson : Script creation
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
	    -e "s/\${MIN_WAIT}/${MIN_WAIT}/g" \
	    -e "s/\${MAX_WAIT}/${MAX_WAIT}/g" \
	    -e "s/\${WAIT}/${WAIT}/g" \
	    -e "s/\${FSQ_AUDIT_FILE}/${FSQ_AUDIT_FILE}/g"
}

function Usage() { 
	printf "Usage: "
	ScriptInfo usage
	exit
}

function Die () {
	echo "${*}, Exiting."
	SafeExit
}

#----------------------------

function ProcessMessage () {
	if [[ $LINE =~ $SEARCH_STRING ]]
	then
	   LINE="$(echo $LINE | sed -e "s/$EOM_RE//")"
	   [[ $DATE_CMD != "" ]] && LINE="$($DATE_CMD) $LINE"
	   echo "$LINE" 
		if (( $(( $(date +%s) - LAST )) >= $WAIT ))
		then # It's been more than $WAIT seconds since last match.  OK to run user script.
			$SCRIPT &
			LAST=$(date +%s) # Reset timer
		fi
	fi
}

#============================
#  FILES AND VARIABLES
#============================

  #== general variables ==#
SCRIPT_NAME="$(basename ${0})" # scriptname without path
SCRIPT_DIR="$( cd $(dirname "$0") && pwd )" # script directory
SCRIPT_FULLPATH="${SCRIPT_DIR}/${SCRIPT_NAME}"
SCRIPT_ID="$(ScriptInfo | grep script_id | tr -s ' ' | cut -d' ' -f3)"
SCRIPT_HEADSIZE=$(grep -sn "^# END_OF_HEADER" ${0} | head -1 | cut -f1 -d:)

# Set Temp Directory
# -----------------------------------
# Create temp directory with three random numbers and the process ID
# in the name.  This directory is removed automatically at exit.
# -----------------------------------
#TMPDIR="/tmp/${SCRIPT_NAME}.$RANDOM.$RANDOM.$RANDOM.$$"
#(umask 077 && mkdir "${TMPDIR}") || {
#  Die "Could not create temporary directory! Exiting."
#}

FSQ_AUDIT_FILE="fsq_audit_log.txt"
TAIL_FILES="$HOME/.fldigi-left/temp/$FSQ_AUDIT_FILE $HOME/.fldigi-right/temp/$FSQ_AUDIT_FILE $HOME/.fldigi/temp/$FSQ_AUDIT_FILE"
WAV_FILE="/usr/lib/libreoffice/share/gallery/sounds/untie.wav"
declare -i WAIT=0
declare -i MIN_WAIT=0
declare -i MAX_WAIT=300

#============================
#  PARSE OPTIONS WITH GETOPTS
#============================
  
#== set short options ==#
SCRIPT_OPTS=':hc:w:t:v-:'

#== set long options associated with short one ==#
typeset -A ARRAY_OPTS
ARRAY_OPTS=(
	[help]=h
	[version]=v
	[command]=c
	[timestamp]=t
	[wait]=w
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
		[[ "x$LONG_OPTARG" == "x" ]] && LONG_OPTIND=$OPTIND || LONG_OPTION=$(echo $OPTARG | cut -d'=' -f1)
		[[ $LONG_OPTIND -ne -1 ]] && eval LONG_OPTARG="\$$LONG_OPTIND"
		OPTION=${ARRAY_OPTS[$LONG_OPTION]}
		[[ "x$OPTION" == "x" ]] &&  OPTION="?" OPTARG="-$LONG_OPTION"
		
		if [[ $( echo "${SCRIPT_OPTS}" | grep -c "${OPTION}:" ) -eq 1 ]]
		then
			if [[ "x${LONG_OPTARG}" == "x" ]] || [[ "${LONG_OPTARG}" == -* ]]
			then 
				OPTION=":" OPTARG="-$LONG_OPTION"
			else
				OPTARG="$LONG_OPTARG";
				if [[ $LONG_OPTIND -ne -1 ]]
				then
					[[ $OPTIND -le $Optnum ]] && OPTIND=$(( $OPTIND+1 ))
					shift $OPTIND
					OPTIND=1
				fi
			fi
		fi
	fi
	#echo "OPTION=\"$OPTION\" OPTARG=\"$OPTARG\"  LONG_OPTION=\"$LONG_OPTION\"  LONG_OPTARG=\"$LONG_OPTARG\""

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
		c) 
			SCRIPT="$OPTARG" 
			#[[ -s "$SCRIPT" ]] || Die "${SCRIPT_NAME}: \""$SCRIPT"\" not found."
			;;
		t) 
			DATE_FORMAT="$OPTARG" 
			DATE_CMD=""
			if [[ $DATE_FORMAT != "default" ]]
			then
				date "$DATE_FORMAT" >/dev/null 2>&1 || Die "${SCRIPT_NAME}: Invalid timestamp date format.  See 'man date'"
				DATE_CMD="date "$DATE_FORMAT""
			else
				DATE_CMD="date"
			fi
			;;
		w) 
			WAIT=$OPTARG
			(( WAIT>=MIN_WAIT )) && (( WAIT<=MAX_WAIT )) || Die "${SCRIPT_NAME}: Wait time must be between $MIN_WAIT and $MAX_WAIT"
			;;
		v) 
			ScriptInfo version
			exit 0
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

# Don't run this script again if it's already running
pgrep -f "tail --pid=.*fsq_audit_log.txt" >/dev/null 2>&1 && SafeExit

VERSION="$(ScriptInfo version | grep version | tr -s ' ' | cut -d' ' -f 4)" 
SEARCH_STRING="${1:-.*}"  # Match anything if no search_string supplied.
#SCRIPT="${SCRIPT:-aplay -q $WAV_FILE}"
declare -i LAST=$(( $(date +%s) - WAIT ))
PID="$(pgrep -n fldigi)"
# Start Of Message Regular Expression
SOM_RE="^[a-z]{1,2}[0-9][a-z].*:..([a-z]{1,2}[0-9][a-z]|allcall)" 
# End Of Message Regular Expression. FSQ end in '<BS>'. read cmd chops off trailing '>'
EOM_RE="<BS$" 
COMPLETE_MESSAGE_RE="${SOM_RE}.*${EOM_RE}"

while [[ $PID != "" ]]
do # At least one fldigi instance is running.  Check messages until that process stops.
	TAIL="$(command -v tail) --pid=$PID -q -F -n 0 $TAIL_FILES"
	PARTIAL_MSG=""
	while IFS= read -d '>' -r LINE  # Use '>' as line delimiter rather than '\n'
	do
      if [[ $LINE =~ $COMPLETE_MESSAGE_RE ]]
      then # Complete message found.  Process it.
         ProcessMessage
         PARTIAL_MSG=""
         continue
		fi
      if [[ $LINE =~ $SOM_RE ]]
      then 
      	# Start of message found.  Start constructing a PARTIAL_MSG and restore
      	# the '>' that read chopped off.
      	PARTIAL_MSG="${PARTIAL_MSG}${LINE}>"
      	continue
      fi
      if [[ $PARTIAL_MSG != "" ]]
      then # PARTIAL_MSG under construction
      	if [[ $LINE =~ $EOM_RE ]]
      	then 
      		# LINE contains EOM_RE, so append it to PARTIAL_MSG and see if it's a
      		# complete message
      		PARTIAL_MSG="${PARTIAL_MSG}${LINE}"
	      	if [[ $PARTIAL_MSG =~ $COMPLETE_MESSAGE_RE ]]
   	   	then # PARTIAL_MSG now appears to be a valid message.  Process it.
   	   		LINE="$PARTIAL_MSG"
         		ProcessMessage
				fi
				PARTIAL_MSG=""
			else
   			# EOM_RE not found, but there is an embedded '>' in LINE.
   			# Add LINE to PARTIAL_MSG and restore '>' that read chopped off.
      		PARTIAL_MSG="${PARTIAL_MSG}${LINE}>"
			fi
		fi      	
   done < <($TAIL 2>/dev/null | stdbuf -o0 tr -cd '\11\12\15\40-\176' | stdbuf -o0 tr -d '\n')
   #done < <($TAIL 2>/dev/null | cat -v | stdbuf -o0 tr -d '\n')
	# Get most recent fldigi PID
	PID="$(pgrep -n fldigi)" 
done

SafeExit
