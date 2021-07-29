#!/bin/bash

VERSION="1.1.1"

# This script checks the status of 4 GPIO pins and runs a script corresponding
# to those settings as described below.  This script is called by initialize-pi.sh,
# which is run a bootup via cron @reboot.

GPIO="$(command -v raspi-gpio)"

function GetSwitchState () {
	# Array P: Array index is the ID of each individual switch in the piano switch.
	#          Array element value is the GPIO BCM number.
	P[1]=25
	P[2]=13
	P[3]=6
	P[4]=5
	local LEVERS=""
	for I in 1 2 3 4
	do
		J=$($GPIO get ${P[$I]} | cut -d' ' -f3 | cut -d'=' -f2) # State of a switch in the piano (0 or 1)
		(( $J == 0 )) && LEVERS="$LEVERS$I"
	done
	echo "$LEVERS"
}

# String $PIANO will identify which levers are in the DOWN position 
PIANO="$(GetSwitchState)"

# Check if the script corresponding to the piano switch setting exists and is not empty.
#
# Scripts must be in the $HOME directory, be marked as executable, and be named
# pianoX.sh where X is one of these:
# 1,12,13,14,123,124,134,1234,2,23,234,24,3,34,4
#
# Example:  When the piano switch levers 2 and 4 are down, the script named 
#           $HOME/piano24.sh will run whenever the Raspberry Pi starts.

[[ $PIANO == "" ]] && MESSAGE="No levers are down." || MESSAGE="Levers $PIANO are down."

if xset q &>/dev/null
then
  	yad --center --title="Test calling pianoX.sh script - version $VERSION" \
  	--info --borders=30 --no-wrap \
  	--text="<b>$MESSAGE $HOME/piano$PIANO.sh will run.</b>" \
  	--buttons-layout=center --button=Close:0
else
	echo "$MESSAGE"
fi

