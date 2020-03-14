#!/bin/bash
#================================================================
# HEADER
#================================================================
#% SYNOPSIS
#+   ${SCRIPT_NAME} [-hv] 
#+   ${SCRIPT_NAME} [-c FILE] start COMMAND [COMMAND ...]
#+   ${SCRIPT_NAME} stop
#%
#% DESCRIPTION
#%   This script will start direwolf in one of 3 APRS modes: igate, digipeater,
#%   or igate + digipeater, OR in AX.25 mode as a TNC for Winlink or other apps.
#%   Use the companion script watchdog-tnc.sh in crontab to launch this script
#%   and keep it running.  
#%
#% OPTIONS
#%    -c FILE, --config=FILE
#%                                Override using the default configuration file. 
#%                                Default configuration file is $HOME/tnc.conf
#%                                
#%    -h, --help                  Print this help
#%    -v, --version               Print script information
#%
#% COMMANDS
#%  ${SCRIPT_NAME} [-c FILE] start ax25|ax25+pat [1200|9600 [2]]
#%                                Starts the ax25 TNC or the ax25 TNC and pat email 
#%                                client." 
#%                                Note that pat requires configuration in
#%                                $HOME/.wl2k/config.json.
#%                                
#%                                Direwolf baud set to 1200 bps (for V/UHF) on a single
#%                                audio channel by default. 
#%                                You can optionally specify baud (1200 or 9600) and 
#%                                number of audio channels.  9600 might work on V/UHF
#%                                with another 9600 station depending on conditions and
#%                                the capabilities of your soundcard.  9600 will likely
#%                                not work with a Signalink.
#%                                If you specify the baud, you can optionally also 
#%                                specify '2' to tell Direwolf to use both channels.  
#%                                '2' assumes" you have a stereo audio card *and* direwolf 
#%                                is configured to use both channels of the stereo sound 
#%                                card.
#%                                Winlink clients can access Direwolf's second channel by     
#%                                selecting Packet TNC Type 'KISS Port 2' in Winlink.
#%                                Default is a single channel.
#%                                1200 baud uses Direwolf's AFSK 1200 & 2200 Hz modem.
#%                                9600 baud uses Direwolf's K9NG/G3RUH modem.
#%                                
#%  ${SCRIPT_NAME} [-c FILE] start pat
#%                                Starts pat email client in telnet mode only (niether 
#%                                ax25 nor ARDOP TNC is started).	
#%                                Note that pat requires configuration in
#%                                $HOME/.wl2k/config.json.
#%
#%  ${SCRIPT_NAME} [-c FILE] start ardop|ardop+pat
#%                                Starts the ARDOP TNC (piardop2) or the ARDOP TNC and 
#%                                pat.  Note that pat requires configuration in
#%                                $HOME/.wl2k/config.json.
#%
#%  ${SCRIPT_NAME} [-c FILE] start digiigate [both]
#%                                Starts the Direwolf APRS digipeater and iGate. 
#%                                If you specify 'both', Direwolf will decode audio on 
#%                                channel 1 (stereo left) and channel 2 (stereo right)
#%                                on stereo sound cards only.
#%                                
#%  ${SCRIPT_NAME} [-c FILE] start digi [both]
#%                                Starts the Direwolf APRS digipeater (only). 
#%                                If you specify 'both', Direwolf will decode audio on 
#%                                channel 1 (stereo left) and channel 2 (stereo right)
#%                                on stereo sound cards only.
#%                                
#%  ${SCRIPT_NAME} [-c FILE] start igate [both]
#%                                Starts the Direwolf APRS iGate (only). 
#%                                If you specify 'both', Direwolf will decode audio on
#%                                channel 1 (stereo left) and channel 2 (stereo right)
#%                                on stereo sound cards only.
#%                                
#%  ${SCRIPT_NAME} stop
#%                                Stops all the apps.  Same as pressing Ctrl-C.
#%
#% EXAMPLES
#%    
#%  Locate serial port file name containing ${DEFAULT_PORTSTRING} (default search string),
#%  then set APO to 30 minutes:
#%
#%     ${SCRIPT_NAME} set apo 30
#%
#%  Override the default search string ${DEFAULT_PORTSTRING} to locate serial port
#%  connected to radio, then get radio information:
#%
#%     ${SCRIPT_NAME} -s Prolific_Technology get info
#%
#%  Specify the serial port used to connect to your radio then set radio TX timeout 
#%  to 3 minutes:
#%
#%     ${SCRIPT_NAME} -p /dev/ttyUSB0 set timeout 3
#%
#================================================================
#- IMPLEMENTATION
#-    version         ${SCRIPT_NAME} 3.3.7
#-    author          Steve Magnuson, AG7GN
#-    license         CC-BY-SA Creative Commons License
#-    script_id       0
#-
#================================================================
#  HISTORY
#     20180125 : Steve Magnuson : Script creation
#     20200203 : Steve Magnuson : New script template
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

