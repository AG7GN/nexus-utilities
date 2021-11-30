#!/bin/bash
#================================================================
# HEADER
#================================================================
#% SYNOPSIS
#+   ${SCRIPT_NAME} [-hv]
#%
#% DESCRIPTION
#%   This script provides a GUI to configure and operate rigctld.
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
#     20200609 : Steve Magnuson : Script creation.
#     20200718 : Steve Magnuson : Delete unused function.
#     20211129 : Steve Magnuson : Updated to suppor new locations
#											 for pat confuguration
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

function TrapCleanup () {
   for P in ${YAD_PIDs[@]}
	do
		kill $P >/dev/null 2>&1
	done
	rm -f $fpipe
	#exec 4>&-
}

function SafeExit() {
	TrapCleanup
   trap - INT TERM EXIT
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

function runFind () {
	echo "2:@disable@"
	echo -e '\f' >> "$fpipe"
	while IFS= read -r LINE
	do
		N="$(trim "${LINE:2:4}")"
		M="$(trim "${LINE:8:23}")"
  		O="$(trim "${LINE:31:24}")"
		echo -e "\n$N\n$M\n$O" >> "$fpipe"
	done < <($(command -v rigctl) -l | grep -v "^ Rig" | sed -e 's/&/&#x26;/g' | grep -i "$1")
	echo "2:$find_cmd"
}
export -f runFind

function viewDeleteAliases () {
	# Load existing aliases
	while true
	do
		# Read aliases from $PAT_CONFIG
		ALIASES="$(jq -r .connect_aliases $PAT_CONFIG | egrep -v "telnet|{|}" | \
				  sed 's/^ /FALSE|/' | tr -d ' ",' | sed 's/:/|/1' | tr '|' '\n')"
		RESULT="$(yad --title="View/remove pat aliases" --list --mouse --borders=10 \
				--height=400 --width=400 --text-align=center \
				--text "<b>Your current pat connection aliases are listed below.</b>\n \
Check the ones you want to remove.\n" \
				--checklist --grid-lines=hor --auto-kill --column="Pick" --column="Call" --column="Connect URI" \
				<<< "$ALIASES" --buttons-layout=center --button="Exit":1 --button="Refresh list":0 --button="Remove selected aliases":0)"
		if [[ $? == 0 ]]
		then # Refresh or removal requested
      	while IFS="|" read -r CHK KEY VALUE REMAINDER
			do # read each checked alias
				if [[ $CHK == "TRUE" ]]
				then # Remove alias
					cat $PAT_CONFIG | jq --arg K "$KEY" --arg V "$VALUE" \
						'(.connect_aliases | select(.[$K] == $V)) |= del (.[$K])' | sponge $PAT_CONFIG
				fi
			done <<< "$RESULT"	
		else # User cancelled
			break
		fi
	done
	exit 0
}
export -f viewDeleteAliases

function trim() {
  # Trims leading and trailing white space from a string
  local s2 s="$*"
  until s2="${s#[[:space:]]}"; [ "$s2" = "$s" ]; do s="$s2"; done
  until s2="${s%[[:space:]]}"; [ "$s2" = "$s" ]; do s="$s2"; done
  echo "$s"
}
export -f trim

function getRig() {
	LINE="$($(command -v rigctl) -l | grep -v "^ Rig" | egrep "^[[:space:]]*$1")"
	N="$(trim "${LINE:2:4}")"
	M="$(trim "${LINE:8:23}")"
  	O="$(trim "${LINE:31:24}")"
	echo "$M $O"
}

function setrigctldDefaults () {
   declare -gA D
   D[1]="1|Hamlib|Dummy"  # Rig ID
   D[2]="Not Applicable" # Serial Port
   D[3]="Not Applicable" # Serial Port Speed
}

function getSerialPorts() {
	# Returns '|' list of the basenames of all files /dev/serial/by-id 
	PORTS="Not Applicable|"
	for P in /dev/serial/by-id/*
	do
		PORTS+="$(basename "$P")|"
	done
	[[ $1 != "" && $PORTS =~ $1 ]] && echo "$PORTS" | sed -e "s/$1/^$1/" -e 's/|$//' || echo "$PORTS" | sed -e 's/|$//'
}

function getSpeeds() {
	# Returns '|' list of serial port speeds
	SPEEDs="Not Applicable|300|1200|2400|4800|9600|19200|38400|57600|115200"
	[[ $1 != "" && $SPEEDs =~ $1 ]] && echo "$SPEEDs" | sed -e "s/$1/^$1/" || echo "$SPEEDs"
}

function loadSettings () {
	if [ -s "$CONFIG_FILE" ]
	then # There is a config file
   	#echo "$CONFIG_FILE found." >&3
  		source "$CONFIG_FILE"
	else # Set some default values in a new config file
   	#echo -e "Config file $CONFIG_FILE not found.\nCreating a new one with default values." >&3
		setrigctldDefaults
   	echo "declare -gA F" > "$CONFIG_FILE"
   	echo "F[_RIG_]='${D[1]}'" >> "$CONFIG_FILE"
   	echo "F[_PORT_]='${D[2]}'" >> "$CONFIG_FILE"
   	echo "F[_SPEED_]='${D[3]}'" >> "$CONFIG_FILE"
   	source "$CONFIG_FILE"
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

TITLE="Hamlib Rig Control (rigctld) Configuration $VERSION"
CONFIG_FILE="$HOME/rigctld.conf"
MESSAGE="Hamlib rigctld Configuration"

PAT_VERSION="$(pat version | cut -d' ' -f2)"
[[ $PAT_VERSION =~ v0.1[01]. ]] && PAT_CONFIG="$HOME/.wl2k/config.json" || PAT_CONFIG="$HOME/.config/pat/config.json"
export PAT_CONFIG=$PAT_CONFIG
export find_cmd='@bash -c "runFind "%1""'
export view_remove_cmd='bash -c "viewDeleteAliases"'
export fpipe=$(mktemp -u --tmpdir find.XXXXXXXX)
mkfifo "$fpipe"
DEFAULT_SEARCH_STRING="$(jq -r .locator $PAT_CONFIG)"
fkey=$(($RANDOM * $$))
YAD_PIDs=()

exec 4<> $fpipe

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
for A in yad rigctld
do 
	command -v $A >/dev/null 2>&1 || Die "$A is required but not installed."
done

RESTART_RIGCTLD=FALSE

#============================
#  MAIN SCRIPT
#============================

trap SafeExit INT TERM EXIT

while true
do
	# Kill any running processes and load latest settings
   for P in ${YAD_PIDs[@]}
	do
		ps x | egrep -q "^$P" && kill $P
	done
	loadSettings
	YAD_PIDs=()
	if [[ $RESTART_RIGCTLD == TRUE ]]
	then # Restart requested 
		RIG="${F[_RIG_]}"
		[[ $RIG =~ ^[0-9] ]] || Die "Invalid Rig: ${F[_RIG_]}"
		[[ ${F[_PORT_]} =~ ^Not ]] && PORT="" || PORT="-r /dev/serial/by-id/${F[_PORT_]}"
		[[ ${F[_SPEED_]} =~ ^Not ]] && SPEED="" || SPEED="-s ${F[_SPEED_]}"
		COM="$(command -v rigctld) -m ${RIG%%|*} $PORT $SPEED"
		$(command -v rigctld) -m ${RIG%%|*} $PORT $SPEED 2>$TMPDIR/rigctld_error.txt &
   	rigctld_PID=$!
		if ! pgrep rigctld >/dev/null && [[ -s $TMPDIR/rigctld_error.txt ]]
		then
			yad --center --title="Hamlib rigctld ERROR" --text-align=center --borders=30 --width=600 --text-wrap \
				--text="<big><b>$COM\n<span color='red'>failed!</span></b>\nError message:</big>\n" --buttons-layout=center \
				--text-info <$TMPDIR/rigctld_error.txt \
				--button=Close:0 >/dev/null
		fi
		rm -f $TMPDIR/rigctld_error.txt
		RESTART_RIGCTLD=FALSE
	fi
	if pgrep rigctld >/dev/null
	then # rigctld already running
		# Determine rig ID of running rigctld process
		ID="$(cat /proc/$(pidof rigctld)/cmdline | tr -d '\0' | tr '-' '\n' | egrep "^m[0-9]{1,4}" | sed -e 's/^m//')"
		case $ID in
			1|2|4) # Hamlib and FLRig "rigs" don't use a serial port
				PORTSPEED_MSG=""
				;;
	 		*) # All(?) of the others require a serial port
				PORT="$(cat /proc/$(pidof rigctld)/cmdline | tr '\0' '~' | sed -e 's/~-/\n-/g' | tr '~' ' ' | grep "^-r" | cut -d' ' -f2)"
				[[ $PORT == "" ]] && PORT="PORT NOT CONFIGURED"
				SPEED="$(cat /proc/$(pidof rigctld)/cmdline | tr '\0' '~' | sed -e 's/~-/\n-/g' | tr '~' ' ' | grep "^-s" | cut -d' ' -f2)"
				[[ $SPEED == "" ]] && SPEED="SPEED NOT CONFIGURED"
				PORTSPEED_MSG="on ${PORT##*/} @ $SPEED"
				;;
		esac
		# Find the rig make and model from that ID
		RIG="$(getRig $ID)"
		STATE="<b><span color='green'><big>rigctld is RUNNING for $RIG</big>\n$PORTSPEED_MSG</span></b> \n \
<b>Change the rig by searching/selecting a different rig below, or click 'Save...' to restart rigctld with $RIG</b>"
	else # rigctld not running
		RIG="$(echo ${F[_RIG_]} | cut -d'|' -f2,3 | tr '|' ' ')"
		STATE="<big><b><span color='red'>rigctld is NOT RUNNING</span></b></big>\n<b>Configured rig is <span color='blue'>$RIG.</span> Change the rig by searching/selecting a different rig below, or click 'Save...' to start rigctld with $RIG</b>"
	fi
	yad --plug="$fkey" --tabnum=1 --text-align=center \
	   --text="<big><b>Configure Hamlib Rig Control (rigctld)</b></big>\n$STATE\n \
<span color='red'><b>Not all rigs are supported by Hamlib!</b></span> Search for your rig using regex (case insensitive).\n \
Example: Find all Kenwood rigs with model numbers staring with 'TM': <b>kenwood.*TM</b>\n \
Hamlib and FLRig models don't use the Serial Port or Speed settings.  Set them to 'Not Applicable' for those models." \
	 	--form \
  	 	--align=right \
		--columns=2 \
  	 	--item-separator="|" \
	 	--field="<b>Rig search string</b>" "" \
 	--field="gtk-find":FBTN "$find_cmd" \
	 	--field="<b>Serial Port</b>":CB "$(getSerialPorts "${F[_PORT_]}")" \
	 	--field="<b>Speed</b>":CB "$(getSpeeds "${F[_SPEED_]}")" >$TMPDIR/RIG_PARAMS.txt &
	YAD_PIDs+=( $! )

	yad --plug="$fkey" --tabnum=2 --list --grid-lines=hor \
		--text-align=left \
		--text "Rig search results. <span color='blue'><b>Select new rig from the list below, select Serial Port and Speed above, then click 'Save...' below to restart rigctld.</b></span>" \
		--radiolist --column="Pick" --column="ID" --column="Make" --column="Model" \
		--expand-column=4 <&4 >$TMPDIR/RIG_SELECTION.txt &
	YAD_PIDs+=( $! )

	yad --paned --key="$fkey" --buttons-layout=center --width=500 --height=700 \
  		--borders=20 \
		--posx=30 --posy=70 \
		--title="$TITLE" --window-icon="system-search" \
		--button="<b>Leave rigctld as-is &#x26; Exit</b>":3 \
		--button="<b>Stop rigctld &#x26; Exit</b>":2 \
		--button="<b>Stop rigctld</b>":1 \
		--button="<b>Save Changes &#x26; [Re]start rigctld</b>":0
	RETURN_CODE=$?	
	
	case $RETURN_CODE in
		0) # Read and handle the Configure TNC tab yad output
			[[ -s $TMPDIR/RIG_PARAMS.txt ]] || Die "Unexpected input from dialog via $TMPDIR/RIG_PARAMS.txt"
			IFS='|' read -r -a PARAMS < "$TMPDIR/RIG_PARAMS.txt"
			F[_PORT_]="${PARAMS[2]}"
			F[_SPEED_]="${PARAMS[3]}"
			PARAMS=()
			if [[ -s $TMPDIR/RIG_SELECTION.txt ]]
			then
				IFS='|' read -r -a PARAMS < "$TMPDIR/RIG_SELECTION.txt"
				F[_RIG_]="${PARAMS[1]}|${PARAMS[2]}|${PARAMS[3]}"
			fi
			RIG="${F[_RIG_]}"
			case ${RIG%%|*} in
				1|2|4) # Hamlib and FLRig "rigs" don't use a serial port
					F[_PORT_]="Not Applicable"
					F[_SPEED_]="Not Applicable"
					;;
		 		*) # All(?) of the others require a serial port
					;;
			esac

			# Update the yad configuration file.
			echo "declare -gA F" > "$CONFIG_FILE"
			for J in "${!F[@]}"
			do
   			echo "F[$J]='${F[$J]}'" >> "$CONFIG_FILE"
			done
			pkill -x rigctld
			RESTART_RIGCTLD=TRUE
			;;
		1) # Stop rigctld
			pkill -x rigctld
			;;
		2) # Stop rigctld and exit
			pkill -x rigctld
			break
			;;
		*) # Leave rigctld as-is and exit 
			break
			;;
	esac
done
SafeExit
