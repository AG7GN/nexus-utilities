# Hampi Utilities

VERSION 20191117

This is a collection of utilities for the Hampi image.  These scripts will only work on the Hampi image.   
Some scripts are specific to the [Nexus DR-X](http://wb7fhc.com/nexus-dr-x.html) board.

[check-piano.sh](#check-piano-script)

[initialize-pi.sh](#initialize-pi-script)

[name-radios.sh](#name-radios-script)

[patmail.sh](#patmail-script)

[tnc-left.conf tnc-right.conf](#tnc-left-tnc-right-configuration-files)

[test-piano.sh](#test-piano-script)

[tnc.sh](#tnc-script)

[trim scripts](#trim-scripts)

[watchdog-tnc.sh](#watchdog-tnc-script)

[shutdown_button.py](#shutdown-button-script)

[radio-monitor.py](#radio-monitor-script)

[pianoX.sh.example](#piano-script-example)

[Desktop Template files](#desktop-template-files)

## Installation

### Easy Install

- Click __Raspberry > Hamradio > Update Pi and Ham Apps__.
- Check __hampi-utilities__, click __OK__.

### Manual Install

Alternatively, you can install these utilities manually as follows:

- Open a terminal and run:

		cd ~
		rm -rf hampi-utilities 
		git clone https://github.com/AG7GN/hampi-utilities  
  		cp -f hampi-utilities/hampi-utilities.version /usr/local/src/hampi/
  		cp -f hampi-utilities/*.conf /usr/local/src/hampi/
  		cp -f hampi-utilities/*.example $HOME/
  		sudo cp -f hampi-utilities/*.sh /usr/local/bin/
  		sudo cp -f hampi-utilities/*.py /usr/local/bin/
  		sudo cp -f hampi-utilities/*.desktop /usr/local/share/applications/
  		sudo cp -f hampi-utilities/*.template /usr/local/share/applications/
		rm -rf hampi-utilities
		
## Check Piano script

`check-piano.sh` is run whenever the Pi starts.  It reads the position of the piano switches on the [Nexus DR-X](http://wb7fhc.com/nexus-dr-x.html) board and launches a script based on which switch levers are up or down.  The script is called by the `autostart` file located in `/etc/xdg/lxsession/LXDE-pi`.  That file looks like this:

	@lxpanel --profile LXDE-pi
	@pcmanfm --desktop --profile LXDE-pi
	@bash /usr/local/bin/check-piano.sh
	@xscreensaver -no-splash

The script that `check-piano.sh` calls must be in the user's home directory, be marked as executable, and be named `pianoX.sh` where X is one of these:

	1, 12, 13, 14, 123, 124, 134, 1234, 2, 23, 234, 24, 3, 34, 4

Example:  When the piano switch levers 2 and 4 are down, the script named `$HOME/piano24.sh` will run whenever the Raspberry Pi starts.
 
See [pianoX.sh.example](#piano-script-example) for an example piano script.
 
If a pianoX.sh script is not present in the home folder, no action is taken and the pi boots normally.
 
## Initialize Pi script

`initialize-pi.sh` is run whenever the Pi starts.  It runs via this line in user pi's crontab:

	@reboot sleep 5 && /usr/local/bin/initialize-pi.sh

The script checks for the presence of a file called `DO_NOT_DELETE_THIS_FILE` in the user's home directory.  If `DO_NOT_DELETE_THIS_FILE` is not present in the user's home directory, the script will reset various configuration files for ham radio applications to default values and reset the VNC Server and SSH keys.  It will then create the `DO_NOT_DELETE_THIS_FILE` file in the user's home directory.

If `DO_NOT_DELETE_THIS_FILE` is present in the home folder, the script exits without taking any action.

## Name Radios script

`name-radios.sh` allows you to change the title bar of Fldigi suite and Direwolf applications so they say something other than "Left Radio" or "Right Radio".  The associated menu entry file is `/usr/local/share/applications/nameradios.desktop`.

## Patmail script

`patmail.sh` allows the user to run [pat](https://getpat.io) within scripts rather than interactively.  Obviously, pat must be installed for it to work.  You can install Pat via __Raspberry > Hamradio > Update Pi and Ham Apps__. 

## Test Piano script

`test-piano.sh` allows you to test the operation of your `pianoX.sh` script by simulating what the [check-piano.sh](#check-piano-script) does when the Pi starts.  Set the piano switches as desired, then open a Terminal and run `test-piano.sh`.  The script will tell you which script will run based on which switch levers are down.  It will not actually run the `pianoX.sh` script.

## TNC left TNC right Configuration Files

`tnc-left.conf` and `tnc-right.conf` configuration files are required by [/usr/local/bin/tnc.sh](#tnc-script) script.  They contain the configuration that `tnc.sh` needs in order to operate with Direwolf as an APRS Digitpeater, iGate, Digipeater+iGate, or ax25 TNC.

__IMPORTANT__: You must edit `tnc-{left|right}.conf` with your own settings before running `tnc.sh` for the first time.

`tnc.sh` will look for `tnc.conf` in the user's home folder.  To use `tnc.sh`, you must make a symlink to the appropriate tnc configuration file for the left or right radio. 
 
- For the left radio:

		cd ~
		ln -s tnc-left.conf tnc.conf

- For the right radio:

		cd ~
		ln -s tnc-right.conf tnc.conf

## TNC Script

`tnc.sh` launches Direwolf, and optionally other related apps, in different modes.  The script will look for [tnc.conf](#tnc-left-tnc-right-configuration-files) in the user's home directory.  The script will set up and run Direwolf to operate in any one of these modes TNC: ax25, APRS Digipeater, APRS iGate, APRS Digipeater+iGate.  It can also launch pat, ardop, pat+ax25, or pat+ardop provided those apps are also installed and configured.

## Trim Scripts

	trim-fldigi-log.sh
	trim-flmsg-log.sh
	trim-flrig-log.sh
	trim-fsq-audit.sh
	trim-fsq-heard.sh
	
This collection of scripts trims the logs of various applications in the Fldigi family.  They all take 1 argument: A date reference, for example: "10 days ago" or "1 hour ago".  The script will delete log entries older than the date specified.  These scripts are run whenever you launch Fldigi, Flrig and Flmsg from the __Raspberry > Hamradio__ menu.  You can change the timeframe of the trim by editing the `.desktop.` file.  For example, this is the Exec entry in the `/usr/local/share/applications/fldigi-left.desktop` file:

	Exec=sh -c '/usr/local/bin/trim-fldigi-log.sh "yesterday";PULSE_SINK=fepi-playback PULSE_SOURCE=fepi-capture fldigi --config-dir /home/pi/.fldigi-left -title "Fldigi (Left Radio)" --flmsg-dir /home/pi/.nbems-left'	
	
To change it to trim log entries older than 2 weeks ago rather than yesterday, the line would look like this:

	Exec=sh -c '/usr/local/bin/trim-fldigi-log.sh "2 weeks ago";PULSE_SINK=fepi-playback PULSE_SOURCE=fepi-capture fldigi --config-dir /home/pi/.fldigi-left -title "Fldigi (Left Radio)" --flmsg-dir /home/pi/.nbems-left'	

## Watchdog TNC Script

`watchdog-tnc.sh` runs via cron.  It launches [tnc.sh](#tnc-script) and restarts it automatically if it stops for some reason.  It is intended for use when `tnc.sh` is run in one of the APRS modes.  The script takes one argument, which it passes to `tnc.sh` as the "mode" argument.  These are examples of entries you could use in crontab (only ONE can be used at one time):

	# This one digipeats only - no internet
	*/2 * * * * /usr/local/bin/watchdog-tnc.sh digi >/dev/null 2>&1

	# This one digipeats and igates 
	*/2 * * * * /usr/local/bin/watchdog-tnc.sh digiigate >/dev/null 2>&1

	# This one igates only
	*/2 * * * * /usr/local/bin/watchdog-tnc.sh igate >/dev/null 2>&1

## Shutdown Button Script

`shutdown_button.py` monitors the shutdown button found on the DigiLink REV DS and [Nexus DR-X](http://wb7fhc.com/nexus-dr-x.html) boards.  It reboots the Pi if the button is pressed more than 2 but less than 5 seconds, or shuts down the Pi if the button is pressed for more than 5 seconds.

Your Hampi image already has the systemd service file for the shutdown script installed and enabled.  No further action is required to enable it, but __for documentation purposes only__, here's how to enable the service manually:

- As sudo, create a file called `/etc/systemd/system/shutdown_button.service` with the following text:

		[Unit]
		Description=GPIO shutdown button
		After=network.target

		[Service]
		Type=simple
		Restart=always
		RestartSec=1
		User=root
		ExecStart=/usr/bin/python3 /usr/local/bin/shutdown_button.py

		[Install]
		WantedBy=multi-user.target

- Run these commands in a Terminal to enable the service:

		sudo systemctl enable shutdown_button.service
		sudo systemctl start shutdown_button.service

## Radio Monitor script

`radio-monitor.py` monitors the TX/RX status of your radios via the GPIO pins (BCM 12 for the left radio and BCM 23 for the right radio).  The associated Hamradio menu item is in the `radio-monitor.desktop` file.

## Piano Script example

`pianoX.sh.example` is stored in your home folder and contains some ideas for using the piano switch feature of the Nexus DR-X boards.  Copy this file to your own script (`pianoX.sh` where `X` is 1,2,3,4 or some combination of those numbers) and edit as desired to make your Pi run certain scripts or applications at boot time.

## Desktop Template Files

These files are stored in `/usr/local/share/applications` and are used as templates for application desktop files.  They are used by the __Name Your Radio__ script to change the radio names as they appear in the Hamradio menu.


 