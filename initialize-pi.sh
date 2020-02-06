#!/bin/bash
#================================================================
# HEADER
#================================================================
#% SYNOPSIS
#+   ${SCRIPT_NAME} [-hv]
#%
#% DESCRIPTION
#%   This script generates new VNC server and SSH server and client keys and restores 
#%   certain ham radio application configurations to default values at boot time 
#%   if a file named DO_NOT_DELETE_THIS_FILE file does not exist in the user's 
#%   home directory.  
#%
#%   Run this script whenever the Pi boots by adding a crontab entry, like this:
#%
#%     1) Run crontab -e
#%     2) Add the following line to the end:
#%
#%        @reboot sleep 5 && /usr/local/bin/initialize-pi.sh
#%
#%     3) Save and exit the crontab editor
#%
#% OPTIONS
#%    -h, --help                  Print this help
#%    -v, --version               Print script information
#%
#================================================================
#- IMPLEMENTATION
#-    version         ${SCRIPT_NAME} 1.16.3
#-    author          Steve Magnuson, AG7GN
#-    license         CC-BY-SA Creative Commons License
#-    script_id       0
#-
#================================================================
#  HISTORY
#     20181220 : Steve Magnuson : Script creation
#     20200204 : Steve Magnuson : Added script template
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


DIR="$HOME"
INIT_DONE_FILE="$DIR/DO_NOT_DELETE_THIS_FILE"

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

# Parse options
while getopts ${SCRIPT_OPTS} OPTION ; do
	# Translate long options to short
	if [[ "x$OPTION" == "x-" ]]; then
		LONG_OPTION=$OPTARG
		LONG_OPTARG=$(echo $LONG_OPTION | grep "=" | cut -d'=' -f2)
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

# Does $INIT_DONE_FILE exist?  Is it a regular file? Is it not empty? If YES to all, then 
# exit.
if [ -e "$INIT_DONE_FILE" ] && [ -f "$INIT_DONE_FILE" ] && [ -s "$INIT_DONE_FILE" ]
then
#   [ -s /usr/local/bin/check-piano.sh ] && /usr/local/bin/check-piano.sh
   exit 0
fi

# Got this far?  Initialze this Pi!
echo "$(date): First time boot.  Initializing..." > "$INIT_DONE_FILE"

# Generate a new VNC key
echo "Generate new VNC server key" >> "$INIT_DONE_FILE"
sudo vncserver-x11 -generatekeys force >> "$INIT_DONE_FILE" 2>&1
sudo systemctl restart vncserver-x11-serviced >/dev/null 2>&1

