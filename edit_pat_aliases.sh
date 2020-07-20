#!/bin/bash
#================================================================
# HEADER
#================================================================
#% SYNOPSIS
#+   ${SCRIPT_NAME} [-hv]
#%
#% DESCRIPTION
#%   This script provides a GUI to add aliases to pat's config.json
#%   file by making selections from the output of 'pat rmslist'.  
#%   These aliases are available in pat's web interface.
#%   This script is designed to work on the Hampi image.
#%   This script requires these packages: jq moreutils.
#%
#% OPTIONS
#%    -h, --help                  Print this help
#%    -v, --version               Print script information
#%
#================================================================
#- IMPLEMENTATION
#-    version         ${SCRIPT_NAME} 1.4.2
#-    author          Steve Magnuson, AG7GN
#-    license         CC-BY-SA Creative Commons License
#-    script_id       0
#-
#================================================================
#  HISTORY
#     20200507 : Steve Magnuson : Script creation.
#     20200718 : Steve Magnuson : Allow pactor, winmor, ardop aliases
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
	exec 4>&-

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
	echo "5:@disabled@"
	PAT="pat rmslist"
	[[ $2 == "Any" ]] || PAT+=" -b $2" # Band filter
	[[ $3 == "Any" ]] || PAT+=" -m $3" # Mode filter
	[[ $4 == TRUE ]] &&  PAT+=" -s" # Sort by distance
	echo -e '\f' >> "$fpipe"
	eval $PAT | grep -i "$1" | grep -v VARA | grep -v "^callsign" | grep -v "^$" | tr -s ' ' | \
		awk '{printf "%s\n%s\n%s\n%s\n%s\n%s\n%s %s\n",$11,$1,$7,$2,$3,$4,$5,$6}' >> "$fpipe"
	echo "5:$find_cmd"
}
export -f runFind

function processAlias () {
	local CALL="$(echo "$1" | sed 's/^ //' | cut -d' ' -f2)"
	local URI="$(echo "$1" | sed 's/^ //' | sed -e 's/packet/ax25/' | cut -d' ' -f1)"
	local FREQ="$(echo "$1" | sed 's/^ //' | sed -e 's/packet/ax25/' | cut -d' ' -f3)"
	if jq -r '.connect_aliases | keys[] as $k | "\(.[$k])"' $PAT_CONFIG | grep -q "$URI"
	then # Alias already present
		yad --info --center --text-align=center --buttons-layout=center \
			--text="$URI was already in aliases" --borders=20 --button="gtk-ok":0
	else # Alias not in list.  Add it.
		cat $PAT_CONFIG | jq --arg K "$CALL@$FREQ" --arg U "$URI" \
			'.connect_aliases += {($K): $U}' | sponge $PAT_CONFIG
		if [[ $? == 0 ]]
		then
			yad --info --center --text-align=center --buttons-layout=center \
			--text="$URI was added to aliases" --borders=20 --button="gtk-ok":0
		else
			yad --info --center --text-align=center --buttons-layout=center \
			--text="ERROR: $URI was NOT added to aliases" --borders=20 --button="gtk-ok":0
		fi
	fi
}
export -f processAlias

function viewDeleteAliases () {
	# Load existing aliases
	while true
	do
		# Read aliases from $PAT_CONFIG
		ALIASES="$(jq -r .connect_aliases $PAT_CONFIG | egrep -v "telnet|{|}" | \
				  sed 's/^ /FALSE|/' | tr -d ' ",' | sed 's/:/|/1' | tr '|' '\n')"
		RESULT="$(yad --title="View/remove aliases" --list --mouse --borders=10 \
				--height=400 --width=500 --text-align=center \
				--text "<b>Your current pat connection aliases are listed below.</b>\n \
Check the ones you want to remove.\n" \
				--checklist --grid-lines=hor --auto-kill --column="Pick" --column="Call@Freq" --column="Connect URI" \
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

  #= general variables ==#
  #== general variables ==#
SCRIPT_NAME="$(basename ${0})" # scriptname without path
SCRIPT_DIR="$( cd $(dirname "$0") && pwd )" # script directory
SCRIPT_FULLPATH="${SCRIPT_DIR}/${SCRIPT_NAME}"
SCRIPT_ID="$(ScriptInfo | grep script_id | tr -s ' ' | cut -d' ' -f3)"
SCRIPT_HEADSIZE=$(grep -sn "^# END_OF_HEADER" ${0} | head -1 | cut -f1 -d:)
VERSION="$(ScriptInfo version | grep version | tr -s ' ' | cut -d' ' -f 4)" 

TITLE="Find RMS Stations $VERSION"
PAT_CONFIG="$HOME/.wl2k/config.json"
export PAT_CONFIG=$PAT_CONFIG
export find_cmd='@bash -c "runFind %1 %2 %3 %6"'
export view_remove_cmd='bash -c "viewDeleteAliases"'
export fpipe=$(mktemp -u --tmpdir find.XXXXXXXX)
mkfifo "$fpipe"
DEFAULT_SEARCH_STRING="$(jq -r .locator $PAT_CONFIG)"
fkey=$(($RANDOM * $$))
YAD_PIDs=()
BANDs="^Any!70cm!1.25m!2m!6m!12m!15m!17m!20m!30m!40m!60m!80m!160m"
MODEs="^Any!ARDOP!Packet!Pactor!WINMOR"

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

# Check for required apps.
for A in yad pat jq sponge
do 
	command -v $A >/dev/null 2>&1 || Die "$A is required but not installed."
done

# Ensure only one instance of this script is running.
pidof -o %PPID -x $(basename "$0") >/dev/null && exit 1

#============================
#  MAIN SCRIPT
#============================

trap SafeExit INT TERM EXIT

yad --plug="$fkey" --tabnum=1 --text-align=center \
	 --text="<b>Search for RMS stations and optionally add them to your pat \
connection alias list\n<span color='blue'>If you make changes: Restart pat + TNC + refresh pat web browser!</span></b>" \
	 --form \
	 --field="Search string" "${DEFAULT_SEARCH_STRING:0:4}" \
	 --field="Band":CB "$BANDs" \
	 --field="Mode":CB "$MODEs" \
	 --field="gtk-find":FBTN "$find_cmd" \
	 --field="<b>View/edit current pat connection aliases</b>":FBTN "$view_remove_cmd &" \
	 --field="Sort results by distance (Uncheck to sort by callsign)":CHK TRUE >/dev/null &
YAD_PIDs+=( $! )

yad --plug="$fkey" --tabnum=2 --list --grid-lines=hor --dclick-action="bash -c \"processAlias '%s'\"" \
	--text "Search results are below. Double-click a Call to add it to your pat aliases." \
	--column="URI" --column="Call" --column="Frequency (MHz)" --column="Location" --column="Distance" --column="Azimuth" \
	--column="Mode" \
	--search-column=2 --expand-column=7 --hide-column=1 <&4 >/dev/null &
YAD_PIDs+=( $! )

yad --paned --key="$fkey" --buttons-layout=center --button="gtk-close":0 --width=700 --height=700 \
	--title="$TITLE" --window-icon="system-search" 

SafeExit
	
