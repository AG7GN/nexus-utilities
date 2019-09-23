#!/bin/bash
#
# Script Name:		tnc.sh
# Author:			Steve Magnuson AG7GN
# Date Created:	20180601
#
# Description:		This script will start direwolf in one of 3 APRS modes: igate, digipeater,
#						or igate + digipeater, OR in AX.25 mode as a TNC for Winlink or other apps.  
#                 Run tnc.sh with no arguments for instructions.
#
# Usage:				tnc.sh start digi|igate|digiigate|ax25
#						tnc.sh stop
#
#						Use the companion script watchdog-tnc.sh in crontab to launch this script
#						to keep it running.
#						
#===========================================================================================
VERSION="3.1.2"

# BEGINNING OF USER CONFIGURATION SECTION ########################################################

TNC_CONFIG_FILE="$HOME/tnc.conf"

if [ -s "$TNC_CONFIG_FILE" ]
then
	source $HOME/tnc.conf
	if [[ $MYCALL =~ N0CALL || $MYCALL =~ N0ONE ]]
	then
	   echo >&2 "Error: You must set the MYCALL variable in $TNC_CONFIG_FILE."
   	exit 1
	fi	
else
   echo >&2 "Error: Configuration file $TNC_CONFIG_FILE is missing or empty."
   exit 1
fi

# END OF USER CONFIGURATION SECTION ########################################################

# Initializations ##########################################################################

# trap ctrl-c and call ctrl_c()
trap ctrl_c INT

LOGFILE="/tmp/tnc.log"
SCREENCONFIG="/tmp/tnc.sh.screenrc"
ACTION="${1,,}" # start|stop
DMODE="${2,,}" # direwolf mode: digi,igate,digi+igate,ax25
SPEED="${3,,}" # speed.  No value implies 1200. Otherwise, allowed values are 300 or 9600.
AUDIO_CHANNELS="$4"
[[ $SPEED == "" ]] && SPEED="1200"
[[ $AUDIO_CHANNELS == "" ]] && AUDIO_CHANNELS="1"
declare -a ORDERS
declare -A CMDS
CMDS[direwolf]="$(which direwolf) -a $AUDIOSTATS -t $COLORS -r $ARATE"
cat > $SCREENCONFIG << EOF
logfile $LOGFILE
logfile flush 1
logtstamp on
logtstamp after 60
log on
logtstamp string "[ %n:%t ] ---- TIMESTAMP ---- %Y-%m-%d %c:%s ---- Press Ctrl-C to Quit\012"
EOF

# Functions ################################################################################

function ctrl_c () {
	# Do cleanup if Ctrl-C is pressed.  Stop all the screens.
	$0 stop
	exit 0
}

function Usage() {
  	echo 
	echo "Version $VERSION"
	echo
  	echo "$(basename $0) usage:"
  	echo 
	echo "$(basename $0) start ax25|ax25+pat [1200|9600 [2]]"
	echo "                     Starts the ax25 TNC or the ax25 TNC and pat email client." 
	echo "                     Note that pat requires configuration in"
	echo "                     $HOME/.wl2k/config.json."
	echo
	echo "                     Direwolf baud set to 1200 bps (for V/UHF) on a single"
	echo "                     audio channel by default."  
	echo "                     You can optionally specify baud (1200 or 9600) and number"
	echo "                     of audio channels.  9600 might work on V/UHF"
   echo "                     with another 9600 station depending on conditions and"
   echo "                     the capabilities of your soundcard.  9600 will likely"
   echo "                     not work with a Signalink."
	echo "                     If you specify the baud, you can optionally also specify"
   echo "                     2 to tell Direwolf to use both channels.  '2' assumes"
	echo "                     you have a stereo audio card and direwolf uses both the left"
	echo "                     and right channels.  Winlink clients can access Direwolf's"
   echo "                     second channel by selecting Packet TNC Type 'KISS Port 2'"
	echo "                     in Winlink.  Default is a single channel."
	echo "                     1200 baud uses Direwolf's AFSK 1200 & 2200 Hz modem."
	echo "                     9600 baud uses Direwolf's K9NG/G3RUH modem."
  	echo 
  	echo "$(basename $0) start pat"
	echo "                     Starts pat email client in telnet mode only (niether ax25"
   echo "                     not ARDOP TNC is started)."	
	echo "                     Note that pat requires configuration in"
	echo "                     $HOME/.wl2k/config.json."
   echo 
  	echo "$(basename $0) start ardop|ardop+pat"
	echo "                     Starts the ARDOP TNC (piardop2) or the ARDFOP TNC and pat." 
	echo "                     Note that pat requires configuration in"
	echo "                     $HOME/.wl2k/config.json."
   echo 
   echo "$(basename $0) start digiigate [both]"
   echo "                     Starts the Direwolf APRS digipeater and iGate." 
	echo "                     If you specify 'both', Direwolf will decode audio on" 
	echo "                     channel 1 (stereo left) and channel 2 (stereo right)"
	echo "                     on stereo sound cards only."
   echo	
   echo "$(basename $0) start digi [both]"
	echo "                     Starts the Direwolf APRS digipeater (only)." 
	echo "                     If you specify 'both', Direwolf will decode audio on" 
	echo "                     channel 1 (stereo left) and channel 2 (stereo right)"
	echo "                     on stereo sound cards only."
   echo 
   echo "$(basename $0) start igate [both]"
	echo "                     Starts the Direwolf APRS iGate (only)." 
	echo "                     If you specify 'both', Direwolf will decode audio on" 
	echo "                     channel 1 (stereo left) and channel 2 (stereo right)"
	echo "                     on stereo sound cards only."
   echo 
   echo "$(basename $0) stop"
   echo "                     Stops all the apps."
   echo
   exit 1
}