# Generate new SSH server keys
sudo rm -v /etc/ssh/ssh_host* >> "$INIT_DONE_FILE" 2>&1
echo "Generate new SSH server keys" >> "$INIT_DONE_FILE"
#sudo dpkg-reconfigure -f noninteractive openssh-server >> "$INIT_DONE_FILE" 2>&1
cd /etc/ssh
sudo rm -f ssh_host_*
sudo ssh-keygen -A
sudo systemctl restart ssh >/dev/null 2>&1
cd $HOME
echo "Remove ssh client keys, authorized_keys and known_hosts" >> "$INIT_DONE_FILE"
rm -f $DIR/.ssh/known_hosts
rm -f $DIR/.ssh/authorized_keys
rm -f $DIR/.ssh/id_*
rm -f $DIR/.ssh/*~

rm -f $DIR/*~

echo "Remove Fldigi suite logs and messages and personalized data" >> "$INIT_DONE_FILE"
DIRS=".nbems .nbems-left .nbems-right"
for D in $DIRS
do
	rm -f ${DIR}/${D}/*~
	rm -f $DIR/$D/debug*
	rm -f $DIR/$D/flmsg.sernbrs
	rm -f $DIR/$D/ICS/*.html
	rm -f $DIR/$D/ICS/*.csv
	rm -f $DIR/$D/ICS/messages/*
	rm -f $DIR/$D/ICS/templates/*
	rm -f $DIR/$D/ICS/log_files/*
	rm -f $DIR/$D/WRAP/auto/*
	rm -f $DIR/$D/WRAP/recv/*
	rm -f $DIR/$D/WRAP/send/*
	rm -f $DIR/$D/TRANSFERS/*
	rm -f $DIR/$D/FLAMP/*log*
	rm -f $DIR/$D/FLAMP/rx/*
	rm -f $DIR/$D/FLAMP/tx/*
	rm -f $DIR/$D/ARQ/files/*
	rm -f $DIR/$D/ARQ/recv/*
	rm -f $DIR/$D/ARQ/send/*
	rm -f $DIR/$D/ARQ/mail/in/*
	rm -f $DIR/$D/ARQ/mail/out/*
	rm -f $DIR/$D/ARQ/mail/sent/*
	if [ -f $DIR/$D/FLMSG.prefs ]
	then
		sed -i -e 's/^mycall:.*/mycall:N0ONE/' \
				 -e 's/^mytel:.*/mytel:/' \
				 -e 's/^myname:.*/myname:/' \
				 -e 's/^myaddr:.*/myaddr:/' \
				 -e 's/^mycity:.*/mycity:/' \
				 -e 's/^myemail:.*/myemail:/' \
		       -e 's/^sernbr:.*/sernbr:1/' \
				 -e 's/^rgnbr:.*/rgnbr:1/' \
				 -e 's/^rri:.*/rri:1/' \
				 -e 's/^sernbr_fname:.*/sernbr_fname:1/' \
				 -e 's/^rgnbr_fname:.*/rgnbr_fname:1/' $DIR/$D/FLMSG.prefs
	fi
done

