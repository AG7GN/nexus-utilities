#!/bin/bash
#================================================================
# HEADER
#================================================================
#% SYNOPSIS
#+   ${SCRIPT_NAME} [-hv]
#%
#% DESCRIPTION
#%   This script provides a GUI to configure and start/stop
#%   Direwolf and pat.  It is designed to work on the Hampi image.
#%
#% OPTIONS
#%    -h, --help                  Print this help
#%    -v, --version               Print script information
#%
#================================================================
#- IMPLEMENTATION
#-    version         ${SCRIPT_NAME} 1.7.1
#-    author          Steve Magnuson, AG7GN
#-    license         CC-BY-SA Creative Commons License
#-    script_id       0
#-
#================================================================
#  HISTORY
#     20200428 : Steve Magnuson : Script creation.
#     20200507 : Steve Magnuson : Bug fixes
#     20200719 : Steve Magnuson : Improved handling of pat rigctl
#                                 settings
#     20200726 : Steve Magnuson : Added time stamps to Direwolf
#                                 traffic logged events & modem
#											 options expanded to 
#                                 300,1200,2400,4800,9600
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
   kill $clearTextInfo_PID >/dev/null 2>&1
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
   for I in $(seq 10 13)
   do # I is the field number.  D[$I] is the default value
      echo "${I}:${D[$((I-3))]}"
   done
}

function setTNCpatDefaults () {
   declare -gA D
   D[1]="N0CALL"  # Call sign
   D[2]="1200" # Modem
   D[3]="null" # Audio capture interface (ADEVICE)
   D[4]="null" # Audio playback interface (ADEVICE)
   D[5]="96000" # Audio playback rate (ARATE)
   D[6]="GPIO 23" # GPIO PTT (BCM pin)
   D[7]="200" # TX Delay
	D[8]="50" # TX Tail
   D[9]="64"  # Persist
   D[10]="20" # Slot Time
   D[11]="60" # Audio Stats
   D[12]="8001" # AGW Port
   D[13]="8010"  # KISS Port
   D[14]="FALSE" # Enable pat HTTP server
}