function checkApp () {
	APP="$(which $1)"	
	if [[ $APP == "" ]]
	then
   	echo >&2 "Error: $1 is required but not installed."
		exit 1
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
		echo >&2 "Error: You must set either the AUDIO_DEV or AUDIO_DEV_SEARCH_STRING variables in this script to select the sound card."
		exit 1
	else
		CAP_DEV="$($ARECORD -l | grep -i "$AUDIO_DEV_SEARCH_STRING" | grep "card [0-9]\|device [0-9]" | sed 's/:.*,/,/;s/:.*$//;s/, /,/;s/ /=/g;s/ice//' | tr -s [:lower:] [:upper:])"
		if [[ $CAP_DEV == "" ]]
		then
			echo >&2 "Error: Unable to find audio interface using string $AUDIO_DEV_SEARCH_STRING."
			sleep 5
			exit 1
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
					echo >&2 "Error: Valid baud settings are 1200 or 9600."
					exit 1
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
			echo >&2 "Error: Could not locate serial device with name containing \"$DEVSTRING\"."
			exit 1
		fi
		DEVICE="/dev/$SERIAL_PORT"
		if [[ $RIGCTL_RADIO != "" ]]
		then
			CMDS[rigctld]="$(which rigctld) -m $RIGCTL_RADIO -r $DEVICE -s $RIGCTL_SPEED"
		else
			CMDS[rigctld]=""
		fi
	fi 
}

# Main #############################################################################################

SCREEN="$(checkApp screen)"
ARECORD="$(checkApp arecord)"
WGET="$(checkApp wget)"
case "$ACTION" in
	start)
		checkSoundCard
		echo "" > $LOGFILE
		echo
		echo "Version $VERSION"
		echo "Running $0 $ACTION $DMODE $SPEED $AUDIO_CHANNELS"
		echo "Mode: $DMODE   Speed: $SPEED   Audio Device: $CAP_DEV   Audio Channels: $AUDIO_CHANNELS"
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
				CMDS[pat]="$(which pat) -l telnet http"
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
						$(which pat) rmslist | grep "${GRID}\|callsign" | sort -k 3,3 -n
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
					CMDS[pat]="$(which pat) -l ax25,telnet http"
				fi
      		# Check that the app is installed.
      		for i in ${!ORDERS[@]}
      		do
         		which ${ORDERS[$i]} >/dev/null
         		[ $? -eq 0 ] && echo "${ORDERS[$i]} found." || { echo >&2 "${ORDERS[$i]} required but not found.  Aborting."; exit 1; }
         		# Kill existing session if it exists
         		SCR="$($SCREEN -list | grep ${ORDERS[$i]} | tr -d ' \t' | cut -d'(' -f1 | tr -d '\n')"
         		[[ "$SCR" != "" ]] && { pkill piardop2; $SCREEN -S $SCR -X quit; }
      		done
      		## Kill existing session if it exists
      		sudo killall kissattach 2>/dev/null 
				## Are the apps installed?
      		for i in kissattach kissparms
      		do
         		which $i >/dev/null
         		[ $? -eq 0 ] && echo "$i found." || { echo >&2 "Error: $i required but not found.  Aborting."; exit 1; }
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
								echo >&2 "Direwolf failed to allocate a PTY! Aborting."
								echo >&2 "Is ADEVICE set to your sound card?"
								ctrl_c
								exit 1
							fi
               		echo "Direwolf started."
               		sudo $(which kissattach) $(readlink -f /tmp/kisstnc) $AX25PORT
               		[ $? -eq 0 ] || { echo "kissattach failed.  Aborting."; ctrl_c; exit 1; }
							KISSPARMS="-c 1 -p $AX25PORT -t $TXDelay -l $TXTail -s $Slottime -r $Persist -f n"
							echo "Setting $(which kissparms) $KISSPARMS"
							sleep 2
               		sudo $(which kissparms) $KISSPARMS
               		[ $? -eq 0 ] || { echo "kissparms settings failed.  Aborting."; ctrl_c; exit 1; }
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
						$(which pat) rmslist | grep "${GRID}\|callsign" | sort -k 3,3 -n
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
         		which ${ORDERS[$i]} >/dev/null
         		[ $? -eq 0 ] && echo "${ORDERS[$i]} found." || { echo >&2 "${ORDERS[$i]} required but not found.  Aborting."; exit 1; }
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
						CMDS[pat]="$(which pat) -l ardop,telnet http"
						;;
					*)
						ORDERS=( piardop2 )
						;;
				esac
     			# Check that the app is installed, and kill it if it is already running.
	     		for i in ${!ORDERS[@]}
   	  		do
		     		which ${ORDERS[$i]} >/dev/null
    				[ $? -eq 0 ] && echo "${ORDERS[$i]} found." || { echo >&2 "${ORDERS[$i]} required but not found.  Aborting."; exit 1; }
   				# Kill existing session if it exists
  					SCR="$($SCREEN -list | grep ${ORDERS[$i]} | tr -d ' \t' | cut -d'(' -f1 | tr -d '\n')"
 					[[ "$SCR" != "" ]] && $SCREEN -S $SCR -X quit
				done
				CMDS[piardop2]="$(which piardop2) $ARDOP_PORT $ARDOP_DEV"
				if [[ $ARDOP_PTT == "" ]]
				then
					echo >&2 "Error: Please set PTT type (variable ARDOP_PTT) for ARDOP in this script."
					exit 1
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
				Usage
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
		rm -f /tmp/tnc*
     	;;
   *)
		Usage
     	;;
esac

