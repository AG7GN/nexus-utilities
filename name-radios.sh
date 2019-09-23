#!/bin/bash

VERSION="1.0.3"

# This script allows the user to change the title bar of Fldigi suite and Direwolf
# applications so they say something other than "Left Radio" or "Right Radio"

TITLE="Left/Right Radio Name Editor $VERSION"
CONFIG_FILE="$HOME/radionames.conf"

trap errorReport INT

function errorReport () {
   echo
   if [[ $1 == "" ]]
   then
      exit 0
   else
      if [[ $2 == "" ]]
      then
         echo >&2 "$1"
         exit 1
      else
         echo >&2 "$1"
         exit $2
      fi
   fi
}

if [ -s "$CONFIG_FILE" ]
then # There is a config file
   echo "$CONFIG_FILE found."
   source "$CONFIG_FILE"
else # Set some default values in a new config file
   echo "Config file $CONFIG_FILE not found.  Creating a new one with default values."
   echo "LEFT_RADIO_NAME=\"Left Radio\"" > "$CONFIG_FILE"
   echo "RIGHT_RADIO_NAME=\"Right Radio\"" >> "$CONFIG_FILE"
   source "$CONFIG_FILE"
fi


ANS=""
ANS="$(yad --title="$TITLE" \
   --text="<b><big><big>Auto-HotSpot Configuration Parameters</big></big>\n\n</b>Status: <b><span color='blue'>$STATUS</span>\n\n \
$MESSAGE</b>\n" \
   --item-separator="!" \
   --center \
   --buttons-layout=center \
   --text-align=center \
   --align=right \
   --borders=20 \
   --form \
   --field="Left Radio Name" "$LEFT_RADIO_NAME" \
   --field="Right Radio Name" "$RIGHT_RADIO_NAME" \
   --focus-field 1 \
)"

[[ $? == 1 || $? == 252 ]] && errorReport  # User has cancelled.

[[ $ANS == "" ]] && errorReport "Error." 1

IFS='|' read -r -a TF <<< "$ANS"

LEFT_RADIO_NAME="${TF[0]}"
RIGHT_RADIO_NAME="${TF[1]}"
echo "LEFT_RADIO_NAME=\"$LEFT_RADIO_NAME\"" > "$CONFIG_FILE"
echo "RIGHT_RADIO_NAME=\"$RIGHT_RADIO_NAME\"" >> "$CONFIG_FILE"

D="/usr/local/share/applications"
for F in `ls $D/*-left.template` `ls $D/*-right.template`
do
   sudo sed -e "s/_LEFT_RADIO_/$LEFT_RADIO_NAME/" -e "s/_RIGHT_RADIO_/$RIGHT_RADIO_NAME/g" $F > ${F%.*}.desktop
done


