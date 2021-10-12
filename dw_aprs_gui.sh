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
#%   It is designed to work on the Nexus image.
#%
#% OPTIONS
#%    -h, --help                  Print this help
#%    -v, --version               Print script information
#%
#================================================================
#- IMPLEMENTATION
#-    version         ${SCRIPT_NAME} 2.1.5.4
#-    author          Steve Magnuson, AG7GN
#-    license         CC-BY-SA Creative Commons License
#-    script_id       0
#-
#================================================================
#  HISTORY
#     20200428 : Steve Magnuson : Script creation.
#     20200507 : Steve Magnuson : Bug fixes
#     20210316 : Steve Magnuson : Enabled using custom configs and
#                                 reduced complexity by using most
#                                 common filters, etc. Also added
#                                 fill-in digipeat mode
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
   pkill -f "bash -c tail -F ${F[_LOGFILE_]}"
	pkill -f "APRS Message"
   for P in $direwolf_PID $socat_PID $kissutil_PID ${YAD_PIDs[@]}
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
   for I in $(seq 20 27)
   do # I+1 is the field number.  D[$I] is the default value
           echo "$((I + 1)):${D[$I]}"
   done
}

function setDefaults () {
   declare -gA D
   D[1]="N0CALL"  # Call sign
   D[2]="0" # SSID
	D[3]="" # Tactical Callsign (if set, will be used instead of MYCALL)
   D[4]="Nexus DR-X" # Comment/Status
   D[5]="48.753318" # Latitude in decimal seconds
   D[6]="-122.472632" # Longitude in decimal seconds
   D[7]="Bellingham WA" # City/state/province
   D[8]="CN88" # Grid Square
   D[9]="10" # Rig power in watts
   D[10]="40" # Antenna height in feet above average terrain
   D[11]="5" # Antenna gain in dB
   D[12]="null" # Audio capture interface (ADEVICE)
   D[13]="null" # Audio playback interface (ADEVICE)
   D[14]="96000" # Audio playback rate (ARATE)
   D[15]="GPIO 23" # GPIO PTT (BCM pin)
   D[16]="8001" #AGW Port
   D[17]="8011" # KISS Port
   D[18]="0" # Direwolf text colors
   D[19]="disabled"  # Autostart APRS on boot
	D[20]="Monitor + Message Only" # digipeat/igate operating mode
	D[21]="" # Custom configuration file
	D[22]="TRUE" # Open monitor window at startup
	D[23]="" # Log file destination
}

function browseCustomFile () {
	echo "25:$(yad --center --file --title="Select your Direwolf config file")"
}

