#!/bin/bash

VERSION="0.1.1"

# This script allows the user to change the text of the default Nexus desktop background 


TITLE="Desktop Text Editor $VERSION"
CONFIG_FILE="$HOME/desktop-text.conf"
PICTURE_DIR="$HOME/Pictures"
DEFAULT_BACKGROUND_IMAGE="$PICTURE_DIR/NexusDeskTop.jpg"
MESSAGE="Enter the text you want displayed below.\nDon't use any single or double quotation marks."

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

[ -s $DEFAULT_BACKGROUND_IMAGE ] || errorReport "Default Nexus image not in $DEFAULT_BACKGROUND_IMAGE" 1

if ! command -v convert >/dev/null
then
	sudo port update
	sudo port install imagemagick
fi

if [ -s "$CONFIG_FILE" ]
then # There is a config file
   echo "$CONFIG_FILE found."
   source "$CONFIG_FILE"
else # Set some default values in a new config file
   echo "Config file $CONFIG_FILE not found.  Creating a new one with default values."
   echo "TEXT=\"N0ONE\"" > "$CONFIG_FILE"
   echo "SHOW_HOSTNAME=\"TRUE\"" >> "$CONFIG_FILE"
   source "$CONFIG_FILE"
fi

while true
do
	ANS=""
	ANS="$(yad --title="$TITLE" \
   	--text="<b><big><big>Desktop Text Editor</big></big>\n\n \
$MESSAGE</b>\n" \
   	--item-separator="!" \
		--posx=10 --posy=50 \
		--align=right \
   	--buttons-layout=center \
  		--text-align=center \
   	--align=right \
   	--borders=20 \
   	--form \
   	--field="Background Text" "$TEXT" \
   	--field="Include Hostname":CHK $SHOW_HOSTNAME \
   	--focus-field 1 \
	)"

	[[ $? == 1 || $? == 252 ]] && errorReport  # User has cancelled.

	[[ $ANS == "" ]] && errorReport "Error." 1

	IFS='|' read -r -a TF <<< "$ANS"

	TEXT="${TF[0]}"
	SHOW_HOSTNAME="${TF[1]}"
	echo "TEXT=\"$TEXT\"" > "$CONFIG_FILE"
	echo "SHOW_HOSTNAME=\"$SHOW_HOSTNAME\"" >> "$CONFIG_FILE"

	[[ $TEXT == "" ]] && { $(command -v pcmanfm) --set-wallpaper="$DEFAULT_BACKGROUND_IMAGE"; continue; }

	TARGET="$PICTURE_DIR/TEXT_$(echo $TEXT | tr -cd [a-zA-Z0-9]).jpg"
	echo "Deleting $PICTURE_DIR/TEXT_*.jpg"
	find "$PICTURE_DIR" -maxdepth 1 -name TEXT_*.jpg -type f -delete

	if [[ $SHOW_HOSTNAME == "TRUE" ]]
	then
   	$(command -v convert) $DEFAULT_BACKGROUND_IMAGE -gravity south -pointsize 20 -fill white -annotate 0 $(hostname) -gravity south -pointsize 75 -fill white -annotate +0+25 "$TEXT" $TARGET
	else
		$(command -v convert) $DEFAULT_BACKGROUND_IMAGE -gravity south -pointsize 75 -fill white -annotate +0+25 "$TEXT" $TARGET
	fi
	$(command -v pcmanfm) --set-wallpaper="$TARGET"
done
