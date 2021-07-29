#!/bin/bash
#================================================================
# HEADER
#================================================================
#% SYNOPSIS
#+   ${SCRIPT_NAME} [-hv]
#%
#% DESCRIPTION
#%   This script checks the status of 4 GPIO pins and runs a script corresponding
#%   to those settings as described below.  This script is called by initialize-pi.sh,
#%   which is run a bootup via cron @reboot.
#%
#% OPTIONS
#%    -h, --help                  Print this help
#%    -v, --version               Print script information
#%    -s, --state                 Print current switch state
#%
#================================================================
#- IMPLEMENTATION
#-    version         ${SCRIPT_NAME} 1.2.1
#-    author          Steve Magnuson, AG7GN
#-    license         CC-BY-SA Creative Commons License
#-    script_id       0
#-
#================================================================
#  HISTORY
#     20190620 : Steve Magnuson : Script creation
#     20200204 : Steve Magnuson : Added script template
#     20200525 : Steve Magnuson : Now using raspi-gpio instead of
#                                 gpio to be compatible with all
#                                 versions of Pis
#     20210719 : Steve Magnuson : Add -s option to print switch
#                                 state
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

function GetSwitchState () {
	# Array P: Array index is the ID of each individual switch in the piano switch.
	#          Array element value is the GPIO BCM number.
	P[1]=25
	P[2]=13
	P[3]=6
	P[4]=5
	local LEVERS=""
	for I in 1 2 3 4
	do
		J=$($GPIO get ${P[$I]} | cut -d' ' -f3 | cut -d'=' -f2) # State of a switch in the piano (0 or 1)
		(( $J == 0 )) && LEVERS="$LEVERS$I"
	done
	echo "$LEVERS"
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
VERSION="$(ScriptInfo version | grep version | tr -s ' ' | cut -d' ' -f 4)" 

GPIO="$(command -v raspi-gpio)"


#============================
#  PARSE OPTIONS WITH GETOPTS
#============================
  
#== set short options ==#
SCRIPT_OPTS=':hsv-:'

#== set long options associated with short one ==#
typeset -A ARRAY_OPTS
ARRAY_OPTS=(
	[help]=h
	[state]=s
	[version]=v
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
		s) PIANO="$(GetSwitchState)"
			[[ $PIANO == "" ]] && MESSAGE="No levers are down." || MESSAGE="Levers $PIANO are down."
		   if xset q &>/dev/null
		   then
		   	yad --center --title="Test calling pianoX.sh script - version $VERSION" \
		   	--info --borders=30 --no-wrap \
		   	--text="<b>$MESSAGE $HOME/piano$PIANO.sh will run.</b>" \
		   	--buttons-layout=center --button=Close:0
		   else
		   	echo "$MESSAGE"
		   fi
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
trap TrapCleanup EXIT INT TERM

# Exit on error. Append '||true' when you run the script if you expect an error.
set -o errexit

# Check Syntax if set
$SYNTAX && set -n
# Run in debug mode, if set
$DEBUG && set -x 

# String $PIANO will identify which levers are in the DOWN position 
PIANO="$(GetSwitchState)"

# Check if the script corresponding to the piano switch setting exists and is not empty.
#
# Scripts must be in the $HOME directory, be marked as executable, and be named
# pianoX.sh where X is one of these:
# 1,12,13,14,123,124,134,1234,2,23,234,24,3,34,4
#
# Example:  When the piano switch levers 2 and 4 are down, the script named 
#           $HOME/piano24.sh will run whenever the Raspberry Pi starts.
#echo "running piano$PIANO.sh"
[ -s $HOME/piano$PIANO.sh ] && $HOME/piano$PIANO.sh
SafeExit