function upgradeSettings () {
	# Upgrades older configurations that didn't have the full and fill-in digipeat options
	# Old modes were: APRSMODEs="Digipeater~iGate (RX Only)~iGate (TX+RX)~Digipeater + iGate"
	sed -i -e "s/F\[_APRSMODE_\]='Digipeater'/F[_APRSMODE_]='Fill-in Digipeater'/" \
	       -e "s/F\[_APRSMODE_\]='Digipeater + iGate'/F[_APRSMODE_]='Fill-in Digipeater + iGate'/" \
	       -e "s/F\[_APRSMODE_\]='iGate (TX+RX)'/F[_APRSMODE_]='iGate'/" \
	       -e "/F\[_DIGIPEATDELAY_\]/d" \
	       -e "/F\[_DIGIPEATEVERY_\]/d" \
	       -e "/F\[_IGTXLIMIT1_\]/d" \
          -e "/F\[_IGTXLIMIT5_\]/d" \
          -e "/F\[_FILTER_\]/d" \
          -e "/F\[_SERVER_\]/d" \
          -e "/F\[_IGFILTER_\]/d"\
          -e "/F\[_HOPS_\]/d" \
          -e "/F\[_IGDELAY_\]/d" \
          -e "/F\[_AUDIOSTATS_\]/d" \
          -e "/F\[_IGEVERY_\]/d" "$1"
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
	   echo "F[_LAT_]='${D[5]}'" >> $1 # Latitude in decimal seconds
	   echo "F[_LONG_]='${D[6]}'" >> $1 # Longitude in decimal seconds
	   echo "F[_LOC_]='${D[7]}'" >> $1 # Location
	   echo "F[_GRID_]='${D[8]}'" >> $1 # Grid Square
	   echo "F[_POWER_]='${D[9]}'" >> $1 # Rig power in watts
	   echo "F[_HEIGHT_]='${D[10]}'" >> $1 # Antenna height in feet above average terrain
	   echo "F[_GAIN_]='${D[11]}'" >> $1 # Antenna gain in dB
	   echo "F[_ADEVICE_CAPTURE_]='${D[12]}'" >> $1 # Audio capture interface (ADEVICE)
	   echo "F[_ADEVICE_PLAY_]='${D[13]}'" >> $1 # Audio playback interface (ADEVICE)
	   echo "F[_ARATE_]='${D[14]}'" >> $1 # Audio playback rate (ARATE)
	   echo "F[_PTT_]='${D[15]}'" >> $1 # GPIO PTT (BCM pin)
	   echo "F[_AGWPORT_]='${D[16]}'" >> $1 # AGW Port
	   echo "F[_KISSPORT_]='${D[17]}'" >> $1 # KISS Port
	   echo "F[_COLORS_]='${D[18]}'" >> $1 # Direwolf text colors
		echo "F[_BOOTSTART_]='${D[19]}'" >> $1 # Piano switch autostart setting
		echo "F[_APRSMODE_]='${D[20]}'" >> $1 # digipeat/igate operating mode
		echo "F[_CUSTOM_]='${D[21]}'" >> $1 # Custom Direwolf config file
		echo "F[_MONITOR_]='${D[22]}'" >> $1 # Open monitor window
		echo "F[_LOGFILE_]='${D[23]}'" >> $1 # APRS Log File
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
   if [[ $ADEVICE_CAPTUREs =~ ${F[_ADEVICE_CAPTURE_]} ]]
   then
   	ADEVICE_CAPTUREs="$(echo "$ADEVICE_CAPTUREs" | sed "s/${F[_ADEVICE_CAPTURE_]}/\^${F[_ADEVICE_CAPTURE_]}/")"
   else
   	F[_ADEVICE_CAPTURE_] = "null"
   fi
   if [[ $ADEVICE_PLAYBACKs =~ ${F[_ADEVICE_PLAY_]} ]]
   then
   	ADEVICE_PLAYBACKs="$(echo "$ADEVICE_PLAYBACKs" | sed "s/${F[_ADEVICE_PLAY_]}/\^${F[_ADEVICE_PLAY_]}/")"
   else
   	F[_ADEVICE_PLAY_] = "null"
	fi
	# Generate sound card rates and selection
	ARATEs="48000~96000"
   [[ $ARATEs =~ ${F[_ARATE_]} ]] && ARATEs="$(echo "$ARATEs" | sed "s/${F[_ARATE_]}/\^${F[_ARATE_]}/")"

	# Generate PTT list and selection
	PTTs="GPIO 12~GPIO 23"
	[[ $PTTs =~ ${F[_PTT_]} ]] && PTTs="$(echo "$PTTs" | sed "s/${F[_PTT_]}/\^${F[_PTT_]}/")" || PTTs+="!^${F[_PTT_]}"

	#AUDIOSTATs="0~15~30~45~60~90~120"
   #[[ $AUDIOSTATs =~ ${F[_AUDIOSTATS_]} ]] && AUDIOSTATs="$(echo "$AUDIOSTATs" | sed "s/${F[_AUDIOSTATS_]}/\^${F[_AUDIOSTATS_]}/")"

	#APRSMODEs="Digipeater~iGate (RX Only)~iGate (TX+RX)~Digipeater + iGate"
	APRSMODEs="Monitor + Message Only~Custom~Fill-in Digipeater~Fill-in Digipeater + iGate~Full Digipeater~Full Digipeater + iGate~iGate~iGate (RX Only)"
	case ${F[_APRSMODE_]} in
		"Full Digipeater + iGate")
			APRSMODEs="$(echo "$APRSMODEs" | sed -e "s/Full Digipeater + iGate/\^Full Digipeater + iGate/1")"
			;;
		"Fill-in Digipeater + iGate")
			APRSMODEs="$(echo "$APRSMODEs" | sed -e "s/Fill-in Digipeater + iGate/\^Fill-in Digipeater + iGate/1")"
			;;
		"Full Digipeater")
			APRSMODEs="$(echo "$APRSMODEs" | sed -e "s/Full Digipeater/\^Full Digipeater/1")"
			;;
		"Fill-in Digipeater")
			APRSMODEs="$(echo "$APRSMODEs" | sed -e "s/Fill-in Digipeater/\^Fill-in Digipeater/1")"
			;;
		"iGate (RX Only)")
			APRSMODEs="$(echo "$APRSMODEs" | sed -e "s/iGate (RX/\^iGate (RX/1")"
			;;
		"iGate")
			APRSMODEs="$(echo "$APRSMODEs" | sed -e "s/~iGate/~\^iGate/1")"
			;;
		"Custom")
			APRSMODEs="$(echo "$APRSMODEs" | sed -e "s/Custom/\^Custom/1")"
			;;
		"Monitor + Message Only")
			APRSMODEs="$(echo "$APRSMODEs" | sed -e "s/Monitor + Message Only/\^Monitor + Message Only/1")"
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
		#[[ ${F[_COMMENT_]} =~ ${F[_CALL_]} ]] || F[_COMMENT_]="${F[_CALL_]} ${F[_COMMENT_]}"
		[[ ${F[_COMMENT_]} =~ ${F[_CALL_]} ]] || F[_COMMENT_]="${F[_CALL_]}-${F[_SSID_]} ${F[_COMMENT_]}"
	fi
	DIGIPEAT=""
	FILTER="$(echo "$FILTER_DEFAULT" | sed -e "s/_LAT_/${F[_LAT_]}/" -e "s/_LONG_/${F[_LONG_]}/")"
	IGFILTER="$IGFILTER_DEFAULT"
	IGLOGIN="IGLOGIN ${F[_CALL_]}-${F[_SSID_]} $(aprsPasscode ${F[_CALL_]})"
	IGSERVER="$IGSERVER_DEFAULT"
	IGTXLIMIT="$IGTXLIMIT_DEFAULT"
	IGTXVIA="$IGTXVIA_DEFAULT"
	PBEACON0=""
	PBEACON1=""
	PBEACON2=""
	PBEACON_IGATE=""
	COMMENT="${F[_COMMENT_]}"
	case ${F[_APRSMODE_]} in
		*Monitor*)
			IGFILTER=""
			IGLOGIN=""
			IGSERVER=""
			IGTXLIMIT=""
			IGTXVIA=""
			;;
		*Digi*) # Digipeater or Digipeater + iGate
			case ${F[_APRSMODE_]} in
				Full*)  # Full Digipeater
					DIGIPEAT="DIGIPEAT 0 0 ^WIDE[3-7]-[1-7]$ ^WIDE[12]-[12]$"
					;;
				Fill*)  # Fill-in Digipeater
					DIGIPEAT="DIGIPEAT 0 0 ^WIDE1-1$ ^WIDE1-1$"
					;;
					*)
						Die "Invalid APRS Mode"
					;;
			esac
			PBEACON0="PBEACON delay=1 every=30 symbol=\"digi\" overlay=S lat=${F[_LAT_]} long=${F[_LONG_]} POWER=${F[_POWER_]} HEIGHT=${F[_HEIGHT_]} GAIN=${F[_GAIN_]} COMMENT=\"$COMMENT\" via=WIDE2-2"
			PBEACON1="PBEACON delay=11 every=30 symbol=\"digi\" overlay=S lat=${F[_LAT_]} long=${F[_LONG_]} POWER=${F[_POWER_]} HEIGHT=${F[_HEIGHT_]} GAIN=${F[_GAIN_]} COMMENT=\"$COMMENT\" via=WIDE1-1,WIDE2-2"
			PBEACON2="PBEACON delay=21 every=30 symbol=\"digi\" overlay=S lat=${F[_LAT_]} long=${F[_LONG_]} POWER=${F[_POWER_]} HEIGHT=${F[_HEIGHT_]} GAIN=${F[_GAIN_]} COMMENT=\"$COMMENT\""
			if [[ ${F[_APRSMODE_]} =~ Digipeater$ ]]
			then # Digipeater only
				FILTER=""
				IGFILTER=""
				IGLOGIN=""
				IGSERVER=""
				IGTXLIMIT=""
				IGTXVIA=""
			else  # Digipeater + iGate
				PBEACON_IGATE="PBEACON sendto=IG delay=00:30 every=15:00 symbol=\"igate\" overlay=T lat=${F[_LAT_]} long=${F[_LONG_]} COMMENT=\"$COMMENT\""
			fi
			;;
 		"iGate (RX Only)") # iGate RX Only
			IGTXLIMIT=""
			IGTXVIA=""
			PBEACON_IGATE="PBEACON sendto=IG delay=00:30 every=15:00 symbol=\"igate\" overlay=R lat=${F[_LAT_]} long=${F[_LONG_]} COMMENT=\"$COMMENT\""
			;;
		iGate) #  iGate TX+RX
			PBEACON_IGATE="PBEACON sendto=IG delay=00:30 every=15:00 symbol=\"igate\" overlay=T lat=${F[_LAT_]} long=${F[_LONG_]} COMMENT=\"$COMMENT\""
			;;
		Custom)
			return
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
AGWPORT ${F[_AGWPORT_]}
KISSPORT ${F[_KISSPORT_]}
$PBEACON0
$PBEACON1
$PBEACON2
$PBEACON_IGATE
$IGLOGIN
$FILTER
$IGSERVER
$IGFILTER
$DIGIPEAT
$IGTXVIA
$IGTXLIMIT
EOF
}

