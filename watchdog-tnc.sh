#!/bin/bash

#How are you running Direwolf : within a GUI (Xwindows / VNC) or CLI mode
#
#  AUTO mode is design to try starting direwolf with GUI support and then
#    if no GUI environment is available, it reverts to CLI support with screen
#
#  GUI mode is suited for users with the machine running LXDE/Gnome/KDE or VNC
#    which auto-logs on (sitting at a login prompt won't work)
#
#  CLI mode is suited for say a Raspberry Pi running the Jessie LITE version
#      where it will run from the CLI w/o requiring Xwindows - uses screen

VERSION="2.2.1"

RUNMODE=AUTO

#Where will logs go - needs to be writable by non-root users
LOGFILE=/tmp/tnc.log
TNC_SCRIPT=/usr/local/bin/tnc.sh

#-------------------------------------
# Main functions of the script
#-------------------------------------

#Status variables
SUCCESS=0

function GUI {
   # In this case
   # In my case, the Raspberry Pi is not connected to a monitor.
   # I access it remotely using VNC as described here:
   # http://learn.adafruit.com/adafruit-raspberry-pi-lesson-7-remote-control-with-vnc
   #
   # If VNC server is running, use its display number.
   # Otherwise default to :0 (the Xwindows on the HDMI display)
   #
   export DISPLAY=":0"

   # Checking for RealVNC sessions (stock in Raspbian Pixel)
   if [ -n "`ps -ef | grep vncserver-x11-serviced | grep -v grep`" ]; then
      sleep 0.1
      echo -e "\nRealVNC found - defaults to connecting to the :0 root window"
     elif [ -n "`ps -ef | grep Xtightvnc | grep -v grep`" ]; then
      # Checking for TightVNC sessions
      echo -e "\nTightVNC found - defaults to connecting to the :1 root window"
      v=`ps -ef | grep Xtightvnc | grep -v grep`
      d=`echo "$v" | sed 's/.*tightvnc *\(:[0-9]\).*/\1/'`
      export DISPLAY="$d"
   fi

   ##echo "Direwolf in GUI mode start up"
   #echo "$(date): Direwolf in GUI mode start up" >> $LOGFILE
   ##echo "DISPLAY=$DISPLAY" 
   #echo "$(date): DISPLAY=$DISPLAY" >> $LOGFILE

   # 
   # Auto adjust the startup for your particular environment:  gnome-terminal, xterm, etc.
   #

   if [ -x /usr/bin/lxterminal ]; then
      /usr/bin/lxterminal -t "$1" --command="$1" &
      SUCCESS=1
     elif [ -x /usr/bin/xterm ]; then
      /usr/bin/xterm -bg white -fg black -e "$1" &
      SUCCESS=1
     elif [ -x /usr/bin/x-terminal-emulator ]; then
      /usr/bin/x-terminal-emulator -e "$1" &
      SUCCESS=1
     else
      echo "Did not find an X terminal emulator.  Reverting to CLI mode"
      SUCCESS=0
   fi
   #echo "-----------------------"
   #echo "$(date): -----------------------" >> $LOGFILE
}

# -----------------------------------------------------------
# Main Script start
# -----------------------------------------------------------

# When running from cron, we have a very minimal environment
# including PATH=/usr/bin:/bin.
#
export PATH=/usr/local/bin:$PATH
export XDG_RUNTIME_DIR=/run/user/`id -u`

# Check log file size.  Delete it if it's too big
find /tmp -type f -name tnc.log -size +100k -delete  2>/dev/null

#Log the start of the script run and re-run
#date >> $LOGFILE

# First wait a little while in case we just rebooted
# and the desktop hasn't started up yet.
#
#sleep 30

SCREEN="$(which screen)"

case "${1,,}" in
   digi*|igate)
   	SCR="$($SCREEN -list | grep direwolf | tr -d ' \t' | cut -d'(' -f1 | tr -d '\n')"
   	if [[ $SCR != "" ]]
   	then
      	pgrep direwolf >/dev/null 2>&1 && exit 0 # Direwolf already running
   	fi
		$TNC_SCRIPT stop >/dev/null 2>&1
   	CMD="$TNC_SCRIPT start ${1,,}"
		pkill -f "(terminal|x-term).*$TNC_SCRIPT"
		if [ $RUNMODE == "AUTO" ]
		then 
   		GUI "$CMD"
   		if [ $SUCCESS -eq 0 ]; then
      		$CMD
   		fi
		elif [ $RUNMODE == "GUI" ]
		then
   		GUI "$CMD"
		elif [ $RUNMODE == "CLI" ]
		then
   		$CMD
		else
   		echo -e "ERROR: illegal run mode given.  Giving up"
   		exit 1
		fi
   	;;
	*)
   	;;
esac


