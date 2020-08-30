#!/bin/bash
#================================================================
# HEADER
#================================================================
#% SYNOPSIS
#+   ${SCRIPT_NAME} [-hv]
#%
#% DESCRIPTION
#%   This script provides a GUI to configure and start/stop
#%   piardop2, pat and gARIM.  It is designed to work on the 
#%   Nexus image.
#%
#% OPTIONS
#%    -h, --help                  Print this help
#%    -v, --version               Print script information
#%
#================================================================
#- IMPLEMENTATION
#-    version         ${SCRIPT_NAME} 0.0.1
#-    author          Steve Magnuson, AG7GN
#-    license         CC-BY-SA Creative Commons License
#-    script_id       0
#-
#================================================================
#  HISTORY
#     20200428 : Steve Magnuson : Script creation.
#     20200507 : Steve Magnuson : Bug fixes
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
   kill $timeStamp_PID >/dev/null 2>&1
   kill $direwolf_PID >/dev/null 2>&1
   kill $pat_PID >/dev/null 2>&1
	kill $RIG_PID >/dev/null 2>&1
   for P in ${YAD_PIDs[@]}
	do
		kill $P >/dev/null 2>&1
	done
   sudo pkill kissattach >/dev/null 2>&1
   rm -f /tmp/kisstnc
   rm -f $PIPE
}