#============================
#  FUNCTIONS
#============================

function TrapCleanup () {
	${SCRIPT_NAME} stop
	exit 0
}

function SafeExit () {
 	rm -f /tmp/tnc*
	rm -f $CONFFILE
	exit
}

function ScriptInfo () { 
	HEAD_FILTER="^#-"
	[[ "$1" = "usage" ]] && HEAD_FILTER="^#+"
	[[ "$1" = "full" ]] && HEAD_FILTER="^#[%+]"
	[[ "$1" = "version" ]] && HEAD_FILTER="^#-"
	head -${SCRIPT_HEADSIZE:-99} ${0} | grep -e "${HEAD_FILTER}" | \
	sed -e "s/${HEAD_FILTER}//g" \
	    -e "s/\${SCRIPT_NAME}/${SCRIPT_NAME}/g"
}

function Usage () { 
	printf "Usage:\n"
	ScriptInfo usage
	exit 0
}

function Die () {
	echo "${*}"
	exit 1
}

#---------------------------------------

function checkApp () {
	APP="$(command -v $1 2>/dev/null)"	
	if [[ $APP == "" ]]
	then
   	Die "Error: $1 is required but not installed."
	fi
	echo "$APP"
}

function aprsPasscode () {
	# Generates the APRS website passcode from the supplied callsign
	CALL="$(echo ${1^^} | cut -d'-' -f1)"
	H="0x73e2"
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

function checkSoundCard () {
	# Checks for the presence of the requested sound card
	if [[ $AUDIO_DEV != "" ]]
	then
		CAP_DEV="$AUDIO_DEV"	
	elif [[ $AUDIO_DEV_SEARCH_STRING == "" ]]
	then
		Die "Error: You must set either the AUDIO_DEV or AUDIO_DEV_SEARCH_STRING variables in this script to select the sound card."
	else
		CAP_DEV="$($ARECORD -l | grep -i "$AUDIO_DEV_SEARCH_STRING" | grep "card [0-9]\|device [0-9]" | sed 's/:.*,/,/;s/:.*$//;s/, /,/;s/ /=/g;s/ice//' | tr -s [:lower:] [:upper:])"
		if [[ $CAP_DEV == "" ]]
		then
			Die "Error: Unable to find audio interface using string $AUDIO_DEV_SEARCH_STRING."
		fi
		CAP_DEV="plughw:$CAP_DEV"
	fi
}

function makeConfig() {
	# direwolf.conf parameters
	ADEVICE="$CAP_DEV"
	CONFFILE="$(mktemp)"
	case "$1" in
 		digi*|igate)
			PASSCODE="$(aprsPasscode $MYCALL)"
				case "$SPEED" in
					both) # Decode stereo right (channel 1) and stereo left (channel 0)
						FROM_CHANNEL="1"
						TO_CHANNEL="0"
						cat >> $CONFFILE << EOF
ADEVICE $ADEVICE
ACHANNELS 2
CHANNEL 0
$PTT0
MYCALL $MYCALL
MODEM 1200
CHANNEL 1
$PTT1
MYCALL $MYCALL
MODEM 1200
EOF
						;;
					*) # Decode stereo left only
						FROM_CHANNEL="0"
						TO_CHANNEL="0"
						cat >> $CONFFILE << EOF
