#!/bin/bash
#================================================================
# HEADER
#================================================================
#% SYNOPSIS
#+   ${SCRIPT_NAME} [-hv]
#%
#% DESCRIPTION
#%   This script provides a GUI to configure and start/stop
#%   Direwolf as an iGate, Digipeater or both.  
#%   It is designed to work on the Hampi image.
#%
#% OPTIONS
#%    -h, --help                  Print this help
#%    -v, --version               Print script information
#%
#================================================================
#- IMPLEMENTATION
#-    version         ${SCRIPT_NAME} 1.0.5
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
   #pkill "^direwolf"
   #kill $timeStamp_PID >/dev/null 2>&1
   kill $direwolf_PID >/dev/null 2>&1
   for P in ${YAD_PIDs[@]}
	do
		kill $P >/dev/null 2>&1
	done
	echo "quit" >&6
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

function aprsPasscode () {
	# Generates the APRS website passcode from the supplied callsign
	local CALL="$(echo ${1^^} | cut -d'-' -f1)"
	local H="0x73e2"
	declare -i LEN=${#CALL}
	declare -i I=0
	while [ $I -lt $LEN ]
	do
	   H=$(( $H ^ $(($(printf '%d' "'${CALL:$I:2}") << 8)) ))
	   H=$(( $H ^ $(printf '%d' "'${CALL:$(( I+1 )):2}") ))
	   (( I+=2 ))
	done
	echo -n $(( $H & 0x7fff ))
}

function loadAPRSDefaults () {
   for I in $(seq 19 28)
   do # I+1 is the field number.  D[$I] is the default value
           echo "$((I + 1)):${D[$I]}"
   done
}

function setDefaults () {
   declare -gA D
   D[1]="N0CALL"  # Call sign
   D[2]="0" # SSID
	D[3]="" # Tactical Callsign (if set, will be used instead of MYCALL)
   D[4]="Comment/Status" # Comment/Status
   D[5]="Bellingham, WA" # Location
   D[6]="CN88SS" # Grid Square
   D[7]="48.753318" # Latitude in decimal seconds
   D[8]="-122.472632" # Longitude in decimal seconds
   D[9]="10" # Rig power in watts
   D[10]="40" # Antenna height in feet above average terrain
   D[11]="5" # Antenna gain in dB
   D[12]="null" # Audio capture interface (ADEVICE)
   D[13]="null" # Audio playback interface (ADEVICE)
   D[14]="96000" # Audio playback rate (ARATE)
   D[15]="GPIO 23" # GPIO PTT (BCM pin)
   D[16]="60" # Audio stats interval
	D[17]="iGate (RX Only)"
   D[18]="disabled"  # Autostart APRS on boot
   D[19]="6" # iGate tansmit limit per minute
   D[20]="10" # iGate transmit limit per 5 minutes
   D[21]="( i/30/8/\$LAT/\$LONG/16 | i/60/0 ) & g/W*/K*/A*/N*" # iGate server > TX filter
   D[22]="noam.aprs2.net"  # iGate server
   D[23]="m/16" # TX messages from iGate server to stations within 16KM (10 miles)
   D[24]="WIDE1-1,WIDE2-1" # Hops
   D[25]="00:30" # Wait time in mm:ss to send position beacon after startup (sent to iGate server)
   D[26]="15:00" # Position beacon send interval in mm:ss (sent to iGate server)
   D[27]="00:30" # Wait time in mm:ss to TX position beacon after startup
   D[28]="10:00" # Position beacon TX interval in mm:ss
}

function loadSettings () {

	DW_CONFIG="$TMPDIR/direwolf.conf"
	if [ -s "$1" ]
	then # There is a config file.  Load it.
		source "$1"
	else # If there is no config file, save the defaults to a new config file and load it
		setDefaults
		echo "declare -gA F" > $1
		echo "F[_CALL_]='${D[1]}'" >> $1  # Call sign
	   echo "F[_SSID_]='${D[2]}'" >> $1      # SSID
	   echo "F[_TACTICAL_CALL_]='${D[3]}'" >> $1 # Tactical Callsign
	   echo "F[_COMMENT_]='${D[4]}'" >> $1 # Comment or tactical call
	   echo "F[_LOC_]='${D[5]}'" >> $1 # Location
	   echo "F[_GRID_]='${D[6]}'" >> $1 # Grid Square
	   echo "F[_LAT_]='${D[7]}'" >> $1 # Latitude in decimal seconds
	   echo "F[_LONG_]='${D[8]}'" >> $1 # Longitude in decimal seconds
	   echo "F[_POWER_]='${D[9]}'" >> $1 # Rig power in watts
	   echo "F[_HEIGHT_]='${D[10]}'" >> $1 # Antenna height in feet above average terrain
	   echo "F[_GAIN_]='${D[11]}'" >> $1 # Antenna gain in dB
	   echo "F[_ADEVICE_CAPTURE_]='${D[12]}'" >> $1 # Audio capture interface (ADEVICE)
	   echo "F[_ADEVICE_PLAY_]='${D[13]}'" >> $1 # Audio playback interface (ADEVICE)
	   echo "F[_ARATE_]='${D[14]}'" >> $1 # Audio playback rate (ARATE)
	   echo "F[_PTT_]='${D[15]}'" >> $1 # GPIO PTT (BCM pin)
	   echo "F[_AUDIOSTATS_]='${D[16]}'" >> $1 # Audio stats interval
		echo "F[_APRSMODE_]='${D[17]}'" >> $1 #
	   echo "F[_BOOTSTART_]='${D[18]}'" >> $1 # Autostart APRS on boot
	   echo "F[_IGTXLIMIT1_]='${D[19]}'" >> $1 # iGate tansmit limit per minute
	   echo "F[_IGTXLIMIT5_]='${D[20]}'" >> $1 # iGate transmit limit per 5 minutes
	   echo "F[_FILTER_]='${D[21]}'" >> $1 # iGate server > TX filter
	   echo "F[_SERVER_]='${D[22]}'" >> $1 # iGate server
	   echo "F[_IGFILTER_]='${D[23]}'" >> $1 # TX messages from iGate server to stations within 16KM (10 miles)
	   echo "F[_HOPS_]='${D[24]}'" >> $1 # Hops
	   echo "F[_IGDELAY_]='${D[25]}'" >> $1 # Wait time in mm:ss to send position beacon after startup (sent to iGate server)
	   echo "F[_IGEVERY_]='${D[26]}'" >> $1 # Position beacon send interval in mm:ss (sent to iGate server)
	   echo "F[_DIGIPEATDELAY_]='${D[27]}'" >> $1 # Wait time in mm:ss to TX position beacon after startup
	   echo "F[_DIGIPEATEVERY_]='${D[28]}'" >> $1 # Position beacon TX interval in mm:ss
		source "$1"
	fi

	# Generate sound card list and selection

	if pgrep pulseaudio >/dev/null 2>&1
   then # There may be pulseaudio ALSA devices.  Look for them.
      CAPTURE_IGNORE="$(pacmd list-sinks 2>/dev/null | grep name: | tr -d '\t' | cut -d' ' -f2 | sed 's/^<//;s/>$//' | tr '\n' '\|' | sed 's/|/\\|/g')"
      ADEVICE_CAPTUREs="$(arecord -L | grep -v "$CAPTURE_IGNORE^ .*\|^dsnoop\|^sys\|^default\|^dmix\|^hw\|^usbstream\|^jack\|^pulse" | tr '\n' '~' | sed 's/~$//')"
      PLAYBACK_IGNORE="$(pacmd list-sources 2>/dev/null | grep name: | tr -d '\t' | cut -d' ' -f2 | sed 's/^<//;s/>$//' | tr '\n' '\|' | sed 's/|/\\|/g')"
      ADEVICE_PLAYBACKs="$(aplay -L | grep -v "$PLAYBACK_IGNORE^ .*\|^dsnoop\|^sys\|^default\|^dmix\|^hw\|^usbstream\|^jack\|^pulse" | tr '\n' '~' | sed 's/~$//')"
   else  # pulseaudio isn't running.  Check only for null and plughw devices
      ADEVICE_CAPTUREs="$(arecord -L | grep "^null\|^plughw" | tr '\n' '~' | sed 's/~$//')"
      ADEVICE_PLAYBACKs="$(aplay -L | grep "^null\|^plughw" | tr '\n' '~' | sed 's/~$//')"
   fi
   [[ $ADEVICE_CAPTUREs =~ ${F[_ADEVICE_CAPTURE_]} ]] && ADEVICE_CAPTUREs="$(echo "$ADEVICE_CAPTUREs" | sed "s/${F[_ADEVICE_CAPTURE_]}/\^${F[_ADEVICE_CAPTURE_]}/")" || F[_ADEVICE_CAPTURE_] = "null" 
   [[ $ADEVICE_PLAYBACKs =~ ${F[_ADEVICE_PLAY_]} ]] && ADEVICE_PLAYBACKs="$(echo "$ADEVICE_PLAYBACKs" | sed "s/${F[_ADEVICE_PLAY_]}/\^${F[_ADEVICE_PLAY_]}/")" || F[_ADEVICE_PLAY_] = "null"

	# Generate sound card rates and selection
	ARATEs="48000~96000"
   [[ $ARATEs =~ ${F[_ARATE_]} ]] && ARATEs="$(echo "$ARATEs" | sed "s/${F[_ARATE_]}/\^${F[_ARATE_]}/")"

	# Generate PTT list and selection
	PTTs="GPIO 12~GPIO 23"
	[[ $PTTs =~ ${F[_PTT_]} ]] && PTTs="$(echo "$PTTs" | sed "s/${F[_PTT_]}/\^${F[_PTT_]}/")" || PTTs+="!^${F[_PTT_]}"

	AUDIOSTATs="0~15~30~45~60~90~120"
   [[ $AUDIOSTATs =~ ${F[_AUDIOSTATS_]} ]] && AUDIOSTATs="$(echo "$AUDIOSTATs" | sed "s/${F[_AUDIOSTATS_]}/\^${F[_AUDIOSTATS_]}/")"

	APRSMODEs="Digipeater~iGate (RX Only)~iGate (TX+RX)~Digipeater + iGate"
	case ${F[_APRSMODE_]} in
		"Digipeater + iGate")
			APRSMODEs="$(echo "$APRSMODEs" | sed "s/Digipeater + iGate/\^Digipeater + iGate/")"
			;;
		Digipeater)
			APRSMODEs="$(echo "$APRSMODEs" | sed "s/Digipeater/\^Digipeater/1")"
			;;
		"iGate (RX Only)")
			APRSMODEs="$(echo "$APRSMODEs" | sed "s/iGate (RX/\^iGate (RX/1")"
			;;
		"iGate (TX+RX)")
			APRSMODEs="$(echo "$APRSMODEs" | sed "s/iGate (TX/\^iGate (TX/1")"
			;;
	esac

	BOOTSTARTs="disabled~none~1~12~13~14~123~124~134~1234~2~23~234~24~3~34~4"
	[[ $BOOTSTARTs =~ ${F[_BOOTSTART_]} && ${F[_BOOTSTART_]} =~ ^(none|[1-4]{1,4})$ ]] && BOOTSTARTs="$(echo "$BOOTSTARTs" | sed "s/~${F[_BOOTSTART_]}/~\^${F[_BOOTSTART_]}/1")" || BOOTSTARTs="^$BOOTSTARTs" 

	# Use Tactical call if set instead of regular call-ssid.
	if [[ ${F[_TACTICAL_CALL_]} == "" ]]
	then
		MYCALL="${F[_CALL_]}-${F[_SSID_]}"
	else
		MYCALL="${F[_TACTICAL_CALL_]}"
		# Prepend CALL if not already present in COMMENT.
		[[ ${F[_COMMENT_]} =~ ${F[_CALL_]} ]] || F[_COMMENT_]="${F[_CALL_]} ${F[_COMMENT_]}"
	fi

	case ${F[_APRSMODE_]} in
		Digi*) # Digipeater or Digipeater + iGate
			if [[ ${F[_APRSMODE_]} == "Digipeater" ]]
			then # Digipeater only
				IGLOGIN=""
				IGTXVIA=""
				COMMENT="${F[_COMMENT_]} Digipeater | ${F[_LOC_]}"
				PBEACON="PBEACON delay=${F[_DIGIPEATDELAY_]} every=${F[_DIGIPEATEVERY_]} symbol=\"digi\" overlay=S lat=${F[_LAT_]} long=${F[_LONG_]} POWER=${F[_POWER_]} HEIGHT=${F[_HEIGHT_]} GAIN=${F[_GAIN_]} COMMENT=\"$COMMENT\" via=${F[_HOPS_]}"
			else # Digipeater + iGate
				IGTXVIA="IGTXVIA 0 ${F[_HOPS_]}"
				COMMENT="${F[_COMMENT_]} Digipeater+iGate | ${F[_LOC_]}"
				PBEACON="PBEACON sendto=IG delay=${F[_IGDELAY_]} every=${F[_IGEVERY_]} symbol=\"igate\" overlay=T lat=${F[_LAT_]} long=${F[_LONG_]} COMMENT=\"$COMMENT\""
				IGLOGIN="IGLOGIN ${F[_CALL_]}-${F[_SSID_]} $(aprsPasscode ${F[_CALL_]})"
				FILTER="FILTER IG 0 $(echo "${F[_FILTER_]}" | sed -e "s/\$LAT/${F[_LAT_]}/" -e "s/\$LONG/${F[_LONG_]}/")"
				IGFILTER="IGFILTER ${F[_IGFILTER_]}"
				IGSERVER="IGSERVER ${F[_SERVER_]}"
			fi
			DIGIPEAT="DIGIPEAT 0 0 ^WIDE[3-7]-[1-7]$|^TEST$ ^WIDE[12]-[12]$ TRACE"
			;;
 		"iGate (RX Only)") # iGate RX Only
			DIGIPEAT=""
			IGTXVIA=""
			COMMENT="${F[_COMMENT_]} iGate | ${F[_LOC_]}"
			PBEACON="PBEACON sendto=IG delay=${F[_IGDELAY_]} every=${F[_IGEVERY_]} symbol=\"igate\" overlay=R lat=${F[_LAT_]} long=${F[_LONG_]} COMMENT=\"$COMMENT\""
			IGLOGIN="IGLOGIN ${F[_CALL_]}-${F[_SSID_]} $(aprsPasscode ${F[_CALL_]})"
			IGSERVER="IGSERVER ${F[_SERVER_]}"
			FILTER="FILTER IG 0 $(echo "${F[_FILTER_]}" | sed -e "s/\$LAT/${F[_LAT_]}/" -e "s/\$LONG/${F[_LONG_]}/")"
			IGFILTER="IGFILTER ${F[_IGFILTER_]}"
			;;
		"iGate (TX+RX)") # iGate TX+RX
			DIGIPEAT=""
			IGTXVIA="IGTXVIA 0 ${F[_HOPS_]}"
			COMMENT="${F[_COMMENT_]} iGate | ${F[_LOC_]}"
			PBEACON="PBEACON sendto=IG delay=${F[_IGDELAY_]} every=${F[_IGEVERY_]} symbol=\"igate\" overlay=T lat=${F[_LAT_]} long=${F[_LONG_]} COMMENT=\"$COMMENT\""
			IGLOGIN="IGLOGIN ${F[_CALL_]}-${F[_SSID_]} $(aprsPasscode ${F[_CALL_]})"
			IGSERVER="IGSERVER ${F[_SERVER_]}"
			FILTER="FILTER IG 0 $(echo "${F[_FILTER_]}" | sed -e "s/\$LAT/${F[_LAT_]}/" -e "s/\$LONG/${F[_LONG_]}/")"
			IGFILTER="IGFILTER ${F[_IGFILTER_]}"
			;;
		*)
			Die "Invalid mode choice"
			;;
	esac
	
	# Create a Direwolf config file with these settings
	cat > $DW_CONFIG <<EOF