function clearTextInfo () {
	# Arguments: $1 = sleep time.
	# Send FormFeed character every $1 minutes to clear yad text-info
	local TIMER=$1 
	while sleep $TIMER
	do
		#echo -e "\nTIMESTAMP: $(date)" 
		echo -e "\f"
		echo "$(date) Cleared monitor window. Window is cleared every $TIMER."
	done >$PIPEDATA
}

function killDirewolf () {
	# $1 is the direwolf PID
   if pgrep ^direwolf | grep -q $1 2>/dev/null
	then
		kill $1 >/dev/null 2>&1
		echo -e "\n\nDirewolf stopped.  Click \"Save & [Re]start...\" button below to restart." >$PIPEDATA
	else
		echo -e "\n\nDirewolf was already stopped.  Click \"Save & [Re]start...\" button below to restart." >$PIPEDATA
	fi
}

function monitorMessages () {

	# Looks for traffic received addressed to $1
	if [[ ! -z "${F[_LOGFILE_]}" ]]
	then
		local TITLE="Monitor APRS Messages to ${F[_CALL_]}"
		(( ${F[_SSID_]} == 0 )) && MYCALL="${F[_CALL_]}" || MYCALL="${F[_CALL_]}-${F[_SSID_]}"
		#local CMD="tail -F ${F[_LOGFILE_]} | grep -Eav '^[0-9]+,[0-9]+,.*,${MYCALL}' | grep '${F[_CALL_]}'"
		local CMD="tail -F ${F[_LOGFILE_]} | grep --line-buffered '${F[_CALL_]}'"

		#local CMD="socat -u udp-recv:3333,reuseaddr >(sed -u 's/\x1b\[[0-9;]*m//g' | grep -Eav '^\[.* [0-9]{8}T.*\] ${F[_CALL_]}>' | sed -En '/^\[.* [0-9]{8}T.*\] .*>/,/^$/p' | sed -En '/^\[.* [0-9]{8}T.*\] .*>.*::${F[_CALL_]}.*/,/^$/p')"
		lxterminal --geometry=80x15 -t "$TITLE" -e "$CMD" &
	fi

}

