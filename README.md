# Hampi Utilities

This is a collection of utilities for the Hampi image.  These scripts will only work on the Hampi image.  Some scripts are specific to the [Nexus DR-X](http://wb7fhc.com/nexus-dr-x.html) board.

[check-piano.sh](#check-piano-script)

[initialize-pi.sh](#initialize-pi-script)

[name-radios.sh](#name-radios-script)

[patmail.sh](#patmail-script)

[tnc-left.conf tnc-right.conf](#tnc-left-tnc-right-configuration-files)

[test-piano.sh](#test-piano-script)

[tnc.sh](#tnc-script)

[trim scripts](#trim-scripts)

[watchdog-tnc.sh](#watchdog-tnc-script)

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
		sudo cp hampi-utilities/*.sh /usr/local/bin
		sudo cp hampi-utilities/*.desktop /usr/local/share/applications/
		cp hampi-utilities/hampi-utilities.version /usr/local/src/hampi/
		rm -rf hampi-utilities
		
## check piano script

`check-piano.sh` is called by [initialize-pi.sh](#initialize-pi.sh) whenever the Pi starts.  It reads the position of the piano switches on the [Nexus DR-X](http://wb7fhc.com/nexus-dr-x.html) board and launches a script based on which switch levers are up or down.

The script that `check-piano.sh` calls must be in the user's home directory, be marked as executable, and be named `pianoX.sh` where X is one of these:

1, 12, 13, 14, 123, 124, 134, 1234, 2, 23, 234, 24, 3, 34, 4

 Example:  When the piano switch levers 2 and 4 are down, the script named `$HOME/piano24.sh` will run whenever the Raspberry Pi starts.
 
 If a pianoX.sh script is not present, no action is taken and the pi boots normally.
 
## initialize pi script

`initialize-pi.sh` is run whenever the Pi starts.  It runs via this line in user pi's crontab:

	@reboot sleep 5 && /usr/local/bin/initialize-pi.sh

The script checks for the presence of a file called `DO_NOT_DELETE_THIS_FILE` in the user's home directory.  If the file is present, the script runs [check-piano.sh](#check-piano.sh) and then exits.

If `DO_NOT_DELETE_THIS_FILE` is not present in the user's home directory, the script will reset various configuration files for ham radio applications to default values and reset the VNC Server and SSH keys.

## name radios script

`name-radios.sh` allows the user to change the title bar of Fldigi suite and Direwolf applications so they say something other than "Left Radio" or "Right Radio".  The associated menu item file is `nameradios.desktop`.

## patmail script

`patmail.sh` allows the user to run [pat](https://getpat.io) within scripts rather than interactively.  Obviously, pat must be installed for it to work.  You can install Pat via __Raspberry > Hamradio > Update Pi and Ham Apps__. 

## test piano script

`test-piano.sh` allows you to test the operation of your `pianoX.sh` script by simulating what the [check-piano.sh](#check-piano.sh) does when the Pi starts.  Set the piano switches as desired, then open a Terminal and run `test-piano.sh`.  The script will tell you which script will run based on which switch levers are down.  It will not actually run the `pianoX.sh` script.

## tnc left tnc right configuration files

`tnc-left.conf` and `tnc-right.conf` configuration files are required by [/usr/local/bin/tnc.sh](#tnc.sh) script.  They contain the configuration that `tnc.sh` needs in order to operate with Direwolf as an APRS Digitpeater, iGate, Digipeater+iGate, or ax25 TNC.

`tnc.sh` will look for `tnc.conf` in the user's home folder.  To use `tnc.sh`, you must make a symlink to the appropriate tnc configuration file for the left or right radio. 
 
- For the left radio:

		cd ~
		ln -s tnc-left.conf tnc.conf

- For the right radio:

		cd ~
		ln -s tnc-right.conf tnc.conf
		
__IMPORTANT__: You must edit tnc-{left|right}.conf with your own settings.


## tnc script

`tnc.sh` launches Direwolf, and optionally other related apps, in different modes.  The script will look for [tnc.conf](#tnc-left.conf-tnc-right.conf) in the user's home directory.  The script will set up Direwolf to operate in any one of these modes TNC: ax25, APRS Digipeater, APRS iGate, APRS Digipeater+iGate.  It can also launch pat, ardop, pat+ax25, or pat+ardop provided those apps are also installed and configured.

## trim scripts

	trim-fldigi-log.sh
	trim-flmsg-log.sh
	trim-flrig-log.sh
	trim-fsq-audit.sh
	trim-fsq-heard.sh
	
This collection of scripts trims the logs of various applications in the Fldigi family.  They all take 1 argument: A date reference, for example: "10 days ago" or "1 hour ago".  The script will delete log entries older than the date specified.  These scripts are run whenever you launch Fldigi, Flrig and Flmsg from the __Raspberry > Hamradio__ menu.  You can change the timeframe of the trim by editing the `.desktop.` file.  For example, this is the Exec entry in the `/usr/local/share/applications/fldigi-left.desktop` file:

	Exec=sh -c '/usr/local/bin/trim-fldigi-log.sh "yesterday";PULSE_SINK=fepi-playback PULSE_SOURCE=fepi-capture fldigi --config-dir /home/pi/.fldigi-left -title "Fldigi (Left Radio)" --flmsg-dir /home/pi/.nbems-left'	
	
To change it to trim log entries older than 2 weeks ago rather than yesterday, the line would look like this:

	Exec=sh -c '/usr/local/bin/trim-fldigi-log.sh "2 weeks ago";PULSE_SINK=fepi-playback PULSE_SOURCE=fepi-capture fldigi --config-dir /home/pi/.fldigi-left -title "Fldigi (Left Radio)" --flmsg-dir /home/pi/.nbems-left'	

## watchdog tnc script

`watchdog-tnc.sh` runs via cron.  It launches tnc.sh and restarts it automatically if it stops for some reason.  It is intended for use when [tnc.sh](#tnc.sh) is run in one of the APRS modes.  The script takes one argument, which it passes on to tnc.sh as the "mode" argument.  These are examples of entries you could use in crontab (only ONE can be used at one time):

	# This one digipeats only - no internet
	*/2 * * * * /usr/local/bin/watchdog-tnc.sh digi >/dev/null 2>&1

	# This one digipeats and igates 
	*/2 * * * * /usr/local/bin/watchdog-tnc.sh digiigate >/dev/null 2>&1

	# This one igates only
	*/2 * * * * /usr/local/bin/watchdog-tnc.sh igate >/dev/null 2>&1

