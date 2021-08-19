#!/bin/bash
#================================================================
# HEADER
#================================================================
#% SYNOPSIS
#+   ${SCRIPT_NAME} [-hv]
#%
#% DESCRIPTION
#%   This script allows you to edit the text on the default Nexus DR-X Desktop.
#%   You can, for example add your call sign and select whether or not to include
#%   the Pi's hostname and Pi model.
#%
#% OPTIONS
#%    -h, --help                  Print this help
#%    -v, --version               Print script information
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
#     20191115 : Steve Magnuson : Script creation
#     20200204 : Steve Magnuson : Added script template
#     20210819 : Steve Magnuson : Add ability to set parameters
#                                 without GUI
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

  #== general variables ==#
SCRIPT_NAME="$(basename ${0})" # scriptname without path
SCRIPT_DIR="$( cd $(dirname "$0") && pwd )" # script directory
SCRIPT_FULLPATH="${SCRIPT_DIR}/${SCRIPT_NAME}"
SCRIPT_ID="$(ScriptInfo | grep script_id | tr -s ' ' | cut -d' ' -f3)"
SCRIPT_HEADSIZE=$(grep -sn "^# END_OF_HEADER" ${0} | head -1 | cut -f1 -d:)
VERSION="$(ScriptInfo version | grep version | tr -s ' ' | cut -d' ' -f 4)" 

TITLE="Desktop Text Editor $VERSION"
CONFIG_FILE="$HOME/desktop-text.conf"
PICTURE_DIR="$HOME/Pictures"
DEFAULT_BACKGROUND_IMAGE="$PICTURE_DIR/NexusDeskTop.jpg"
MESSAGE="Enter the text you want displayed below.\nDon't use any single or double quotation marks."
GUI=TRUE

declare -A MODELS
MODELS[a02082]="1GB RAM"
MODELS[a020d3]="1GB RAM"
MODELS[a22082]="1GB RAM"
MODELS[a32082]="1GB RAM"
MODELS[a52082]="1GB RAM"
MODELS[a22083]="1GB RAM"
MODELS[a32082]="1GB RAM"
MODELS[a220a0]="1GB RAM"
MODELS[a02100]="1GB RAM"
MODELS[a03111]="1GB RAM"
MODELS[b03111]="2GB RAM"
MODELS[b03112]="2GB RAM"
MODELS[c03111]="4GB RAM"
MODELS[c03112]="4GB RAM"
MODELS[d03114]="8GB RAM"
#MODELS[a02082]="1GB RAM Manufacturer: Sony UK"
#MODELS[a020d3]="1GB RAM Manufacturer: Sony UK"
#MODELS[a22082]="1GB RAM Manufacturer: Embest"
#MODELS[a32082]="1GB RAM Manufacturer: Sony Japan"
#MODELS[a52082]="1GB RAM Manufacturer: Stadium"
#MODELS[a22083]="1GB RAM Manufacturer: Embest"
#MODELS[a32082]="1GB RAM Manufacturer: Sony Japan"
#MODELS[a220a0]="1GB RAM Manufacturer: Embest"
#MODELS[a02100]="1GB RAM Manufacturer: Sony UK"
#MODELS[a03111]="1GB RAM Manufacturer: Sony UK"
#MODELS[b03111]="2GB RAM Manufacturer: Sony UK"
#MODELS[b03112]="2GB RAM Manufacturer: Sony UK"
#MODELS[c03111]="4GB RAM Manufacturer: Sony UK"
#MODELS[c03112]="4GB RAM Manufacturer: Sony UK"
#MODELS[d03114]="8GB RAM Manufacturer: Sony UK"

#============================
#  PARSE OPTIONS WITH GETOPTS
#============================
  
#== set short options ==#
SCRIPT_OPTS=':c:hv-:'

#== set long options associated with short one ==#
typeset -A ARRAY_OPTS
ARRAY_OPTS=(
	[help]=h
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
	   c)
	   	MYCALL="$OPTARG"
			GUI=FALSE
	   	;;
		h) 
			ScriptInfo full
			exit 0
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

[ -s $DEFAULT_BACKGROUND_IMAGE ] || Die "Default Nexus image not in $DEFAULT_BACKGROUND_IMAGE" 1