ADEVICE $ADEVICE
ACHANNELS 1
CHANNEL 0
$PTT0
MYCALL $MYCALL
MODEM 1200
EOF
							;;
				esac
			case "$1" in
				digi*) # digipeater+igate or digipeater
					if [[ $1 == "digi" ]] # digipeat ONLY
					then
						IGLOGIN=""
						PBEACONIG=""
						IGTXVIA=""
						COMMENT="$COMMENTCALL Digipeater | $LOC"
					else # Digipeater + iGate
						# IGTXVIA is set at the top of the script
						COMMENT="$COMMENTCALL Digipeater+iGate | $LOC"
						PBEACONIG="PBEACON sendto=IG delay=$IGDELAY every=$IGEVERY symbol=\"igate\" overlay=T lat=$LAT long=$LONG COMMENT=\"$COMMENT\""
						IGLOGIN="IGLOGIN $MYCALL $PASSCODE"
					fi
					DIGIPEAT="DIGIPEAT $FROM_CHANNEL $TO_CHANNEL ^WIDE[3-7]-[1-7]$|^TEST$ ^WIDE[12]-[12]$ TRACE"
					PBEACON="PBEACON delay=$DIGIPEATDELAY every=$DIGIPEATEVERY symbol=\"digi\" overlay=S lat=$LAT long=$LONG POWER=$POWER HEIGHT=$HEIGHT GAIN=$GAIN COMMENT=\"$COMMENT\" via=$HOPS"
					;;
				*) # iGate
					PBEACON=""
					DIGIPEAT=""
					IGTXVIA=""
					COMMENT="$COMMENTCALL iGate | $LOC"
					PBEACONIG="PBEACON sendto=IG delay=$IGDELAY every=$IGEVERY symbol=\"igate\" overlay=R lat=$LAT long=$LONG COMMENT=\"$COMMENT\""
					IGLOGIN="IGLOGIN $MYCALL $PASSCODE"
					;;
			esac
			cat >> $CONFFILE << EOF
$AGWPORT
$KISSPORT
$PBEACONIG
$PBEACON
$DIGIPEAT
$IGTXVIA
$IGLOGIN
$FILTER
$IGSERVER
$IGTXLIMIT
$IGFILTER
EOF
			;;
		ax25)
			case "$SPEED" in
				1200|9600)
					case "$AUDIO_CHANNELS" in
						2) # Assumes stereo input - use both channels
							if [[ $PTT0 =~ "GPIO" ]]
							then # Allow only one radio at a time to transmit
								TXINH0="TXINH $(echo $PTT1 | sed 's/PTT //')"
								TXINH1="TXINH $(echo $PTT0 | sed 's/PTT //')"
							else
								TXINH0=""
								TXINH1=""
							fi
							cat > $CONFFILE << EOF
ADEVICE $ADEVICE
ACHANNELS 2
CHANNEL 0
MODEM $SPEED
$PTT0
$TXINH0
MYCALL $MYCALL
CHANNEL 1
MODEM $SPEED
$PTT1
$TXINH1
MYCALL $MYCALL
$AGWPORT
$KISSPORT
EOF
						;;
						*) # Use only left channel
							cat > $CONFFILE << EOF
ADEVICE $ADEVICE
ACHANNELS 1
CHANNEL 0
MODEM $SPEED
$PTT0
MYCALL $MYCALL
$AGWPORT
$KISSPORT
EOF
						;;
					esac
					;;
				*)	
					Die "Error: Valid baud settings are 1200 or 9600."
					;;
				esac
			;;
		ardop)
			CONFFILE=""
			;;
		*)
			;;
	esac
	echo "$CONFFILE"
}