function loadSettings () {
	 
	MODEMs="300!1200!2400!4800!9600"
   ARATEs="48000!96000"
   PTTs="GPIO 12!GPIO 23!RIG 2 localhost:4532"
	DW_CONFIG="$TMPDIR/direwolf.conf"

	if [ -s "$CONFIG_FILE" ]
	then # There is a config file
   	echo "$CONFIG_FILE found." >&3
  		source "$CONFIG_FILE"
	else # Set some default values in a new config file
   	echo -e "Config file $CONFIG_FILE not found.\nCreating a new one with default values." >&3
		setTNCpatDefaults
   	echo "declare -gA F" > "$CONFIG_FILE"
   	echo "F[_CALL_]='${D[1]}'" >> "$CONFIG_FILE"
   	echo "F[_MODEM_]='${D[2]}'" >> "$CONFIG_FILE"
   	echo "F[_ADEVICE_CAPTURE_]='${D[3]}'" >> "$CONFIG_FILE"
   	echo "F[_ADEVICE_PLAY_]='${D[4]}'" >> "$CONFIG_FILE"
   	echo "F[_ARATE_]='${D[5]}'" >> "$CONFIG_FILE"
   	echo "F[_PTT_]='${D[6]}'" >> "$CONFIG_FILE"
   	echo "F[_TXDELAY_]='${D[7]}'" >> "$CONFIG_FILE"
   	echo "F[_TXTAIL_]='${D[8]}'" >> "$CONFIG_FILE"
   	echo "F[_PERSIST_]='${D[9]}'" >> "$CONFIG_FILE"
   	echo "F[_SLOTTIME_]='${D[10]}'" >> "$CONFIG_FILE"
   	echo "F[_AUDIOSTATS_]='${D[11]}'" >> "$CONFIG_FILE"
   	echo "F[_AGWPORT_]='${D[12]}'" >> "$CONFIG_FILE"
   	echo "F[_KISSPORT_]='${D[13]}'" >> "$CONFIG_FILE"
   	echo "F[_PAT_HTTP_]='${D[14]}'" >> "$CONFIG_FILE"
   	source "$CONFIG_FILE"
	fi

	MYCALL="${F[_CALL_]}"
   [[ $MODEMs =~ ${F[_MODEM_]} ]] && MODEMs="$(echo "$MODEMs" | sed "s/${F[_MODEM_]}/\^${F[_MODEM_]}/")"

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

   [[ $ARATEs =~ ${F[_ARATE_]} ]] && ARATEs="$(echo "$ARATEs" | sed "s/${F[_ARATE_]}/\^${F[_ARATE_]}/")"

	if [[ $PTTs =~ ${F[_PTT_]} ]]
   then
      PTTs="$(echo "$PTTs" | sed "s/${F[_PTT_]}/\^${F[_PTT_]}/")"
   else
      PTTs+="!^${F[_PTT_]}"
   fi
	
	TXDELAY="${F[_TXDELAY_]}"
	TXTAIL="${F[_TXTAIL_]}"
	PERSIST="${F[_PERSIST_]}"
	SLOTTIME="${F[_SLOTTIME_]}"
	
	AUDIOSTATs="0!15!30!45!60!90!120"
   [[ $AUDIOSTATs =~ ${F[_AUDIOSTATS_]} ]] && AUDIOSTATs="$(echo "$AUDIOSTATs" | sed "s/${F[_AUDIOSTATS_]}/\^${F[_AUDIOSTATS_]}/")"

	AGWPORT="${F[_AGWPORT_]}"
	KISSPORT="${F[_KISSPORT_]}"

	# Create a Direwolf config file with these settings
	cat > $DW_CONFIG <<EOF
ADEVICE ${F[_ADEVICE_CAPTURE_]} ${F[_ADEVICE_PLAY_]}
ACHANNELS 1
CHANNEL 0
ARATE ${F[_ARATE_]}
PTT ${F[_PTT_]}
MYCALL ${F[_CALL_]}
MODEM ${F[_MODEM_]}
AGWPORT ${F[_AGWPORT_]}
KISSPORT ${F[_KISSPORT_]}
EOF

	PAT_START_HTTP="${F[_PAT_HTTP_]}"
	PAT_CALL="$(jq -r ".mycall" $PAT_CONFIG)"
	PAT_PASSWORD="$(jq -r ".secure_login_password" $PAT_CONFIG)"
	PAT_HTTP_PORT="$(jq -r ".http_addr" $PAT_CONFIG | cut -d: -f2)"
	PAT_TELNET_PORT="$(jq -r ".telnet.listen_addr" $PAT_CONFIG | cut -d: -f2)"
	PAT_TELNET_PASSWD="$(jq -r ".telnet.password" $PAT_CONFIG)"
	PAT_LOCATOR="$(jq -r ".locator" $PAT_CONFIG)"
	PAT_BEACON_INTERVAL="$(jq -r ".ax25.beacon.every" $PAT_CONFIG)"
	PAT_BEACON_MESSAGE="$(jq -r ".ax25.beacon.message" $PAT_CONFIG)"
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
		echo -e "\n\nDirewolf stopped.  Click \"Save Settings...\" button below to restart." >$PIPEDATA
	else
		echo -e "\n\nDirewolf was already stopped.  Click \"Save Settings...\" button below to restart." >$PIPEDATA
	fi
}