function sendMessage () {

	# Command to look for replies:
	# grep -Eav "^\[.* [0-9]{8}T.*\] $MYCALL>" /tmp/aprs | sed -En '/^\[.* [0-9]{8}T.*\] .*>/,/^$/p' | sed -En "/^\[.* [0-9]{8}T.*\] .*>.*::$MYCALL.*/,/^$/p"
	
	function sendingMessageAlert () {
		yad --width=300 --height=75 --title="Sending" --timeout=2 \
			--timeout-indicator=top --no-buttons --center --text="Sending $1"
	}
	
	function updateCache () {
		echo "ADD_PATH='$ADD_PATH'" > $MSG_CACHE_FILE
		echo "TO='$TO'" >> $MSG_CACHE_FILE
		echo "MESSAGE_TEXT='$MESSAGE_TEXT'" >> $MSG_CACHE_FILE
		echo "STATUS_TEXT='$STATUS_TEXT'" >> $MSG_CACHE_FILE
		echo "POSITION_TEXT='$POSITION_TEXT'" >> $MSG_CACHE_FILE	
	}
	
	function convertToDMdS () {
		LATLONG="LAT"
		for L in $1 $2
		do
		  	[[ $L =~ - ]] && SIGN=-1 || SIGN=1
		  	Y=${L#-}
		  	D=${Y%.*}
		  	# *Degree* minutes, so multiply by 60
		  	Z=$(bc -l <<< "60*($Y - $D)")
		  	M=${Z%.*}
		  	# *Decimal* seconds, so don't multiply by 60.
		  	S=$(bc -l <<< "$Z - $M")
		  	if [[ $LATLONG == "LAT" ]]
		  	then
				(( $SIGN == -1 )) && HEMISPHERE='S' || HEMISPHERE='N'
				printf -v LAT "%.2d%5.2f%s" $D ${M}${S} $HEMISPHERE
		  	else # Longitude
				(( $SIGN == -1 )) && HEMISPHERE='W' || HEMISPHERE='E'
				printf -v LONG "%.3d%5.2f%s" $D ${M}${S} $HEMISPHERE
		  	fi
		  	LATLONG="LONG"
		done
		echo "${LAT}/${LONG}"
	}

	MSG_CACHE_FILE="$HOME/.config/dw_aprs_message_cache"
	if [[ ! -s $MSG_CACHE_FILE ]]
	then
		echo "ADD_PATH=''" > $MSG_CACHE_FILE
		echo "TO=''" >> $MSG_CACHE_FILE
		echo "MESSAGE_TEXT=''" >> $MSG_CACHE_FILE
		echo "STATUS_TEXT=''" >> $MSG_CACHE_FILE
		echo "POSITION_TEXT='Station'" >> $MSG_CACHE_FILE
	fi
	source $MSG_CACHE_FILE
	MESSAGE_TYPE="${1^^}"
	MYCALL="${F[_CALL_]^^}"
	SSID="${F[_SSID_]}"
	GRID="${F[_GRID_]}"
	LOC="${F[_LOC_]}"
	if [[ -z $ADD_PATH ]]
	then
		APRS_PATHs="^CQ~ARISS~CQ,ARISS"
	else
		APRS_PATHs="^${ADD_PATH}~CQ~ARISS~CQ,ARISS"
	fi
	if [[ -z $MESSAGE_TEXT ]]
	then
		MESSAGEs="QSL & 73 ${MYCALL} in ${GRID::4}~Heard you in ${LOC} ${GRID::4}"
	else
		MESSAGEs="^${MESSAGE_TEXT}~QSL & 73 ${MYCALL} in ${GRID::4}~Heard you in ${LOC} ${GRID::4}"
	fi
	local APRS_VERSION="$(direwolf -h | grep -m1 "^Dire.*version" | tr -d '[:alpha:][:space:].')"
	[[ ${APRS_VERSION::2} =~ ^[0-9][0-9]$ ]] || APRS_VERSION="00"
	local APRS_PATH="APDW${APRS_VERSION::2}"
	
	MESSAGE_GUI_TEXT="<span color='red'><b>IMPORTANT! DO NOT USE</b></span> the '<b>~</b>' or '<b>^</b>' or '<b>|</b>' or '<b>{</b>' characters in any field below!" 
	
	case $MESSAGE_TYPE in
		FREE)
			while true
			do
				MSG=$(yad --center --width=400 --height=100 \
							--title="Free-form APRS Message" --text-align=center \
							--text="$MESSAGE_GUI_TEXT" --form --item-separator='~' \
							--field="APRS Path":CBE "$APRS_PATHs" \
							--field="Add message # (send until ACKed. UNCHECK for ARISS!)":CHK FALSE \
							--field="To" "$TO" \
							--field="Message (max\n67 characters)":CBE "$MESSAGEs" \
							--buttons-layout=center \
							--button="Cancel":1 --button="Send":0)
				if [[ $? == 0 ]]
				then
					ADD_PATH="$(echo $MSG | awk -F '|' '{print $1}')"
					[[ -z $ADD_PATH ]] || APRS_PATH+=",$ADD_PATH"
					APRS=$(echo $MSG | awk -F "|" '{print $2}')
					TO=$(echo $MSG | awk -F "|" '{print $3}')
					MESSAGE_TEXT=$(echo $MSG | awk -F '|' '{print $4}')
					#if [[ ! -z $TO && ! -z $APRS_PATH && ! -z $MESSAGE_TEXT ]]
					if [[ ! -z $TO && ! -z $MESSAGE_TEXT ]]
					then
						TO="${TO^^}"
						printf -v CALLSIGN %-9.9s "$TO"
						if [ $APRS == "TRUE" ]
						then
							local SEQ=$(echo $RANDOM | cut -b 1-3)
							SEQ="{$SEQ}"
							#echo "aprs set to true"
							printf "${MYCALL}-${SSID}>${APRS_PATH}::${CALLSIGN}:${MESSAGE_TEXT::67}${SEQ}" > $MSGPATH/free.txt
						else
							#echo "aprs set to false"
							printf "${MYCALL}-${SSID}>${APRS_PATH}::${CALLSIGN}:${MESSAGE_TEXT::67}" > $MSGPATH/free.txt
						fi
						sendingMessageAlert message
						updateCache
					fi
					APRS_PATH="APDW${APRS_VERSION::2}"
				else
					break
				fi
			done
			return
			;;
		STATUS)
			MSG=$(yad --center --width=400 --height=100 \
						--title="Status APRS Message" --text-align=center \
						--text="$MESSAGE_GUI_TEXT" --form --item-separator='~' \
						--field="APRS Path":CBE "$APRS_PATHs" \
						--field="Status Comment" "$STATUS_TEXT" \
						--buttons-layout=center \
						--button="Cancel":1 --button="Send":0)
			if [[ $? == 0 ]]
			then
				ADD_PATH="$(echo $MSG | awk -F '|' '{print $1}')"
				[[ -z $ADD_PATH ]] || APRS_PATH+=",$ADD_PATH"
				STATUS_TEXT=$(echo $MSG | awk -F "|" '{print $2}')
				if [[ ! -z $APRS_PATH && ! -z $STATUS_TEXT ]]
				then
					printf "${MYCALL}-${SSID}>${APRS_PATH}:>${MYCALL} ${STATUS_TEXT::67}" > $MSGPATH/status.txt
					sendingMessageAlert status
				fi
			else
				return
			fi
			;;
		POSITION)
			MSG=$(yad --center --width=400 --height=100 \
						--title="Position APRS Message" --text-align=center \
						--text="$MESSAGE_GUI_TEXT" --form --item-separator='~' \
						--field="APRS Path":CBE "$APRS_PATHs" \
						--field="Position Comment" "$POSITION_TEXT" \
						--buttons-layout=center \
						--button="Cancel":1 --button="Send":0)
			if [[ $? == 0 ]]
			then
				ADD_PATH="$(echo $MSG | awk -F '|' '{print $1}')"
				[[ -z $ADD_PATH ]] || APRS_PATH+=",$ADD_PATH"
				POSITION_TEXT=$(echo $MSG | awk -F "|" '{print $2}')
				if [[ ! -z $APRS_PATH && ! -z $POSITION_TEXT ]]
				then
					local PKT="${MYCALL}-${SSID}>${APRS_PATH}:=$(convertToDMdS ${F[_LAT_]} ${F[_LONG_]})x ${POSITION_TEXT::67}"
					echo $PKT > $MSGPATH/position.txt
					sendingMessageAlert position
				fi
			else
				return
			fi
			;;
		*)
			return
			;;
	esac
	updateCache

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