ADEVICE ${F[_ADEVICE_CAPTURE_]} ${F[_ADEVICE_PLAY_]}
ACHANNELS 1
CHANNEL 0
ARATE ${F[_ARATE_]}
PTT ${F[_PTT_]}
MYCALL $MYCALL
MODEM 1200
AGWPORT 0
KISSPORT 0
$PBEACON
$IGLOGIN
$FILTER
$IGSERVER
$IGFILTER
$DIGIPEAT
$IGTXVIA
$IGTXLIMIT
EOF

}

#function timeStamp () {
#   exec 6<> $PIPEDATA
#	while sleep 60
#	do
#		echo -e "\nTIMESTAMP: $(date)" 
#	done >&6
#}

function killDirewolf () {
	# $1 is the direwolf PID
   if pgrep ^direwolf | grep -q $1 2>/dev/null
	then
		kill $1 >/dev/null 2>&1
		echo -e "\n\nDirewolf stopped.  Click \"Restart...\" button below to restart." >&6
	else
		echo -e "\n\nDirewolf was already stopped.  Click \"Restart...\" button below to restart." >&6
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

TITLE="Direwolf APRS Monitor and Configuration $VERSION"
CONFIG_FILE="$HOME/direwolf_aprs.conf"

CONFIG_TAB_TEXT="<b><big><big>Direwolf APRS Configuration</big></big></b>\n \
<span color='red'><b>DO NOT USE</b></span> the '<b>~</b>' character in any field below. \
     Click the <b>Restart...</b> button to save your changes and restart APRS.\n"

ID="${RANDOM}"

RETURN_CODE=0

PIPE=$TMPDIR/pipe
mkfifo $PIPE
exec 6<> $PIPE

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
pidof -o %PPID -x $(basename "$0") >/dev/null && Die "$(basename $0) already running."

# Check for required apps.
for A in yad direwolf
do 
	command -v $A >/dev/null 2>&1 || Die "$A is required but not installed."
done

loadSettings $CONFIG_FILE

# If this is the first time running this script, don't attempt to start Direwolf
# or pat until user configures both.
if [[ -s $CONFIG_FILE ]]
then # Direwolf configuration files exists
	if [[ ${F[_ADEVICE_CAPTURE_]} == "null" || ${F[_CALL_]} == "N0CALL" ]]
	then # Config file present, but not configured
		FIRST_RUN=true
	else # Config files present and configured
		FIRST_RUN=false
	fi
else # No configuration files exist
	FIRST_RUN=true
fi

export -f setDefaults loadAPRSDefaults killDirewolf
export load_aprs_defaults_cmd='@bash -c "setDefaults; loadAPRSDefaults"'
export click_aprs_help_cmd='bash -c "xdg-open /usr/local/share/hampi/aprs_help.html"'
#export PIPEDATA=$PIPE

#============================
#  MAIN SCRIPT
#============================

# Trap bad exits with cleanup function
trap SafeExit EXIT INT TERM SIGINT

# Exit on error. Append '||true' when you run the script if you expect an error.
#set -o errexit

# Check Syntax if set
$SYNTAX && set -n
# Run in debug mode, if set
$DEBUG && set -x 

timeStamp_PID=""
direwolf_PID=""
YAD_PIDs=()

while true
do

	# Have direwolf allocate a pty
	#DIREWOLF="$(command -v direwolf) -p -t 0 -d u"
	# No pty
	DIREWOLF="$(command -v direwolf) -t 0 -d u"

	# Kill any running processes and load latest settings
	killDirewolf $direwolf_PID
#   for P in ${YAD_PIDs[@]} $timeStamp_PID
   for P in ${YAD_PIDs[@]}
	do
		ps x | egrep -q "^$P" && kill $P
	done
	rm -f $TMPDIR/CONFIGURE_APRS.txt
	
	# Retrieve saved settings or defaults if there are no saved settings
	loadSettings $CONFIG_FILE
	YAD_PIDs=()
	
	# Start the monitor tab
	[[ $FIRST_RUN == true ]] && MODE_MESSAGE="" || MODE_MESSAGE="${F[_APRSMODE_]}"
	TEXT="<big><b>Direwolf $MODE_MESSAGE APRS Monitor</b></big>"
	yad --plug="$ID" --tabnum=1 --text="$TEXT" --show-uri --show-cursor \
		--back=black --fore=yellow \
		--text-info --text-align=center \
		--tail --center <&6 &
	YAD_PIDs+=( $! )

   # Start the Time Stamper function
	#timeStamp &
   #timeStamp_PID=$!

	if [[ $FIRST_RUN == true ]]
	then
		echo -e "\n\nDirewolf was not started because APRS is not configured.\nConfigure it in the \"Configure APRS\" tab, then click the \"Restart...\" button below." >&6
	else # Not a first run.  Direwolf appears to be configured so start it
		echo >&6
		echo "Using Direwolf configuration in $DW_CONFIG:" >&6
		cat $DW_CONFIG | grep -v "^$" >&6
		echo >&6
		[[ ${F[_AUDIOSTATS_]} == 0 ]] || DIREWOLF+=" -a ${F[_AUDIOSTATS_]}"
		$DIREWOLF -c $DW_CONFIG >&6 2>&6 &
		direwolf_PID=$!
		echo -e "\n\nDirewolf APRS has started. PID=$direwolf_PID" >&6
	fi
	# Start the Configure APRS.
	CMD=(
		yad --plug="$ID" --tabnum=2 --show-uri 
  		--item-separator="~" 
		--separator="~" 
		--align=right 
  		--text-align=center 
  		--align=right 
  		--borders=10 
  		--form 
		--scroll
		--columns=3 
		--text="$CONFIG_TAB_TEXT" 
   	--field="Call"
   	--field="SSID":NUM
		--field="Tactical Call"
   	--field="Comment/Status"
   	--field="Location"
   	--field="Grid Square"
   	--field="LAT"
   	--field="LONG"
   	--field="Power (watts)":NUM
		--field="Antenna HAAT (ft)":NUM
   	--field="Antenna Gain (dB)":NUM
   	--field="Direwolf Capture ADEVICE":CB
   	--field="Direwolf Playback ADEVICE":CB
   	--field="Direwolf ARATE":CB
   	--field="Direwolf PTT":CBE
		--field="Direwolf Audio Stats (show\nevery x sec. 0 disables)":CB
   	--field="Autostart APRS when these\npiano switch levers are <b>ON</b>:":CB
   	--field="<b>  APRS Settings </b>\t\t\t\t\t\t":LBL
   	--field="APRS Mode":CB
   	--field="iGate TX Limit /min"
   	--field="iGate TX Limit /5 min"
		--field="Client&#x3A; FILTER IG 0"
   	--field="iGate Server"
		--field="Server&#x3A; IGFILTER"
		--field="Hops&#x3A; IGTXVIA 0"
   	--field="iGate Beacon\nDelay (mm&#x3A;ss)"
   	--field="iGate Beacon\nInterval (mm&#x3A;ss)"
   	--field="Digipeat Beacon\nDelay (mm&#x3A;ss)"
   	--field="Digipeat Beacon\nInterval (mm&#x3A;ss)"
   	--field="<b>Load Default APRS Settings</b>":FBTN
   	--field="<b>Configuration Help</b>":FBTN
   	-- 
   	"${F[_CALL_]}" 
   	"${F[_SSID_]}~0..15~1~" 
	   "${F[_TACTICAL_CALL_]}"	
   	"${F[_COMMENT_]}" 
   	"${F[_LOC_]}" 
   	"${F[_GRID_]}" 
   	"${F[_LAT_]}" 
   	"${F[_LONG_]}" 
   	"${F[_POWER_]}~1..100~1~" 
   	"${F[_HEIGHT_]}~0..200~1~" 
   	"${F[_GAIN_]}~0..20~1~" 
   	"$ADEVICE_CAPTUREs" 
   	"$ADEVICE_PLAYBACKs" 
   	"$ARATEs"  
   	"$PTTs" 
   	"$AUDIOSTATs" 
   	$BOOTSTARTs 
   	"@disabled@"
   	"$APRSMODEs"
   	"${F[_IGTXLIMIT1_]}" 
   	"${F[_IGTXLIMIT5_]}" 
   	"${F[_FILTER_]}" 
   	"${F[_SERVER_]}" 
   	"${F[_IGFILTER_]}" 
   	"${F[_HOPS_]}" 
   	"${F[_IGDELAY_]}" 
   	"${F[_IGEVERY_]}" 
   	"${F[_DIGIPEATDELAY_]}" 
   	"${F[_DIGIPEATEVERY_]}"
   	"$load_aprs_defaults_cmd" 
   	"$click_aprs_help_cmd"
	)
	"${CMD[@]}" > $TMPDIR/CONFIGURE_APRS.txt &
	YAD_PIDs+=( $! )

	# Save the previous piano script autostart setting
	PREVIOUS_AUTOSTART="${F[_BOOTSTART_]}"

	# Set up a notebook with the 3 tabs.		
	#yad --title="$TITLE" --text="<b><big>Direwolf APRS Monitor and Configuration</big></b>" \
	yad --title="$TITLE" \
  		--text-align="center" --notebook --key="$ID" \
		--posx=10 --posy=45 --width=1100 --height=700 \
  		--buttons-layout=center \
  		--tab="Monitor APRS" \
  		--tab="Configure APRS" \
  		--button="<b>Stop Direwolf APRS &#x26; Exit</b>":1 \
  		--button="<b>Stop Direwolf APRS</b>":"bash -c 'killDirewolf $direwolf_PID'" \
  		--button="<b>Restart Direwolf APRS</b>":0
	RETURN_CODE=$?

	case $RETURN_CODE in
		0) # Read and handle the Configure APRS tab yad output
			[[ -s $TMPDIR/CONFIGURE_APRS.txt ]] || Die "Unexpected input from dialog"
			IFS='~' read -r -a TF < "$TMPDIR/CONFIGURE_APRS.txt"
			F[_CALL_]="${TF[0]^^}"
			F[_SSID_]="${TF[1]}"
			F[_TACTICAL_CALL_]="${TF[2]}"
			F[_COMMENT_]="${TF[3]}"
			F[_LOC_]="${TF[4]}"
			F[_GRID_]="${TF[5]}"
			F[_LAT_]="${TF[6]}"
			F[_LONG_]="${TF[7]}"
			F[_POWER_]="${TF[8]}"
			F[_HEIGHT_]="${TF[9]}"
			F[_GAIN_]="${TF[10]}"
			F[_ADEVICE_CAPTURE_]="${TF[11]}"
			F[_ADEVICE_PLAY_]="${TF[12]}"
			F[_ARATE_]="${TF[13]}"
			F[_PTT_]="${TF[14]}"
			F[_AUDIOSTATS_]="${TF[15]}"
			F[_BOOTSTART_]="${TF[16]}"
			F[_APRSMODE_]="${TF[18]}"
			F[_IGTXLIMIT1_]="${TF[19]}"
			F[_IGTXLIMIT5_]="${TF[20]}"
			F[_FILTER_]="${TF[21]}"
			F[_SERVER_]="${TF[22]}"
			F[_IGFILTER_]="${TF[23]}"
			F[_HOPS_]="${TF[24]}"
			F[_IGDELAY_]="${TF[25]}"
			F[_IGEVERY_]="${TF[26]}"
			F[_DIGIPEATDELAY_]="${TF[27]}"
			F[_DIGIPEATEVERY_]="${TF[28]}"

			## Update the yad configuration file.
			echo "declare -gA F" > "$CONFIG_FILE"
			for J in "${!F[@]}"
			do
   			echo "F[$J]='${F[$J]}'" >> "$CONFIG_FILE"
			done
			if [[ ${F[_ADEVICE_CAPTURE_]} == "null" || ${F[_CALL_]} == "N0CALL" ]]
			then # Looks like new values are default. Force FIRST_RUN and require configuration before starting
				FIRST_RUN=true
			else
				FIRST_RUN=false
			fi
			# Make autostart piano switch script if necessary
			if [[ ${F[_BOOTSTART_]} == "disabled" ]]
			then # Disable autostart
				[[ $PREVIOUS_AUTOSTART =~ none ]] && SWITCHES="" || SWITCHES="$PREVIOUS_AUTOSTART" 
				# Save previous piano script if it exists
				[[ -s $HOME/piano${SWITCHES}.sh ]] && mv -f $HOME/piano${SWITCHES}.sh $HOME/piano${SWITCHES}.sh.$(date '+%Y%m%d') 
	 		else # Enable autostart
				if [[ ${F[_BOOTSTART_]} != $PREVIOUS_AUTOSTART ]]
				then # Previous autostart was not the same as the requested autostart
					[[ $PREVIOUS_AUTOSTART =~ none ]] && SWITCHES="" || SWITCHES="$PREVIOUS_AUTOSTART" 
					# Save previous piano script if it exists
					[[ -s $HOME/piano${SWITCHES}.sh ]] && mv -f $HOME/piano${SWITCHES}.sh $HOME/piano${SWITCHES}.sh.$(date '+%Y%m%d') 
					[[ ${F[_BOOTSTART_]} =~ none ]] && SWITCHES="" || SWITCHES="${F[_BOOTSTART_]}" 
					echo -e "#!/bin/bash\nsleep 5\n$(command -v $(basename $0)) >/dev/null 2>&1" > $HOME/piano${SWITCHES}.sh
					chmod +x $HOME/piano${SWITCHES}.sh
				fi
			fi		
			;;
		*) # 1, 252, or anything else.  User click Exit button or closed window. 
			break
			;;
	esac
done
SafeExit