function checkSerial () {
	if [[ $DEVSTRING == "" ]]
	then # No rig defined.  Don't use rigctld or ARDOP CAT commands to key radio
		CMDS[rigctld]=""
	else
		SERIAL_PORT="$(find -P /dev/serial/by-id -maxdepth 1 -type l -exec echo -n "{} -> " \; -exec readlink {} \; | \
                		grep "$DEVSTRING" | cut -d' ' -f3 | tr -d './')"
		if [[ $SERIAL_PORT == "" ]] 
		then # rigctl or ardop CAT control requested, but could not find serial port
			Die "Error: Could not locate serial device with name containing \"$DEVSTRING\"."
		fi
		DEVICE="/dev/$SERIAL_PORT"
		if [[ $RIGCTL_RADIO != "" ]]
		then
			CMDS[rigctld]="$(command -v rigctld) -m $RIGCTL_RADIO -r $DEVICE -s $RIGCTL_SPEED"
		else
			CMDS[rigctld]=""
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

TNC_CONFIG_FILE=""
LOGFILE="/tmp/tnc.log"
SCREENCONFIG="/tmp/tnc.sh.screenrc"
cat > $SCREENCONFIG << EOF
logfile $LOGFILE
logfile flush 1
logtstamp on
logtstamp after 60
log on
logtstamp string "[ %n:%t ] ---- TIMESTAMP ---- %Y-%m-%d %c:%s ---- Press Ctrl-C to Quit\012"
EOF
VERSION="$(ScriptInfo version | grep version | tr -s ' ' | cut -d' ' -f 4)" 

#============================
#  PARSE OPTIONS WITH GETOPTS
#============================
  
#== set short options ==#
SCRIPT_OPTS=':hc:v-:'

#== set long options associated with short one ==#
typeset -A ARRAY_OPTS
ARRAY_OPTS=(
	[help]=h
	[version]=v
	[man]=h
	[script]=s
	[timestamp]=t
	[wait]=w
)

# Parse options
while getopts ${SCRIPT_OPTS} OPTION
do
	# Translate long options to short
	if [[ "x$OPTION" == "x-" ]]
	then
		LONG_OPTION=$OPTARG
		LONG_OPTARG=$(echo $LONG_OPTION | grep "=" | cut -d'=' -f2-)
		LONG_OPTIND=-1
		[[ "x$LONG_OPTARG" = "x" ]] && LONG_OPTIND=$OPTIND || LONG_OPTION=$(echo $OPTARG | cut -d'=' -f1)
		[[ $LONG_OPTIND -ne -1 ]] && eval LONG_OPTARG="\$$LONG_OPTIND"
		OPTION=${ARRAY_OPTS[$LONG_OPTION]}
		[[ "x$OPTION" = "x" ]] &&  OPTION="?" OPTARG="-$LONG_OPTION"
		
		if [[ $( echo "${SCRIPT_OPTS}" | grep -c "${OPTION}:" ) -eq 1 ]]
		then
			if [[ "x${LONG_OPTARG}" = "x" ]] || [[ "${LONG_OPTARG}" = -* ]]
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
			TNC_CONFIG_FILE="$OPTARG"
			[[ -s "$TNC_CONFIG_FILE" ]] || Die "Configuration file $TNC_CONFIG_FILE is missing or empty."
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
trap TrapCleanup INT
trap SafeExit TERM EXIT

# Exit on error. Append '||true' when you run the script if you expect an error.
set -o errexit

# Check Syntax if set
$SYNTAX && set -n
# Run in debug mode, if set
$DEBUG && set -x 

# No configuration file supplied, so use the default
[[ $TNC_CONFIG_FILE == "" ]] && TNC_CONFIG_FILE="$HOME/tnc.conf"

source $TNC_CONFIG_FILE
[[ $MYCALL =~ N0CALL || $MYCALL =~ N0ONE  || $MYCALL == "" ]] && Die "You must set the MYCALL variable in $TNC_CONFIG_FILE."

ACTION="${1,,}" # start|stop
DMODE="${2,,}" # direwolf mode: digi,igate,digi+igate,ax25,ax25+pat
SPEED="${3,,}" # speed.  No value implies 1200. Otherwise, allowed values are 300 or 9600.
AUDIO_CHANNELS="${4}"

[[ $SPEED == "" ]] && SPEED="1200"
[[ $AUDIO_CHANNELS == "" ]] && AUDIO_CHANNELS="1"

declare -a ORDERS
declare -A CMDS
CMDS[direwolf]="$(command -v direwolf) -a $AUDIOSTATS -t $COLORS -r $ARATE"

SCREEN="$(checkApp screen)"
ARECORD="$(checkApp arecord)"
WGET="$(checkApp wget)"
case "$ACTION" in
	start)
	   [[ $DMODE == "" ]] && Usage
		checkSoundCard
		echo "" > $LOGFILE
		echo
		echo "Version $VERSION"
		echo
		echo "Running $0 $ACTION $DMODE $SPEED $AUDIO_CHANNELS"
		echo "Using configuration file $TNC_CONFIG_FILE"
		echo "Mode: $DMODE  Speed: $SPEED  Audio Device: $CAP_DEV  Audio Channels: $AUDIO_CHANNELS"
		echo
		case "$DMODE" in
			pat)
				checkSerial
				if [[ ${CMDS[rigctld]} == "" ]]
				then
      			echo "rigctld will not be used."
					ORDERS=( pat )
				else
      			echo "rigctld will use radio found on $DEVICE."
					ORDERS=( rigctld pat )
				fi
				echo "NOTE: If you haven't already done so, you must run 'pat configure' or manually"
				echo "      configure $HOME/.wl2k/config.json to use pat."
				echo
				CMDS[pat]="$(command -v pat) -l telnet http"
      		for i in ${!ORDERS[@]}
      		do
              	$SCREEN -c $SCREENCONFIG -L -d -m -S ${ORDERS[$i]} ${CMDS[${ORDERS[$i]}]}
         		echo "============================"
      		done
      		screen -list
				echo
				sleep 2
				rm -f $CONFFILE
      		if [[ $GRID != "" ]]
				then 
					if $WGET -q --tries=2 --timeout=5 --spider http://google.com
					then	# There is an internet connection, so get local RMS list
						GRID="${GRID:0:4}"
						GRID="${GRID^^}"
						echo
      				echo "RMS Stations in grid square $GRID:"
						$(command -v pat) rmslist | grep "${GRID}\|callsign" | sort -k 3,3 -n
					fi
			 	fi
      		echo
      		echo "Tailing $LOGFILE.  All apps log to this file.  Press Ctrl-C to quit all apps."
      		echo
      		tail -n 150 -F $LOGFILE
      		;;
   		*ax25*)
				checkSerial
				if [[ ${CMDS[rigctld]} == "" ]]
				then
      			echo "rigctld will not be used."
					case "$DMODE" in
						*pat*)
							ORDERS=( direwolf pat )
							;;
						*)
							ORDERS=( direwolf )
							;;
					esac
				else
					case "$DMODE" in
						*pat*)
							ORDERS=( rigctld direwolf pat )
							;;
						*)
							ORDERS=( rigctld direwolf )
							;;
					esac
      			echo "rigctld will use radio found on $DEVICE."
				fi
				if [[ $DMODE =~ "pat" ]] 
				then
					echo "NOTE: If you haven't already done so, you must run 'pat configure' or manually"
					echo "      configure $HOME/.wl2k/config.json to use pat."
					echo
					CMDS[pat]="$(command -v pat) -l ax25,telnet http"
				fi
      		# Check that the app is installed.
      		for i in ${!ORDERS[@]}
      		do
         		command -v ${ORDERS[$i]} >/dev/null
         		[ $? -eq 0 ] && echo "${ORDERS[$i]} found." || Die "${ORDERS[$i]} required but not found.  Aborting."
         		# Kill existing session if it exists
         		SCR="$($SCREEN -list | grep ${ORDERS[$i]} | tr -d ' \t' | cut -d'(' -f1 | tr -d '\n')"
         		[[ "$SCR" != "" ]] && { pkill piardop2; $SCREEN -S $SCR -X quit; }
      		done
      		## Kill existing session if it exists
      		pgrep kissattach >/dev/null && sudo kill $(pgrep kissattach)
				## Are the apps installed?
      		for i in kissattach kissparms
      		do
         		command -v $i >/dev/null
         		[ $? -eq 0 ] && echo "$i found." || Die "Error: $i required but not found.  Aborting."
      		done
			   CONFFILE="$(makeConfig ax25)"	
				CMDS[direwolf]+=" -p -d u -c $CONFFILE"
      		for i in ${!ORDERS[@]}
      		do
         		echo  
         		echo "Starting ${CMDS[${ORDERS[$i]}]}"
         		case "${ORDERS[$i]}" in
            		direwolf)
							if ! grep -q "^$AX25PORT[[:space:]]" $AX25PORTFILE 2>/dev/null
							then
								echo -n "File $AX25PORTFILE empty or does not contain $AX25PORT. Adding..."
						 		echo "$AX25PORT	$MYCALL	0	255	7	Winlink" | sudo tee --append $AX25PORTFILE
								echo "done."
							fi
               		rm -f /tmp/kisstnc
               		$SCREEN -c $SCREENCONFIG -L -d -m -S ${ORDERS[$i]} ${CMDS[${ORDERS[$i]}]}
               		COUNTER=0
               		MAXWAIT=8
               		while [ $COUNTER -lt $MAXWAIT ]
               		do
								# Allocate a PTY to ax25
                  		[ -L /tmp/kisstnc ] && break
                  		sleep 1
                  		let COUNTER=COUNTER+1
               		done
               		if [ $COUNTER -ge $MAXWAIT ]
							then
								Die "Direwolf failed to allocate a PTY! Aborting. Is ADEVICE set to your sound card?"
							fi
               		echo "Direwolf started."
               		sudo $(command -v kissattach) $(readlink -f /tmp/kisstnc) $AX25PORT
               		[ $? -eq 0 ] || Die "kissattach failed.  Aborting."
							KISSPARMS="-c 1 -p $AX25PORT -t $TXDelay -l $TXTail -s $Slottime -r $Persist -f n"
							echo "Setting $(command -v kissparms) $KISSPARMS"
							sleep 2
               		sudo $(command -v kissparms) $KISSPARMS
               		[ $? -eq 0 ] || Die "kissparms settings failed.  Aborting."
               		;;
            		*)
               		$SCREEN -c $SCREENCONFIG -L -d -m -S ${ORDERS[$i]} ${CMDS[${ORDERS[$i]}]}
               		;;
         		esac
         		echo "============================"
      		done
      		screen -list
				echo
				echo "------ ax25 Direwolf configuration file ------"
				cat $CONFFILE | grep -v "^$"
				echo "----------------------------------------------"
				sleep 2
				rm -f $CONFFILE
      		if [[ $DMODE == "pat" && $GRID != "" ]]
				then 
					if $WGET -q --tries=2 --timeout=5 --spider http://google.com
					then	# There is an internet connection, so get local RMS list
						GRID="${GRID:0:4}"
						GRID="${GRID^^}"
						echo
      				echo "RMS Stations in grid square $GRID:"
						$(command -v pat) rmslist | grep "${GRID}\|callsign" | sort -k 3,3 -n
					fi
			 	fi
      		echo
      		echo "Tailing $LOGFILE.  All apps log to this file.  Press Ctrl-C to quit all apps."
      		echo
      		tail -n 150 -F $LOGFILE
      		;;
			digi*|igate)
				[[ $PTT0 == "" || $PTT0 =~ "GPIO" ]] && ORDERS=( direwolf ) || { checkSerial; ORDERS=( rigctld direwolf ); }
      		# Check that the app is installed.
      		for i in ${!ORDERS[@]}
      		do
         		command -v ${ORDERS[$i]} >/dev/null
         		[ $? -eq 0 ] && echo "${ORDERS[$i]} found." || Die "${ORDERS[$i]} required but not found.  Aborting."
         		# Kill existing session if it exists
         		SCR="$($SCREEN -list | grep ${ORDERS[$i]} | tr -d ' \t' | cut -d'(' -f1 | tr -d '\n')"
         		[[ "$SCR" != "" ]] && { pkill piardop2; $SCREEN -S $SCR -X quit; }
         		#[[ "$SCR" != "" ]] && $SCREEN -S $SCR -X quit
      		done
			   CONFFILE="$(makeConfig $DMODE)"	
				CMDS[direwolf]+=" -d t -c $CONFFILE"
      		for i in ${!ORDERS[@]}
      		do
         		echo  
         		echo "Starting ${CMDS[${ORDERS[$i]}]}" 
				   $SCREEN -c $SCREENCONFIG -L -d -m -S ${ORDERS[$i]} ${CMDS[${ORDERS[$i]}]}
				done
				screen -list
				echo
				echo "------ APRS $DMODE Direwolf configuration file ------"
				cat $CONFFILE | grep -v "^$"
				echo "-----------------------------------------------------"
				echo
				sleep 2
				rm -f $CONFFILE
      		echo "Tailing $LOGFILE.  All apps log to this file.  Press Ctrl-C to quit all apps."
      		echo
      		tail -n 150 -F $LOGFILE
				;;
			*ardop*)
				case "$DMODE" in
					*pat*)
						ORDERS=( piardop2 pat )
						echo "NOTE: If you haven't already done so, you must run 'pat configure' or manually"
						echo "      configure $HOME/.wl2k/config.json to use pat."
						echo
						CMDS[pat]="$(command -v pat) -l ardop,telnet http"
						;;
					*)
						ORDERS=( piardop2 )
						;;
				esac
     			# Check that the app is installed, and kill it if it is already running.
	     		for i in ${!ORDERS[@]}
   	  		do
		     		command -v ${ORDERS[$i]} >/dev/null
    				[ $? -eq 0 ] && echo "${ORDERS[$i]} found." || Die "${ORDERS[$i]} required but not found.  Aborting."
   				# Kill existing session if it exists
  					SCR="$($SCREEN -list | grep ${ORDERS[$i]} | tr -d ' \t' | cut -d'(' -f1 | tr -d '\n')"
 					[[ "$SCR" != "" ]] && $SCREEN -S $SCR -X quit
				done
				CMDS[piardop2]="$(command -v piardop2) $ARDOP_PORT $ARDOP_DEV"
				if [[ $ARDOP_PTT == "" ]]
				then
					Die "Error: Please set PTT type (variable ARDOP_PTT) for ARDOP in this script."
				else
					CMDS[piardop2]+=" $ARDOP_PTT"
				fi
      		for i in ${!ORDERS[@]}
      		do
         		echo  
         		echo "Starting ${CMDS[${ORDERS[$i]}]}"
               $SCREEN -c $SCREENCONFIG -L -d -m -S ${ORDERS[$i]} ${CMDS[${ORDERS[$i]}]}
				done
      		echo "Tailing $LOGFILE.  All apps log to this file.  Press Ctrl-C to quit all apps."
      		echo
      		tail -n 150 -F $LOGFILE
				;;
			*)
				Die "Invalid mode requested.  Run ${SCRIPT_NAME} -h for instructions."
				;;
		esac
		;;
   stop)
		ORDERS=( rigctld piardop2 direwolf pat )
		#ORDERS=( rigctld direwolf )
		echo
		for i in ${!ORDERS[@]}
		do
  			SCR="$($SCREEN -list | grep ${ORDERS[$i]} | tr -d ' \t' | cut -d'(' -f1 | tr -d '\n')"
  			if [[ "$SCR" != "" ]]
  			then 
   			echo -n "Stopping $SCR..."
   			$SCREEN -S $SCR -X quit
   			echo "done."
    		else
     			echo "Stopping ${ORDERS[$i]}: ${ORDERS[$i]} not running"
     		fi
		done
  		pgrep piardop2 >/dev/null && kill -9 $(pgrep piardop2)
		KISSATTACHPID="$(pgrep kissattach)"
		if [[ $KISSATTACHPID != "" ]]
		then
  			echo -n "Stopping kissattach..."
  			sudo killall kissattach
  			rm -f /tmp/kisstnc
  			echo "done."
		fi
     	;;
   *)
		Usage
     	;;
esac