TITLE="Direwolf APRS Manager $VERSION"
CONFIG_FILE="$HOME/direwolf_aprs.conf"

CONFIG_TAB_TEXT="<b><big><big>Direwolf APRS Configuration</big></big></b>\n \
<span color='red'><b>DO NOT USE</b></span> the '<b>~</b>' or '<b>^</b>' characters in any field below!  \
Click the <b>Save...</b> button to save your changes and restart APRS.\n \
<span color='blue'>Note that if you select <b>Custom</b> for the APRS Mode, you must \
also select your own Direwolf configuration file using the button below. </span>\n \
<span color='red'>** No error checking is done on your custom configuration file. **\n</span>" 

ID="${RANDOM}"

#### APRS Default settings.
FILTER_DEFAULT="FILTER IG 0 ( i/30/8/_LAT_/_LONG_/16 | i/60/0 ) & g/W*/K*/A*/N*"
IGFILTER_DEFAULT="IGFILTER m/16"
IGSERVER_DEFAULT="IGSERVER noam.aprs2.net"
IGTXLIMIT_DEFAULT="IGTXLIMIT 6 10"
IGTXVIA_DEFAULT="IGTXVIA 0 WIDE1-1,WIDE2-1"

# YAD Dialog Window settings
POSX=10 
POSY=45 
WIDTH=1000