DIRS=".fldigi .fldigi-left .fldigi-right"
for D in $DIRS
do
   for F in $(ls -R $DIR/$D/*log* 2>/dev/null)
	do
		[ -e $F ] && [ -f $F ] && rm -f $F
	done
	rm -f $DIR/$D/*~
	rm -f $DIR/$D/debug/*txt*
	rm -f $DIR/$D/logs/*
	rm -f $DIR/$D/LOTW/*
	rm -f $DIR/$D/rigs/*
	rm -f $DIR/$D/temp/*
	rm -f $DIR/$D/kml/*
	rm -f $DIR/$D/wrap/*
	if [ -f $DIR/$D/fldigi_def.xml ]
	then
		sed -i -e 's/<MYCALL>.*<\/MYCALL>/<MYCALL>N0ONE<\/MYCALL>/' \
		       -e 's/<MYQTH>.*<\/MYQTH>/<MYQTH><\/MYQTH>/' \
		       -e 's/<MYNAME>.*<\/MYNAME>/<MYNAME><\/MYNAME>/' \
		       -e 's/<MYLOC>.*<\/MYLOC>/<MYLOC><\/MYLOC>/' \
		       -e 's/<MYANTENNA>.*<\/MYANTENNA>/<MYANTENNA><\/MYANTENNA>/' \
		       -e 's/<OPERCALL>.*<\/OPERCALL>/<OPERCALL><\/OPERCALL>/' \
		       -e 's/<PORTINDEVICE>.*<\/PORTINDEVICE>/<PORTINDEVICE><\/PORTINDEVICE>/' \
		       -e 's/<PORTININDEX>.*<\/PORTININDEX>/<PORTININDEX>-1<\/PORTININDEX>/' \
		       -e 's/<PORTOUTDEVICE>.*<\/PORTOUTDEVICE>/<PORTOUTDEVICE><\/PORTOUTDEVICE>/' \
		       -e 's/<PORTOUTINDEX>.*<\/PORTOUTINDEX>/<PORTOUTINDEX>-1<\/PORTOUTINDEX>/' $DIR/$D/fldigi_def.xml
	fi
done

DIRS=".flrig .flrig-left .flrig-right"
for D in $DIRS
do
	if [ -f $DIR/$D/flrig.prefs ]
	then
		sed -i 's/^xcvr_name:.*/xcvr_name:NONE/' $DIR/$D/flrig.prefs 2>/dev/null
		mv $DIR/$D/flrig.prefs $DIR/$D/flrig.prefs.temp
		rm -f $DIR/$D/*.prefs
		mv $DIR/$D/flrig.prefs.temp $DIR/$D/flrig.prefs
	fi
	rm -f $DIR/$D/debug*
	rm -f ${DIR}/${D}/*~
done

echo "Restore defaults for tnc-*.conf files" >> "$INIT_DONE_FILE"
sed -i 's/^MYCALL=.*/MYCALL=\"N0ONE-10\"/' $(ls $DIR/tnc-*.conf)

# Restore defaults for rmsgw

echo "Restore defaults for RMS Gateway" >> "$INIT_DONE_FILE"
( systemctl list-units | grep -q "ax25.*loaded" ) && sudo systemctl disable ax25
[ -L /etc/ax25/ax25-up ] && sudo rm -f /etc/ax25/ax25-up
[ -f /etc/rmsgw/channels.xml ] && sudo rm -f /etc/rmsgw/channels.xml
[ -f /etc/rmsgw/banner ] && sudo rm -f /etc/rmsgw/banner
[ -f /etc/rmsgw/gateway.conf ] && sudo rm -f /etc/rmsgw/gateway.conf
[ -f /etc/rmsgw/sysop.xml ] && sudo rm -f /etc/rmsgw/sysop.xml
[ -f /etc/ax25/ax25d.conf ] && sudo rm -f /etc/ax25/ax25d.conf
[ -f /etc/ax25/ax25-up.new ] && sudo rm -f /etc/ax25/ax25-up.new
[ -f /etc/ax25/ax25-up.new2 ] && sudo rm -f /etc/ax25/ax25-up.new2
[ -f /etc/ax25/direwolf.conf ] && sudo rm -f /etc/ax25/direwolf.conf
[ -f $HOME/rmsgw.conf ] && rm -f $HOME/rmsgw.conf
id -u rmsgw >/dev/null 2>&1 && sudo crontab -u rmsgw -r 2>/dev/null

#rm -rf $DIR/.flrig/
#rm -rf $DIR/.fldigi/
#rm -rf $DIR/.fltk/

# Remove Auto Hot-Spot if configured
echo "Remove Auto-HotSpot" >> "$INIT_DONE_FILE"
rm -f $HOME/autohotspot.conf
sudo sed -i 's|^net.ipv4.ip_forward=1|#net.ipv4.ip_forward=1|' /etc/sysctl.conf
if systemctl | grep -q "autohotspot"
then
   sudo systemctl disable autohotspot
fi
if [ -s /etc/dhcpcd.conf ]
then
	TFILE="$(mktemp)"
	grep -v "^nohook wpa_supplicant" /etc/dhcpcd.conf > $TFILE
	sudo mv -f $TFILE /etc/dhcpcd.conf
fi
# Remove cronjob if present
crontab -u $USER -l | grep -v "autohotspotN" | crontab -u $USER -

# Set radio names to default
rm -f $HOME/radionames.conf
D="/usr/local/share/applications"
for F in `ls $D/*-left.template 2>/dev/null` `ls $D/*-right.template 2>/dev/null`
do
   sudo sed -e "s/_LEFT_RADIO_/Left Radio/" -e "s/_RIGHT_RADIO_/Right Radio/g" $F > ${F%.*}.desktop
done

# Expand the filesystem if it is < 8 GB 
echo "Expand filesystem if needed" >> "$INIT_DONE_FILE"
PARTSIZE=$( df | sed -n '/root/{s/  */ /gp}' | cut -d ' ' -f2 )
THRESHOLD=$((8 * 1024 * 1024))
(( $PARTSIZE < $THRESHOLD )) && sudo raspi-config --expand-rootfs >> "$INIT_DONE_FILE"

echo "Raspberry Pi initialization complete" >> "$INIT_DONE_FILE"
sudo shutdown -r now