function getRig() {
   # Arg1: Hamlib ID of rig.  Function returns rig manufacturer and name
	LINE="$($(command -v rigctl) -l | grep -v "^ Rig" | egrep "^[[:space:]]*$1")"
	N="$(trim "${LINE:2:4}")"
	M="$(trim "${LINE:8:23}")"
  	O="$(trim "${LINE:31:24}")"
	echo "$M $O"
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

TITLE="Direwolf TNC Monitor and Configuration $VERSION"
CONFIG_FILE="$HOME/direwolf_tnc.conf"
MESSAGE="Direwolf Configuration"

ID="${RANDOM}"

AX25PORT="wl2k"
AX25PORTFILE="/etc/ax25/axports"
PAT_CONFIG="$HOME/.wl2k/config.json"

RETURN_CODE=0
# Direwolf does not allow embedded spaces in timestamp format string -T
DIREWOLF="$(command -v direwolf) -p -t 0 -d u -T "%Y%m%dT%H:%M:%S""
#PAT="$(command -v pat) --log /dev/stdout -l ax25,telnet http"
PAT="$(command -v pat) -l ax25,telnet http"

PIPE=$TMPDIR/pipe
mkfifo $PIPE
exec 3<> $PIPE

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

# Check for pat's config file, config.json.  Create it if missing or corrupted.
RESULT="$(jq . $PAT_CONFIG 2>/dev/null)"
if [[ $RESULT == "" ]]
then # config.json missing or corrupted.  Make a new one.
	[[ -f $PAT_CONFIG ]] && rm $PAT_CONFIG
	cd $HOME
	export EDITOR=ed
	echo -n "" | pat configure >/dev/null 2>&1
fi

# Set up pat for rigctl in config.json
cat $PAT_CONFIG | jq \
   '.hamlib_rigs += {"network": {"address": "localhost:4532", "network": "tcp"}}' | sponge $PAT_CONFIG
# Add the network Hamlib rig to the ax25 section
cat $PAT_CONFIG | jq --arg R "network" '.ax25.rig = $R' | sponge $PAT_CONFIG

export -f setTNCpatDefaults loadpatDefaults
export load_pat_defaults_cmd='@bash -c "setTNCpatDefaults; loadpatDefaults"'
export click_dw_pat_help_cmd='bash -c "xdg-open /usr/local/share/hampi/dw_pat_gui_help.html"'
export PIPEDATA=$PIPE

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

#clearTextInfo &
#clearTextInfo_PID=$!

direwolf_PID=""
pat_PID=""
YAD_PIDs=()

while true
do
	# Kill any running processes and load latest settings
	killDirewolf $direwolf_PID
	[[ $pat_PID == "" ]] || kill $pat_PID >/dev/null 2>&1
   for P in $clearTextInfo_PID ${YAD_PIDs[@]} 
	do
		kill $P >/dev/null 2>&1
	done
	# If an unrelated pat is running, kill it too
	#pgrep pat >/dev/null && pkill pat
	# Kill kissattach
   sudo pgrep kissattach >/dev/null && sudo pkill kissattach	
	rm -f $TMPDIR/CONFIGURE_TNC.txt $TMPDIR/CONFIGURE_PAT.txt
   rm -f /tmp/kisstnc
	loadSettings
	YAD_PIDs=()
	
	# Start the tail window tab
	TEXT="<b>TNC PORTS:</b>   AGW=<span color='blue'><b>$AGWPORT</b></span>    KISS=<span color='blue'><b>$KISSPORT</b></span>    AX.25=<span color='blue'><b>$AX25PORT</b></span>"
	[[ $PAT_START_HTTP == TRUE ]] && TEXT+="     <b>pat PORTS:</b> telnet=<span color='blue'><b>$PAT_TELNET_PORT</b></span>   web=<span color='blue'><b>http://$HOSTNAME.local:$PAT_HTTP_PORT</b></span>"
	yad --plug="$ID" --tabnum=1 \
		--back=black --fore=yellow --selectable-labels \
		--text-info --text-align=center --text="$TEXT" \
		--tail --listen --center <&3 &
	YAD_PIDs+=( $! )

	clearTextInfo 60m &
   clearTextInfo_PID=$!

	# Start rigctld.  
	if pgrep rigctld >/dev/null
	then
		echo "rigctld already running." >&3
	else # Start rigctl as a dummy rig because we have no idea what rig is used.
		echo "Starting rigctld using dummy rig..." >&3
		$(command -v rigctld) -m 1 >&3 2>&3 &
		RIG_PID=$!
		echo "Done." >&3
	fi

	if [[ $FIRST_RUN == true ]]
	then
		echo -e "Configure Direwolf TNC and pat in the \"Configure TNC\" and \"Configure pat\" tabs,\nthen click \"Save Settings...\" button below." >&3
	else # Not a first run.  pat and Direwolf configured so start 'em
		# Configure /etc/ax25/axports if necessary.  This is needed in order to allocate a PTY for pat.
		if ! grep -q "^$AX25PORT[[:space:]]*$MYCALL" $AX25PORTFILE 2>/dev/null
		then #$AX25PORT $MYCALL entry not found
			# Remove existing lines with $AX25PORT and any empty lines if present
			sudo sed -i -e "s/^$AX25PORT[[:space:]].*$//g" -e '/^[[:space:]]*$/d' $AX25PORTFILE
			# Add the entry for $MYCALL
			echo "$AX25PORT	$MYCALL	0	255	7	Winlink" | sudo tee --append $AX25PORTFILE >/dev/null
		fi
		# Start Direwolf
		[[ ${F[_AUDIOSTATS_]} == 0 ]] || DIREWOLF+=" -a ${F[_AUDIOSTATS_]}"
		$DIREWOLF -c $DW_CONFIG >&3 2>&3 &
		direwolf_PID=$!
		echo -e "\n\nDirewolf TNC has started.  PID=$direwolf_PID" >&3

		# Wait for Direwolf to allocate a PTY
   	COUNTER=0
   	MAXWAIT=8
   	while [ $COUNTER -lt $MAXWAIT ]
   	do # Allocate a PTY to ax25
      	[ -L /tmp/kisstnc ] && break
      	sleep 1
      	let COUNTER=COUNTER+1
   	done
   	if [ $COUNTER -ge $MAXWAIT ]
		then
			Die "Direwolf failed to allocate a PTY! Aborting. Is ADEVICE set to your sound card?"
		fi
   	echo "Direwolf has allocated a PTY." >&3

		# Start kissattach on new PTY
   	sudo $(command -v kissattach) $(readlink -f /tmp/kisstnc) $AX25PORT >&3 2>&1
   	[ $? -eq 0 ] || Die "kissattach failed.  Aborting."
		KISSPARMS="-c 1 -p $AX25PORT -t $TXDELAY -l $TXTAIL -s $SLOTTIME -r $PERSIST -f n"
		echo "Setting $(command -v kissparms) $KISSPARMS" >&3
		sleep 2
   	sudo $(command -v kissparms) $KISSPARMS >&3 2>&3
   	[ $? -eq 0 ] || Die "kissparms settings failed.  Aborting."

		# Start pat
		if [[ $PAT_START_HTTP == TRUE ]]
		then
			$PAT >&3 2>&3 &
			pat_PID=$!
		else
			pat_PID=""
		fi
	fi 
	
	# Set up tab for configuring Direwolf.
	yad --plug="$ID" --tabnum=2 \
  		--text="<b><big><big>Direwolf TNC Configuration</big></big></b>\n\n \
<b><u><big>Typical Direwolf Sound Card and PTT Settings for Nexus DR-X</big></u></b>\n \
<span color='blue'><b>LEFT Radio:</b></span> Use ADEVICEs \
<b>fepi-capture-left</b> and <b>fepi-playback-left</b> and PTT <b>GPIO 12</b>.\n \
<span color='blue'><b>RIGHT Radio:</b></span> Use ADEVICEs \
<b>fepi-capture-right</b> and <b>fepi-playback-right</b> and PTT <b>GPIO 23</b>.\n\n \
Click the <b>Save Settings...</b> button below after you make your changes.\n\n" \
  		--item-separator="!" \
		--separator="|" \
  		--text-align=center \
  		--align=right \
  		--borders=20 \
  		--form \
		--columns=2 \
     	--field="<b>Call Sign</b>" "$MYCALL" \
  	  	--field="<b>Direwolf Capture ADEVICE</b>":CB "$ADEVICE_CAPTUREs" \
     	--field="<b>Direwolf Playback ADEVICE</b>":CB "$ADEVICE_PLAYBACKs" \
  	  	--field="<b>Direwolf ARATE</b>":CB "$ARATEs" \
   	--field="<b>Direwolf MODEM</b>":CB "$MODEMs" \
   	--field="<b>Direwolf PTT</b>":CBE "$PTTs" \
		--field="<b>Audio Stats interval (s)</b>":CB "$AUDIOSTATs" \
   	--field="<b>AGW Port</b>":NUM "$AGWPORT!8001..8010!1!" \
   	--field="<b>KISS Port</b>":NUM "$KISSPORT!8011..8020!1!" \
  		--focus-field 1 > $TMPDIR/CONFIGURE_TNC.txt &
	YAD_PIDs+=( $! )

	# Set up tab for pat configuration
	yad --plug="$ID" --tabnum=3 \
		--text="<b><big><big>pat Configuration</big></big></b>\n\n \
Click the <b>Save Settings...</b> button below after you make your changes.\n\n" \
		--item-separator="!" \
		--separator="|" \
  		--text-align=center \
  		--align=right \
  		--borders=20 \
  		--form \
		--columns=2 \
     	--field="Call Sign" "$PAT_CALL" \
		--field="Winlink Password":H "$PAT_PASSWORD" \
		--field="Locator Code" "$PAT_LOCATOR" \
   	--field="Web Service Port":NUM "$PAT_HTTP_PORT!8040..8049!1!" \
   	--field="Telnet Service Port":NUM "$PAT_TELNET_PORT!8770..8779!1!" \
   	--field="Telnet Service Password\n(default&#x3A; no password)" "$PAT_TELNET_PASSWD" \
   	--field="Beacon Interval (s)\n(0 disables beacon)":NUM "$PAT_BEACON_INTERVAL!0..7200!1!" \
   	--field="Beacon Message" "$PAT_BEACON_MESSAGE" \
   	--field="Start pat web service when Direwolf TNC starts":CHK "$PAT_START_HTTP" \
   	--field="TX Delay (ms)":NUM "$TXDELAY!0..500!1!" \
  		--field="TX Tail (ms)":NUM "$TXTAIL!0..200!10!" \
   	--field="Persist":NUM "$PERSIST!0..255!1!" \
		--field="Slot Time (ms)":NUM "$SLOTTIME!0..255!10!" \
   	--field="<b>Load Default AX25 Timers</b>":FBTN "$load_pat_defaults_cmd" \
		--field="<b>Edit pat Connection Aliases</b>":FBTN "bash -c edit_pat_aliases.sh &" \
  		--focus-field 1 > $TMPDIR/CONFIGURE_PAT.txt &
	YAD_PIDs+=( $! )
	[[ $PAT_START_HTTP == TRUE ]] && AND_PAT=" + pat" || AND_PAT=""

	# Set up tab with form button to launch pat web interface
	#yad --plug="$ID" --tabnum=4 --text-align="center" \
	#	--text="<big><b>Open pat Web Interface</b></big>" --form \
	#	--field="<b>Open pat Web Interface</b>":FBTN "bash -c xdg-open >/dev/null &" >/dev/null &
	#YAD_PIDs+=( $! )

	# Set up tab to present button to launch rigctld manager
	RIGCTL_INFO=" \
The rig control daemon (rigctld) is part of Hamlib. It provides a way to control \
various rigs using CAT commands, usually over a serial port.\n\nIn order to set up \
aliases (shortcuts) in the pat web interface for RMS Gateway stations ALONG WITH \
their frequency, pat requires the use of rigctld. When started, the GUI you're \
currently using will check to see if rigctld is already running. If it's not, it'll \
start rigctld using a 'dummy' rig, which fools pat into thinking it's controlling a \
radio when it's not (meaning you have to set your radio's frequency manually).\n\nIf \
your rig is supported by Hamlib (or to check to see if it is supported), click the \
'Manage Hamlib rigctld' button below to have the TNC and pat REALLY talk to your \
radio (if supported) and have pat automatically QSY as needed."
	yad --plug="$ID" --tabnum=4 --text-align=center --borders=20 --form --wrap \
		--text="<big><b>Hamlib Rig Control (rigctld)</b></big>" \
		--field="":TXT "$RIGCTL_INFO" \
		--field="<b>Manage Hamlib rigctld</b>":FBTN "bash -c rigctl_gui.sh >/dev/null &" >/dev/null &
	YAD_PIDs+=( $! )

	if [[ $pat_PID == "" ]]
	then
		cat > $TMPDIR/pat_web.sh <<EOF
yad --center --title="Error" --borders=20 --text "<b>pat is not running.\nNo web interface to open.</b>" --button="Close":0 --buttons-layout=center
EOF
	else
		cat > $TMPDIR/pat_web.sh <<EOF
xdg-open http://$HOSTNAME.local:$PAT_HTTP_PORT >/dev/null 2>&1
EOF
	fi
	chmod +x $TMPDIR/pat_web.sh
	
	# Set up a notebook with the tabs.		
	yad --title="Direwolf TNC and pat $VERSION" --text="<b><big>Direwolf TNC$AND_PAT Configuration and Operation</big></b>" \
  		--text-align="center" --notebook --key="$ID" \
		--posx=10 --posy=50 \
  		--buttons-layout=center \
  		--tab="Monitor" \
  		--tab="Configure TNC" \
  		--tab="Configure pat" \
  		--tab="Rig Control" \
		--width="800" --height="600" \
  		--button="<b>Stop Direwolf$AND_PAT &#x26; Exit</b>":1 \
  		--button="<b>Save Settings &#x26; Restart Direwolf$AND_PAT</b>":0 \
  		--button="<b>Open pat Web interface</b>":"bash -c $TMPDIR/pat_web.sh" \
  		--button="<b>Help</b>":"$click_dw_pat_help_cmd"
	RETURN_CODE=$?

	case $RETURN_CODE in
		0) # Read and handle the Configure TNC tab yad output
			[[ -s $TMPDIR/CONFIGURE_TNC.txt ]] || Die "Unexpected input from dialog"
			IFS='|' read -r -a TF < "$TMPDIR/CONFIGURE_TNC.txt"
			F[_CALL_]="${TF[0]^^}"
			F[_ADEVICE_CAPTURE_]="${TF[1]}"
			F[_ADEVICE_PLAY_]="${TF[2]}"
			F[_ARATE_]="${TF[3]}"
			F[_MODEM_]="${TF[4]}"
			F[_PTT_]="${TF[5]}"
			F[_AUDIOSTATS_]="${TF[6]}"
			F[_AGWPORT_]="${TF[7]}"
			F[_KISSPORT_]="${TF[8]}"

			# Read and handle the Configure pat tab yad output
			[[ -s $TMPDIR/CONFIGURE_PAT.txt ]] || Die "Unexpected input from dialog"
			IFS='|' read -r -a TF < "$TMPDIR/CONFIGURE_PAT.txt"
			PAT_CALL="${TF[0]^^}"
			PAT_PASSWORD="${TF[1]}"
			PAT_LOCATOR="${TF[2]^^}"
			PAT_HTTP_PORT="${TF[3]}"
			PAT_TELNET_PORT="${TF[4]}"
			PAT_TELNET_PASSWD="${TF[5]}"
			PAT_BEACON_INTERVAL="${TF[6]}"
			PAT_BEACON_MESSAGE="${TF[7]}"
			F[_PAT_HTTP_]="${TF[8]}"
			F[_TXDELAY_]="${TF[9]}"
			F[_TXTAIL_]="${TF[10]}"
			F[_PERSIST_]="${TF[11]}"
			F[_SLOTTIME_]="${TF[12]}"

			# Update the pat config.json file with the new data.
			cat $PAT_CONFIG | jq \
				--arg C "$PAT_CALL" \
				--arg P "$PAT_PASSWORD" \
				--arg H "0.0.0.0:$PAT_HTTP_PORT" \
				--arg T "0.0.0.0:$PAT_TELNET_PORT" \
				--arg A "$PAT_TELNET_PASSWD" \
				--arg L "$PAT_LOCATOR" \
				--argjson I $PAT_BEACON_INTERVAL \
				--arg M "$PAT_BEACON_MESSAGE" \
					'.mycall = $C | .secure_login_password = $P | .http_addr = $H | .telnet.listen_addr = $T | .telnet.password = $A |.locator = $L | .ax25.beacon.every = $I | .ax25.beacon.message = $M' | sponge $PAT_CONFIG

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