# Other settings
SOCAT_PORT=3333
AUDIO_STATS_INTERVAL=120
TIME_FORMAT="%Y%m%dT%H:%M:%S"
# Have direwolf allocate a pty
#DIREWOLF="$(command -v direwolf) -p -t 0 -d u"
# No pty
# Direwolf does not allow embedded spaces in timestamp format string -T
DIREWOLF="$(command -v direwolf) -a $AUDIO_STATS_INTERVAL -d u -T "$TIME_FORMAT""
RETURN_CODE=0
PIPE=$TMPDIR/pipe
mkfifo $PIPE
exec 6<> $PIPE

MSGPATH="$TMPDIR/MESSAGES"
mkdir -p $MSGPATH

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
for A in yad direwolf kissutil
do 
	command -v $A >/dev/null 2>&1 || Die "$A is required but not installed."
done

upgradeSettings $CONFIG_FILE
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

#export -f setDefaults loadAPRSDefaults killDirewolf browseCustomFile
export -f setDefaults killDirewolf browseCustomFile sendMessage monitorMessages
export MSGPATH
export click_browse_custom_file='@bash -c "browseCustomFile"'

#export load_aprs_defaults_cmd='@bash -c "setDefaults; loadAPRSDefaults"'
export click_aprs_help_cmd='bash -c "xdg-open /usr/local/share/nexus/aprs_help.html"'
export PIPEDATA=$PIPE

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

clearTextInfo_PID=""
direwolf_PID=""
kissutil_PID=""
YAD_PIDs=()

while true
do

	# Kill any running processes and load latest settings
	pkill -f "APRS Message"
	killDirewolf $direwolf_PID
