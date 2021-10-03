#!/bin/bash

VERSION="1.0.6"

# This script installs the scripts and desktop files that customize a Nexus DR-X 
# Raspberry Pi so it can be used for remote access by WECG members.
# 

function Usage () {
	
	echo "Version $VERSION"
	echo
	echo "$(basename $0) installs scripts and files to make a Nexus DR-X Pi suitable"
	echo "for remote access by WECG members. Only WECG administrators should use this"
	echo "script on Pis that are designated for use by WECG members and that have"
	echo "Kenwood Tm-D710G or TM-V71A radios attached via a serial cable."
	echo
	echo "Usage:"
	echo "  $(basename $0) left|right <fldigi-frequency> [rmsgw|aprs <restore-frequency>]"
	echo
	echo "  \"left\" or \"right\" is what channel on the Nexus DR-X is used for audio"
	echo "  to/from the Kenwood radio."
	echo
	echo "  \"fldigi-frequency\" is the frequency in MHz to QSY to when starting Fldigi."
	echo
	echo " OPTIONAL:"
	echo "  \"rmsgw\" or \"aprs\" is what app to restart after Fldigi closes."
	echo
	echo "  \"restore-frequency\" is the frequency in MHz to QSY to after stopping"
	echo "  Fldigi and restarting rmsgw or aprs."
	echo
	echo "Examples:"
	echo "  $(basename $0) left 145.580 rmsgw 144.990"
	echo "  $(basename $0) right 145.020 aprs 144.390"
	echo
}

# Check for 4 arguments arguments
[[ $# == 2 || $# == 4 ]] || Usage

function Die () {
	echo "${*}"
	exit 1
}

# Validate input
RE="^[0-9]+([.][0-9]+)?$"
[[ $2 =~ $RE ]] || Die "ERROR: Arg 2: $2 is not a frequency"
# echo "Arg1='$1', Arg2='$2', Arg3='$3', Arg4='$4'"
if [[ ! -z $4 ]]
then
	[[ $4 =~ $RE ]] || Die "ERROR: Arg 4: $4 is not a frequency"
fi

FLDIGI_FREQ="$2"
[[ ! -z $4 ]] && RESTORE_FREQ="$4" || RESTORE_FREQ=""

case ${1,,} in
	left|right)
		SIDE="${1,,}"
		;;
	*)
		Die "ERROR: First argument must be left or right"
		;;
esac
if [[ ! -z $3 ]]
then
	case ${3,,} in
		rmsgw|aprs)
			RESTORE_APP="${3,,}"
			;;
		*)
			Die "ERROR: Third argument must be left or right"
			;;
	esac
else
	RESTORE_APP=""
fi

# Get the files 
echo >&2 "Retrieving WECG files and scripts..."
cd /usr/local/src/nexus
rm -rf wecg
git clone https://github.com/AG7GN/wecg
[[ $? == 0 ]] || Die "FAILED.  Aborting installation."
echo >&2 "Done."
cd wecg

# Get the Fldigi XML file for the Kenwood 710/71A 
echo >&2 "Retrieving Fldigi XML file for Kenwood 710/71A..."
wget -q -O TM-D710G.xml http://www.w1hkj.com/files/xmls/kenwood/TM-D710G.xml
[[ $? == 0 ]] || Die "FAILED.  Unable to retrieve FLdigi XML file."
echo >&2 "Done."

# Move files into place
echo >&2 "Moving files into place..."
mv TM-D710G.xml $HOME/.fldigi-${SIDE}/rigs/
sudo mv *.sh /usr/local/bin/
for K in start kill stop
do
	cp flapps_$K.template flapps_$K.desktop
	[[ $K == "stop" && -z $RESTORE_APP ]] && SIDE=""
	sed -i -e "s/_HOME_/\/home\/$USER/g" -e "s/_SIDE_/$SIDE/g" \
		-e "s/_FLDIGI_FREQ_/$FLDIGI_FREQ/g" \
		-e "s/_RESTORE_APP_/$RESTORE_APP/g" \
		-e "s/_RESTORE_FREQ_/$RESTORE_FREQ/g" flapps_$K.desktop
done
sudo mv *.desktop /usr/local/share/applications/
echo >&2 "Done."
echo >&2
echo >&2 "Installation complete. Opening browser to online instructions for next steps."
xdg-open https://github.com/AG7GN/wecg/blob/master/README.md >/dev/null 2>&1 &
exit 0