function SafeExit() {
   trap - INT TERM EXIT SIGINT
	TrapCleanup
   exit 0
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

function loadpatDefaults () {
   for I in $(seq 7 10)
   do # I is the field number.  D[$I] is the default value
           echo "${I}:${D[$I]}"
   done
}

function setTNCpatDefaults () {
   declare -gA D
   D[1]="N0CALL"  # Call sign
   D[2]="null" # Audio capture interface (ADEVICE)
   D[3]="null" # Audio playback interface (ADEVICE)
   D[4]="gpio=23" # GPIO PTT (BCM pin)
   D[5]="8515" # ARDOP Listen Port
   D[6]="FALSE" # Enable pat HTTP server
}

function loadSettings () {
	 
   PTTs="gpio=12!gpio=23"

	if [ -s "$CONFIG_FILE" ]
	then # There is a config file
   	echo "$CONFIG_FILE found." >&7
  		source "$CONFIG_FILE"
	else # Set some default values in a new config file
   	echo -e "Config file $CONFIG_FILE not found.\nCreating a new one with default values." >&7
		setTNCpatDefaults
   	echo "declare -gA F" > "$CONFIG_FILE"
   	echo "F[_CALL_]='${D[1]}'" >> "$CONFIG_FILE"
   	echo "F[_ADEVICE_CAPTURE_]='${D[2]}'" >> "$CONFIG_FILE"
   	echo "F[_ADEVICE_PLAY_]='${D[3]}'" >> "$CONFIG_FILE"
   	echo "F[_PTT_]='${D[4]}'" >> "$CONFIG_FILE"
   	echo "F[_ARDOPPORT_]='${D[5]}'" >> "$CONFIG_FILE"
   	echo "F[_PAT_HTTP_]='${D[6]}'" >> "$CONFIG_FILE"
   	source "$CONFIG_FILE"
	fi

	MYCALL="${F[_CALL_]}"

	if pgrep pulseaudio >/dev/null 2>&1
   then # There may be pulseaudio ALSA devices.  Look for them.
      CAPTURE_IGNORE="$(pacmd list-sinks 2>/dev/null | grep name: | tr -d '\t' | cut -d' ' -f2 | sed 's/^<//;s/>$//' | tr '\n' '\|' | sed 's/|/\\|/g')"
      ADEVICE_CAPTUREs="$(arecord -L | grep -v "$CAPTURE_IGNORE^ .*\|^dsnoop\|^sys\|^default\|^dmix\|^hw\|^usbstream\|^jack\|^pulse" | tr '\n' '!' | sed 's/!$//')"
      PLAYBACK_IGNORE="$(pacmd list-sources 2>/dev/null | grep name: | tr -d '\t' | cut -d' ' -f2 | sed 's/^<//;s/>$//' | tr '\n' '\|' | sed 's/|/\\|/g')"
      ADEVICE_PLAYBACKs="$(aplay -L | grep -v "$PLAYBACK_IGNORE^ .*\|^dsnoop\|^sys\|^default\|^dmix\|^hw\|^usbstream\|^jack\|^pulse" | tr '\n' '!' | sed 's/!$//')"
   else  # pulseaudio isn't running.  Check only for null and plughw devices
      ADEVICE_CAPTUREs="$(arecord -L | grep "^null\|^plughw" | tr '\n' '!' | sed 's/!$//')"
      ADEVICE_PLAYBACKs="$(aplay -L | grep "^null\|^plughw" | tr '\n' '!' | sed 's/!$//')"
   fi
   [[ $ADEVICE_CAPTUREs =~ ${F[_ADEVICE_CAPTURE_]} ]] && ADEVICE_CAPTUREs="$(echo "$ADEVICE_CAPTUREs" | sed "s/${F[_ADEVICE_CAPTURE_]}/\^${F[_ADEVICE_CAPTURE_]}/")"
   [[ $ADEVICE_CAPTUREs == "" ]] && ADEVICE_CAPTUREs="null"
   [[ $ADEVICE_PLAYBACKs =~ ${F[_ADEVICE_PLAY_]} ]] && ADEVICE_PLAYBACKs="$(echo "$ADEVICE_PLAYBACKs" | sed "s/${F[_ADEVICE_PLAY_]}/\^${F[_ADEVICE_PLAY_]}/")"
   [[ $ADEVICE_PLAYBACKs == "" ]] && ADEVICE_PLAYBACKs="null"

	if [[ $PTTs =~ ${F[_PTT_]} ]]
   then
      PTTs="$(echo "$PTTs" | sed "s/${F[_PTT_]}/\^${F[_PTT_]}/")"
   else
      PTTs+="!^${F[_PTT_]}"
   fi
	
	ARDOPPORT="${F[_ARDOPPORT_]}"
	cat $PAT_CONFIG | jq \
		--arg A "0.0.0.0:$ARDOPPORT" '.ardop.addr = $A' | sponge $PAT_CONFIG
	PAT_START_HTTP="${F[_PAT_HTTP_]}"
	PAT_CALL="$(jq -r ".mycall" $PAT_CONFIG)"
	PAT_LOCATOR="$(jq -r ".locator" $PAT_CONFIG)"
	PAT_ARQ_BW_FORCED="$(jq -r ".ardop.arq_bandwidth.Forced" $PAT_CONFIG)"
	PAT_ARQ_BW_MAX="$(jq -r ".ardop.arq_bandwidth.Max" $PAT_CONFIG)"
}

function timeStamp () {
	while sleep 60
	do
		echo -e "\nTIMESTAMP: $(date)" 
	done >$PIPEDATA
}

function killpiardop2 () {
	# $1 is the piardop2 PID
   if pgrep ^direwolf | grep -q $1 2>/dev/null
	then
		kill $1 >/dev/null 2>&1
		echo -e "\n\npiardop2 stopped.  Click \"Save Settings...\" button below to restart." >$PIPEDATA
	else
		echo -e "\n\npiardop2 was already stopped.  Click \"Save Settings...\" button below to restart." >$PIPEDATA
	fi
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

TITLE="ARDOP TNC Monitor and Configuration $VERSION"
CONFIG_FILE="$HOME/ardop_tnc.conf"
MESSAGE="ARDOP Configuration"

ID="${RANDOM}"

PAT_CONFIG="$HOME/.wl2k/config.json"

RETURN_CODE=0
ARDOP="$(command -v piardop2)"
PAT="$(command -v pat) -l ardop http"

PIPE=$TMPDIR/pipe
mkfifo $PIPE
exec 7<> $PIPE

#============================
#  PARSE OPTIONS WITH GETOPTS
#============================
  
#== set short options ==#
SCRIPT_OPTS=':hv-:'

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

# Ensure only one instance of this script is running.
pidof -o %PPID -x $(basename "$0") >/dev/null && exit 1

# Check for required apps.
for A in yad pat jq sponge rigctld
do 
	command -v $A >/dev/null 2>&1 || Die "$A is required but not installed."
done

# If this is the first time running this script, don't attempt to start Direwolf
# or pat until user configures both.
if [[ -s $PAT_CONFIG && -s $CONFIG_FILE ]]
then # Direwolf and pat configuration files exist
	if [[ $(jq -r ".mycall" $PAT_CONFIG) == "" ||  ${F[_ADEVICE_CAPTURE_]} == "null" ]]
	then # Config files present, but not configured
		FIRST_RUN=true
	else # Config files present and configured
		FIRST_RUN=false
	fi
else # No configuration files exist
	FIRST_RUN=true
fi

# Check for pat's config.json.  Create it if necessary
if ! [[ -s $PAT_CONFIG ]]
then
	cd $HOME
	export EDITOR=ed
	echo -n "" | pat configure >/dev/null 2>&1
fi

export -f setTNCpatDefaults loadpatDefaults
export load_pat_defaults_cmd='@bash -c "setTNCpatDefaults; loadpatDefaults"'
export PIPEDATA=$PIPE

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


# Set up a dummy rig for rigctl in pat
RIG="$(jq -r .hamlib_rigs $PAT_CONFIG)"
if [[ $RIG == "{}" ]]
then # No rigs configured.  Make a dummy rig
   cat $PAT_CONFIG | jq \
         '.hamlib_rigs += {"dummy": {"address": "localhost:4532", "network": "tcp"}}' | sponge $PAT_CONFIG
   # Add the dummy rig to the ax25 section
   cat $PAT_CONFIG | jq \
      --arg R "dummy" \
      '.ax25.rig = $R' | sponge $PAT_CONFIG
fi

timeStamp &
timeStamp_PID=$!

piardop2_PID=""
pat_PID=""
YAD_PIDs=()

while true
do
	# Kill any running processes and load latest settings
	killpiardop2 $piardop2_PID
	[[ $pat_PID == "" ]] || kill $pat_PID >/dev/null 2>&1
   for P in ${YAD_PIDs[@]}
	do
		ps x | egrep -q "^$P" && kill $P
	done
	loadSettings
	YAD_PIDs=()
	
	# Start the tail window tab
	TEXT="Port: <span color='blue'><b>$ARDOPPORT</b></span>"
	[[ $PAT_START_HTTP == TRUE ]] && TEXT+="pat Web Server: <span color='blue'><b>http://$HOSTNAME.local:$PAT_ARDOP_PORT</b></span>"
	yad --plug="$ID" --tabnum=1 \
		--back=black --fore=yellow --selectable-labels \
		--text-info --text-align=center --text="$TEXT" \
		--editable --tail --center <&7 &
	YAD_PIDs+=( $! )

	if [[ $FIRST_RUN == true ]]
	then
		echo -e "Configure ARDOP (piardop2) and pat in the \"Configure TNC\" and \"Configure pat\" tabs,\nthen click \"Save Settings...\" button below." >&7
	else # Not a first run.  pat and piardop configured so start 'em
		# Start piardop2
		$ARDOP $ARDOPPORT ${F[_ADEVICE_CAPTURE_]} ${F[_ADEVICE_PLAYBACK_]} -p ${F[_PTT_]} >&7 2>&7 &
		piardop2_PID=$!
		echo -e "\n\nARDOP TNC (piardop2) has started.  PID=$piardop2_PID" >&7

		# Start pat
		if [[ $PAT_START_HTTP == TRUE ]]
		then
			$PAT >&7 2>&7 &
			pat_PID=$!
		else
			pat_PID=""
		fi
	fi 
	
	# Set up tab for configuring Direwolf.
	yad --plug="$ID" --tabnum=2 \
  		--text="<b><big><big>ARDOP TNC Configuration</big></big></b>\n\n \
<b><u><big>Typical ARDROP Sound Card and PTT Settings</big></u></b>\n \
<span color='blue'><b>LEFT Radio:</b></span> Use ADEVICEs \
<b>fepi-capture-left</b> and <b>fepi-playback-left</b> and PTT <b>gpio=12</b>.\n \
<span color='blue'><b>RIGHT Radio:</b></span> Use ADEVICEs \
<b>fepi-capture-right</b> and <b>fepi-playback-right</b> and PTT <b>gpio=23</b>.\n\n \
Click the <b>Save Settings...</b> button below after you make your changes.\n\n" \
  		--item-separator="!" \
		--separator="|" \
		--align=right \
  		--text-align=center \
  		--align=right \
  		--borders=20 \
  		--form \
		--columns=1 \
     	--field="<b>Call Sign</b>" "$MYCALL" \
  	  	--field="<b>ARDOP Capture ADEVICE</b>":CB "$ADEVICE_CAPTUREs" \
     	--field="<b>ARDOP Playback ADEVICE</b>":CB "$ADEVICE_PLAYBACKs" \
   	--field="<b>ARDOP PTT</b>":CBE "$PTTs" \
   	--field="<b>ARDOP Port</b>":NUM "$AGWPORT!8515..8525!1!" \
  		--focus-field 1 > $TMPDIR/CONFIGURE_ARDOP_TNC.txt &
	YAD_PIDs+=( $! )

	# Set up tab for pat configuration
	yad --plug="$ID" --tabnum=3 \
		--text="<b><big><big>pat Configuration</big></big></b>\n\n \
Click the <b>Save Settings...</b> button below after you make your changes.\n\n" \
		--item-separator="!" \
		--separator="|" \
		--align=right \
  		--text-align=center \
  		--align=right \
  		--borders=20 \
  		--form \
		--columns=1 \
     	--field="Call Sign" "$PAT_CALL" \
		--field="Locator Code" "$PAT_LOCATOR" \
   	--field="Web Service Port":NUM "$PAT_HTTP_PORT!8040..8049!1!" \
   	--field="Force ARDOP ARQ Bandwidth":CHK "$PAT_ARQ_BW_FORCED" \
   	--field="Max ARDOP Bandwidth":NUM "$PAT_ARQ_BW_MAX" \
   	--field="Start pat web service when Direwolf TNC starts":CHK "$PAT_START_HTTP" \
		--field="<b>Edit pat Connection Aliases</b>":FBTN "bash -c edit_pat_aliases.sh &" \
  		--focus-field 1 > $TMPDIR/CONFIGURE_ARDOP_PAT.txt &
	YAD_PIDs+=( $! )
	[[ $PAT_START_HTTP == TRUE ]] && AND_PAT=" + pat" || AND_PAT=""

	# Set up a notebook with the 3 tabs.		
	yad --title="ARDOP TNC and pat $VERSION" --text="<b><big>ARDOP TNC$AND_PAT Configuration and Operation</big></b>" \
  		--text-align="center" --notebook --key="$ID" \
		--posx=10 --posy=50 \
  		--buttons-layout=center \
  		--tab="Monitor" \
  		--tab="Configure TNC" \
  		--tab="Configure pat" \
		--width="800" --height="600" \
  		--button="<b>Stop ARDOP$AND_PAT &#x26; Exit</b>":1 \
  		--button="<b>Save Settings &#x26; Restart ARDOP$AND_PAT</b>":0
	RETURN_CODE=$?

	case $RETURN_CODE in
		0) # Read and handle the Configure TNC tab yad output
			[[ -s $TMPDIR/CONFIGURE_ARDOP_TNC.txt ]] || Die "Unexpected input from dialog"
			IFS='|' read -r -a TF < "$TMPDIR/CONFIGURE_ARDOP_TNC.txt"
			F[_CALL_]="${TF[0]^^}"
			F[_ADEVICE_CAPTURE_]="${TF[1]}"
			F[_ADEVICE_PLAY_]="${TF[2]}"
			F[_PTT_]="${TF[3]}"
			F[_ARDOPPORT_]="${TF[4]}"

			# Read and handle the Configure pat tab yad output
			[[ -s $TMPDIR/CONFIGURE_PAT.txt ]] || Die "Unexpected input from dialog"
			IFS='|' read -r -a TF < "$TMPDIR/CONFIGURE_ARDOP_PAT.txt"
			PAT_CALL="${TF[0]^^}"
			PAT_LOCATOR="${TF[1]}"
			PAT_HTTP_PORT="${TF[2]}"
			PAT_ARQ_BW_FORCED="${TF[4]}"
			PAT_ARQ_BW_MAX="${TF[5]}"
			F[_PAT_HTTP_]="${TF[6]}"

			# Update the pat config.json file with the new data.
			cat $PAT_CONFIG | jq \
				--arg C "$PAT_CALL" \
				--arg H "0.0.0.0:$PAT_HTTP_PORT" \
				--arg A "0.0.0.0:${F[_ARDOPPORT_]}" \
				--arg L "$PAT_LOCATOR" \
				--arg F "$PAT_ARQ_BW_FORCED" \
				--arg M "$PAT_ARQ_BW_MAX" \
					'.mycall = $C | .http_addr = $H | .ardop.addr = $A | .locator = $L | .ardop.arq_bandwidth.Forced = $F | .ardop.arq_bandwidth.Max = $M' | sponge $PAT_CONFIG

			# Update the yad configuration file.
			echo "declare -gA F" > "$CONFIG_FILE"
			for J in "${!F[@]}"
			do
   			echo "F[$J]='${F[$J]}'" >> "$CONFIG_FILE"
			done
			if [[ $(jq -r ".mycall" $PAT_CONFIG) == "" ||  ${F[_ADEVICE_CAPTURE_]} == "null" ]]
			then
				FIRST_RUN=true
			else
				FIRST_RUN=false
			fi
			;;
		*) # User click Exit button or closed window. 
			break
			;;
	esac
done
SafeExit