#   for P in ${YAD_PIDs[@]} $clearTextInfo_PID
   for P in $clearTextInfo_PID $socat_PID $kissutil_PID ${YAD_PIDs[@]} 
	do
		kill $P >/dev/null 2>&1
	done
	rm -f $TMPDIR/CONFIGURE_APRS.txt
	#clearTextInfo_PID=""
	#direwolf_PID=""
	kissutil_PID=""
	YAD_PIDs=()

	# Retrieve saved settings or defaults if there are no saved settings
	loadSettings $CONFIG_FILE
	if [[ ${F[_ADEVICE_CAPTURE_]} == "null" || ${F[_ADEVICE_PLAY_]} == "null" ]]
	then
		yad --center --title="$TITLE" --borders=10 --text "<big><b>Audio device(s) are not set!</b></big>\nClick <b>Continue</b> below, then select the <b>Configure APRS</b> tab to select audio devices and PTT settings." --text-align=center --button="Continue":0 --buttons-layout=center
	fi
	
	# Start the monitor tab
	[[ $FIRST_RUN == true ]] && MODE_MESSAGE="" || MODE_MESSAGE="${F[_APRSMODE_]}"
	TEXT="<big><b>APRS $MODE_MESSAGE Status</b></big>\n<b>TNC PORTS:</b>   AGW=<span color='blue'><b>${F[_AGWPORT_]}</b></span>    KISS=<span color='blue'><b>${F[_KISSPORT_]}</b></span>"

	yad --plug="$ID" --tabnum=1 --text="$TEXT" --back=black --fore=yellow \
		--text-info --text-align=center \
		--tail --listen --center <&6 &
	#MONITOR_YAD_PID=$!
	#YAD_PIDs+=( $MONITOR_YAD_PID )
	YAD_PIDs+=( $! )
	#tail -F --pid=$MONITOR_YAD_PID -q -n 30 $LOGFILE 2>/dev/null | cat -v >&6 & 

	#clearTextInfo 15m &
   #clearTextInfo_PID=$!
   
	if [[ $FIRST_RUN == true ]]
	then
		echo -e "\n\nAPRS is not configured.\nConfigure it in the \"Configure APRS\" tab, then click the \"Save...\" button below." >&6
	else # Not a first run.  Direwolf appears to be configured so start it
		echo >&6
		if [[ ${F[_APRSMODE_]} =~ ^Custom ]]
		then
			if [[ ${F[_CUSTOM_]} == "" || ! -s ${F[_CUSTOM_]} ]]
			then
				echo -e "\n\nCustom mode requested, but no custom direwolf configuration file found.\nSelect your custom configuration file in the \"Configure APRS\" tab, then click the \"Save...\" button below." >&6
				RUN_OK=false
			else
				cp "${F[_CUSTOM_]}" $DW_CONFIG
				echo "Using Custom Direwolf configuration in ${F[_CUSTOM_]}:" >&6
				RUN_OK=true
			fi
		else # Non-custom APRS mode requested.
			echo "Using Direwolf configuration in $DW_CONFIG:" >&6
			RUN_OK=true
		fi

		if [[ $RUN_OK == true ]]
		then
			cat $DW_CONFIG | grep -v "^$" >&6
			echo >&6
			#[[ ${F[_AUDIOSTATS_]} == 0 ]] || DIREWOLF+=" -a ${F[_AUDIOSTATS_]}"
			# Open a terminal to receive the output from direwolf
			if [[ ${F[_MONITOR_]} == "TRUE" ]]
			then
				MONITOR_TITLE="APRS $MODE_MESSAGE Monitor"
				lxterminal --geometry=80x20 -t "$MONITOR_TITLE" -e "socat udp-recv:$SOCAT_PORT,reuseaddr -" &
				echo -e "" | socat - udp-sendto:127.255.255.255:$SOCAT_PORT,broadcast
				# Set background color of lxterminal if necessary
				#if [[ ${F[_COLORS_]} == 0 ]]
				#then
				#	echo -e "" | socat - udp-datagram:localhost:$SOCAT_PORT
				#else
				#	echo -e "\e[48;2;255;255;255m\e[0J\e[38;2;0;0;0m" | socat - udp-datagram:localhost:$SOCAT_PORT
				#fi
			fi
			# Send direwolf output to the terminal we opened earlier and also to
			# log file if specified
			if [[ -z ${F[_LOGFILE_]} ]]
			then
				DW_LOG=""
			else
				if truncate -s 0 "${F[_LOGFILE_]}"
				then
					DW_LOG="-L ${F[_LOGFILE_]}"
				else
					DW_LOG=""
					echo -e "\nUnable to create/write to ${F[_LOGFILE_]}. Logging disabled." >&6
				fi					
			fi
			($DIREWOLF -t ${F[_COLORS_]} -c $DW_CONFIG $DW_LOG 2>&6 | socat - udp-sendto:127.255.255.255:$SOCAT_PORT,broadcast) &
			direwolf_PID=$(pgrep -f "^$DIREWOLF -t ${F[_COLORS_]} -c $DW_CONFIG")
			socat_PID=$(pgrep -f "socat udp-recv:$SOCAT_PORT,reuseaddr -")
			if [[ $direwolf_PID == "" ]]
			then
				echo -e "\nDirewolf was *NOT* started" >&6
			else
				echo -e "\nDirewolf configured as APRS $MODE_MESSAGE mode has started. PID=$direwolf_PID" >&6
				if [[ ! ${F[_APRSMODE_]} =~ ^Custom ]]
				then
					echo -e "Direwolf listening on port ${F[_KISSPORT_]} for KISS connections." >&6
					echo -e "Direwolf listening on port ${F[_AGWPORT_]} for AGW connections." >&6
				fi
				KISSUTIL="$(command -v kissutil) -f $MSGPATH -h 127.0.0.1 -p ${F[_KISSPORT_]}"
				echo -e "Starting $KISSUTIL" >&6
				let COUNT=0
				while [[ -z $kissutil_PID ]]
				do
					sleep 1
					$KISSUTIL >&6 &
					kissutil_PID=$(pgrep -f "^$KISSUTIL")
					((COUNT++))
					(( $COUNT > 5 )) && break
				done
				[[ -z $kissutil_PID ]] && echo -e "\nkissutil did not start!" >&6 || echo -e "\nkissutil running. PID=$kissutil_PID" >&6
			fi
			if [[ $socat_PID != "" ]]
			then
				echo -e "\nExternal '$MONITOR_TITLE' running. PID=$socat_PID" >&6
				# Position the monitor window so it's not under the configuration window
				sleep 1
				wmctrl -r "$MONITOR_TITLE" -e "0,$(($POSX + $WIDTH + 5)),$POSY,-1,-1"
				#if [[ ! -z "${F[_LOGFILE_]}" ]]
				#then
				#	if truncate -s 0 "${F[_LOGFILE_]}"
				#	then
				#		(socat -u udp-recv:$SOCAT_PORT,reuseaddr >(sed -u 's/\x1b\[[0-9;]*m//g' > "${F[_LOGFILE_]}")) &
				#		log_PID=$!
				#		echo -e "\nLogging to ${F[_LOGFILE_]}" >&6	
				#	else
				#		echo -e "\nUnable to create/write to ${F[_LOGFILE_]}. Logging disabled." >&6
				#	fi					
				#fi
			fi
		fi
	fi
	
	# Start the Configure APRS tab
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
      --columns=2
      --text="$CONFIG_TAB_TEXT"
      --field="<b>Configuration Help</b>":FBTN
      --field="Open monitor window when [re]starting this script":CHK
      --field="Call"
      --field="SSID":NUM
      --field="Tactical Call"
      --field="Comment/Status"
      --field="LAT"
      --field="LONG"
		--field="Location"
		--field="Grid Square"
      --field="Power (watts)":NUM
      --field="Antenna HAAT (ft)":NUM
      --field="Antenna Gain (dB)":NUM
      --field="Direwolf Capture ADEVICE":CB
      --field="Direwolf Playback ADEVICE":CB
      --field="Direwolf ARATE":CB
      --field="Direwolf PTT":CBE
   	--field="AGW Port":NUM 
   	--field="KISS Port":NUM 
      --field="Direwolf text colors (0=off)":NUM
      --field="Log file (Will be overwritten)"
      --field="Autostart APRS when these\npiano switch levers are <b>ON</b>:":CB
      --field="<b>APRS Mode</b>":CB
      --field="<b>Select Direwolf config file (for APRS Mode Custom)</b>":FBTN
      --field="Custom mode config file:":RO
      --
      "$click_aprs_help_cmd"
      "${F[_MONITOR_]}"
      "${F[_CALL_]}"
      "${F[_SSID_]}~0..15~1~"
      "${F[_TACTICAL_CALL_]}"
      "${F[_COMMENT_]}"
      "${F[_LAT_]}"
      "${F[_LONG_]}"
      "${F[_LOC_]}"
      "${F[_GRID_]}"
      "${F[_POWER_]}~1..100~1~"
      "${F[_HEIGHT_]}~0..200~1~"
      "${F[_GAIN_]}~0..20~1~"
      "$ADEVICE_CAPTUREs"
      "$ADEVICE_PLAYBACKs"
      "$ARATEs"
      "$PTTs"
      "${F[_AGWPORT_]}~8001..8010~1~"
      "${F[_KISSPORT_]}~8011..8020~1~"
      "${F[_COLORS_]}~0..4~1~"
      "${F[_LOGFILE_]}"
      $BOOTSTARTs
      "$APRSMODEs"
      "$click_browse_custom_file"
      "${F[_CUSTOM_]}"
	)
	"${CMD[@]}" > $TMPDIR/CONFIGURE_APRS.txt &
	YAD_PIDs+=( $! )

	# Start the Send Messages tab
   yad --plug="$ID" --tabnum=3 --show-uri \
      --item-separator="~" \
      --separator="~" \
      --align=right \
      --text-align=center \
      --borders=10 \
      --form \
      --scroll \
      --columns=1 \
      --field="<b>Compose Free-form Message</b>":FBTN "bash -c 'source $CONFIG_FILE; sendMessage FREE'" \
      --field="<b>Compose Status Message</b>":FBTN "bash -c 'source $CONFIG_FILE; sendMessage STATUS'" \
      --field="<b>Compose Position Message</b>":FBTN "bash -c 'source $CONFIG_FILE; sendMessage POSITION'" \
      --field="":LBL "" \
      --field="<span color='blue'><b>Monitor incoming messages for ${F[_CALL_]}</b></span>":FBTN "bash -c 'source $CONFIG_FILE; monitorMessages'" >/dev/null &
	YAD_PIDs+=( $! )
	
	# Save the previous piano script autostart setting
	PREVIOUS_AUTOSTART="${F[_BOOTSTART_]}"

	# Set up a notebook with the 3 tabs.		
	#yad --title="$TITLE" --text="<b><big>Direwolf APRS Monitor and Configuration</big></b>" \
	yad --title="$TITLE" \
  		--text-align="center" --notebook --key="$ID" --window-icon=logviewer \
		--posx=$POSX --posy=$POSY --width=$WIDTH \
  		--buttons-layout=center \
  		--tab="Direwolf Status" \
  		--tab="Configure APRS" \
  		--tab="Messaging" \
  		--button="<b>Stop Direwolf APRS &#x26; Exit</b>":1 \
  		--button="<b>Stop Direwolf APRS</b>":"bash -c 'killDirewolf $direwolf_PID'" \
  		--button="<b>Save &#x26; [Re]start Direwolf APRS</b>":0 

	RETURN_CODE=$?

	case $RETURN_CODE in
		0) # Read and handle the Configure APRS tab yad output
         [[ -s $TMPDIR/CONFIGURE_APRS.txt ]] || Die "Unexpected input from dialog"
         IFS='~' read -r -a TF < "$TMPDIR/CONFIGURE_APRS.txt"
         F[_MONITOR_]="${TF[1]}"
         F[_CALL_]="${TF[2]^^}"
         F[_SSID_]="${TF[3]}"
         F[_TACTICAL_CALL_]="${TF[4]}"
         F[_COMMENT_]="${TF[5]}"
         F[_LAT_]="${TF[6]}"
         F[_LONG_]="${TF[7]}"
			F[_LOC_]="${TF[8]}"
			F[_GRID_]="${TF[9]}"
         F[_POWER_]="${TF[10]}"
         F[_HEIGHT_]="${TF[11]}"
         F[_GAIN_]="${TF[12]}"
         F[_ADEVICE_CAPTURE_]="${TF[13]}"
         F[_ADEVICE_PLAY_]="${TF[14]}"
         F[_ARATE_]="${TF[15]}"
         F[_PTT_]="${TF[16]}"
         F[_AGWPORT_]="${TF[17]}"
         F[_KISSPORT_]="${TF[18]}"
         F[_COLORS_]="${TF[19]}"
         F[_LOGFILE_]="${TF[20]}"
         F[_BOOTSTART_]="${TF[21]}"
         F[_APRSMODE_]="${TF[22]}"
         [[ ${F[_APRSMODE_]} =~ ^Custom ]] && F[_CUSTOM_]="${TF[24]}" || F[_CUSTOM_]=""
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