if ! command -v convert >/dev/null
then
   yad --center --title="Desktop Text Editor - version $VERSION" --info --borders=30 \
    --no-wrap --selectable-labels --text="<b>The 'convert' application is not installed.  Run this command in the Terminal:\n\nsudo apt update &amp;&amp; sudo apt install -y imagemagick\n\nthen run this script again.</b>" --buttons-layout=center \
--button=Close:0
	SafeExit
	#sudo apt update || Die "Could not run 'sudo apt update'"
	#sudo apt install -y imagemagick || Die "Could not run 'sudo apt install -y imagemagick'"
fi

MODEL="$(egrep "^Model" /proc/cpuinfo | sed -e 's/ //;s/\t//g' | cut -d: -f2)"
REVISION="$(egrep "^Revision" /proc/cpuinfo | sed -e 's/ //;s/\t//g' | cut -d: -f2)"
SERIAL="$(egrep "^Serial" /proc/cpuinfo | sed -e 's/ //;s/\t//g' | cut -d: -f2)"
[[ -z $MODEL ]] && INFO ="" || INFO="$MODEL with ${MODELS[$REVISION]}"

[[ -z $MYCALL ]] && MYCALL="N0CALL"

if [ -s "$CONFIG_FILE" ]
then # There is a config file
	echo "$CONFIG_FILE found."
else # Set some default values in a new config file
	echo "Config file $CONFIG_FILE not found.  Creating a new one with default values."
	echo "TEXT=\"$N0CALL\"" > "$CONFIG_FILE"
	echo "SHOW_HOSTNAME=\"TRUE\"" >> "$CONFIG_FILE"
fi
source "$CONFIG_FILE"

while true
do
	if [[ $GUI == TRUE ]]
	then
		ANS=""
		ANS="$(yad --title="$TITLE" \
   		--text="<b><big><big>Desktop Text Editor</big></big>\n\n \
$MESSAGE</b>\n" \
   		--item-separator="!" \
			--posx=10 --posy=50 \
			--align=right \
   		--buttons-layout=center \
  			--text-align=center \
   		--align=right \
   		--borders=20 \
   		--form \
   		--field="Background Text" "$TEXT" \
   		--field="Include Hostname":CHK $SHOW_HOSTNAME \
   		--focus-field 1 \
		)"

		[[ $? == 1 || $? == 252 ]] && Die  # User has cancelled.

		[[ $ANS == "" ]] && Die "Unexpected input from dialog"

		IFS='|' read -r -a TF <<< "$ANS"

		TEXT="${TF[0]}"
		SHOW_HOSTNAME="${TF[1]}"
		echo "TEXT=\"$TEXT\"" > "$CONFIG_FILE"
		echo "SHOW_HOSTNAME=\"$SHOW_HOSTNAME\"" >> "$CONFIG_FILE"
	else
  		TEXT="$MYCALL"
  		SHOW_HOSTNAME="FALSE"
   	echo "TEXT=\"$MYCALL\"" > "$CONFIG_FILE"
  		echo "SHOW_HOSTNAME=\"FALSE\"" >> "$CONFIG_FILE"
	fi

	[[ $TEXT == "" ]] && { $(command -v pcmanfm) --set-wallpaper="$DEFAULT_BACKGROUND_IMAGE"; continue; }

	TARGET="$PICTURE_DIR/TEXT_$(echo $TEXT | tr -cd [a-zA-Z0-9]).jpg"
	echo "Deleting $PICTURE_DIR/TEXT_*.jpg"
	find "$PICTURE_DIR" -maxdepth 1 -name TEXT_*.jpg -type f -delete

	if [[ $SHOW_HOSTNAME == "TRUE" ]]
	then
		$(command -v convert) $DEFAULT_BACKGROUND_IMAGE \
     		-gravity south -pointsize 20 -fill yellow -annotate 0 $(hostname) \
     		-gravity south -pointsize 18 -fill white -annotate +0+25 "$INFO" \
     		-gravity south -pointsize 75 -fill yellow -annotate +0+40 "$TEXT" $TARGET
	else
		$(command -v convert) $DEFAULT_BACKGROUND_IMAGE \
    		-gravity south -pointsize 18 -fill white -annotate +0+25 "$INFO" \
			-gravity south -pointsize 75 -fill yellow -annotate +0+40 "$TEXT" $TARGET
	fi
	$(command -v pcmanfm) --set-wallpaper="$TARGET"
	[[ $GUI == FALSE ]] && break
done
SafeExit