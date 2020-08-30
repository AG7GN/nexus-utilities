#!/bin/bash

VERSION="1.17.0"

#
# Script to generate new VNC server and SSH server keys at boot time if a certain 
# file does not exist.  Run this script whenever the Pi boots by adding a crontab 
# entry, like this:
#
# 1) Run crontab -e
# 2) Add the following line to the end:
#
#    @reboot sleep 5 && /usr/local/bin/initialize-pi.sh
#
# 3) Save and exit the crontab editor
#

DIR="$HOME"
INIT_DONE_FILE="$DIR/DO_NOT_DELETE_THIS_FILE"

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
   for F in $DIR/$D/*log*
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
sed -i 's/^MYCALL=.*/MYCALL=\"N0ONE-10\"/' $DIR/tnc-*.conf

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
SCRIPT="$(command -v rmsgw-activity.sh)"
PAT_DIR="$HOME/.wl2kgw"
PAT="$(command -v pat) --config $PAT_DIR/config.json --mbox $PAT_DIR/mailbox --send-only --event-log /dev/null connect telnet"
CLEAN="find $PAT_DIR/mailbox/*/sent -type f -mtime +30 -exec rm -f {} \;"
# remove old style pat cron job, which used the default config.json pat configuration
OLDPAT="$(command -v pat) --send-only --event-log /dev/null connect telnet"
cat <(fgrep -i -v "$OLDPAT" <(sudo crontab -u $USER -l)) | sudo crontab -u $USER -
cat <(fgrep -i -v "$SCRIPT" <(sudo crontab -u $USER -l)) | sudo crontab -u $USER -
cat <(fgrep -i -v "$PAT" <(sudo crontab -u $USER -l)) | sudo crontab -u $USER -
cat <(fgrep -i -v "$CLEAN" <(sudo crontab -u $USER -l)) | sudo crontab -u $USER -

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
for F in $D/*-left.template $D/*-right.template
do
   sudo sed -e "s/_LEFT_RADIO_/Left Radio/" -e "s/_RIGHT_RADIO_/Right Radio/g" $F > ${F%.*}.desktop
done

# Reset pat configuration
if [ -f $HOME/.wl2k/config.json ]
then
	rm -f $HOME/.wl2k/config.json*
#	sed -i -e 's/"mycall": .*",$/"mycall": "",/' \
#		-e 's/"secure_login_password": .*",$/"secure_login_password": "",/' \
#		-e 's/"locator": .*",$/"locator": "",/' $HOME/.wl2k/config.json
#	rm -f $HOME/.wl2k/config.json~
#	rm -rf $HOME/.wl2k/mailbox/*
#	> $HOME/.wl2k/eventlog.json
#	> $HOME/.wl2k/pat.log
#	echo "Delete pat configuration" >> "$INIT_DONE_FILE"
fi

# Reset Desktop image
if [ -f $HOME/.config/pcmanfm/LXDE-pi/desktop-items-0.conf ]
then
	rm -f $HOME/desktop-text.conf
	rm -f $HOME/Pictures/TEXT_*.jpg
	if [ -f $HOME/Pictures/NexusDeskTop.jpg ]
	then
		sed -i -e "s|^wallpaper=.*|wallpaper=$HOME/Pictures/NexusDeskTop.jpg|" $HOME/.config/pcmanfm/LXDE-pi/desktop-items-0.conf
	fi
fi

# Clear Terminal history
echo "" > $HOME/.bash_history && history -c
echo "Delete shell history" >> "$INIT_DONE_FILE"

# Expand the filesystem if it is < 8 GB 
echo "Expand filesystem if needed" >> "$INIT_DONE_FILE"
PARTSIZE=$( df | sed -n '/root/{s/  */ /gp}' | cut -d ' ' -f2 )
THRESHOLD=$((8 * 1024 * 1024))
(( $PARTSIZE < $THRESHOLD )) && sudo raspi-config --expand-rootfs >> "$INIT_DONE_FILE"

echo "Raspberry Pi initialization complete" >> "$INIT_DONE_FILE"
sudo shutdown -r now
