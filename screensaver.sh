#!/bin/bash

## Slideshow pictures screensaver
##
## Author: eli ben ya'acov
##
## 3rd party apps: xdotool; xprintidle; feh; yad
##
## To-do:

appname=$(basename $0)

function usage {
	echo
	echo "Pictures slideshow screensaver"
	echo
	echo "usage: $appname [-b | -s [dir] [-d delay ] [-z | -Z] | -c | -h]"
	echo
	echo -e "  -b\t\t- run in background, starting screen saver when system is idle (\e[4mdefault\e[0m)"
	echo -e "  -s\t\t- start screen saver now"
	echo -e "  dir\t\t- directory of images"
	echo -e "  -d\t\t- delay between each image (in seconds)"
	echo -e "  -z\t\t- randomize the slideshow"
	echo -e "  -Z\t\t- do not randomize the slideshow"
	echo -e "  -c\t\t- change settings (config file: \e[3m~/.config/screensaver/screensaver.conf\e[0m)"
	echo -e "  -h | --help\t- display help"
	echo
	echo -e "running \e[3m$appname\e[0m without any arguments will start in background mode"
}

[[ ! "$1" ]] && action='background'

while [[ "$1" != "" ]]; do
	case "$1" in
		-h | --help )	usage
						exit
						;;
		-b )			action='background' ;;
		-s )			action='start'
						while [[ "$2" != "" ]]; do
							case "$2" in
								-z )	tmp_randomize="true" ;;
								-Z )	tmp_randomize="false" ;;
								-d )	[[ "$3" -gt "0" ]] && tmp_interval="$3" && shift ;;
								* )		if [[ -d "$2" ]]; then
											tmp_picsdir="$2"
										else
											echo "unable to find directory $2"
											exit 1
										fi
										;;
							esac
							shift
						done
						;;
		-c )			action='conf' ;;
		--fork )		sleep 10 ;;
		*  )			usage
						exit 1
						;;
	esac
	shift
done

function read_confile {
	start_on_boot=$(grep "^start_on_boot = " "$confile" | cut -d '=' -f 2 | xargs)
	enabled=$(grep "^enabled = " "$confile" | cut -d '=' -f 2 | xargs)
	pics_dir=$(grep "^pics_dir = " "$confile" | cut -d '=' -f 2- | xargs)
	recursive=$(grep "^recursive = " "$confile" | cut -d '=' -f 2 | xargs)
	idle_wait=$(grep "^idle_wait = " "$confile" | cut -d '=' -f 2- | xargs)
	slideshow_interval=$(grep "^slideshow_interval = " "$confile" | cut -d '=' -f 2 | xargs)
	randomize=$(grep "^randomize = " "$confile" | cut -d '=' -f 2 | xargs)
}

function write_confile {
	sed -i --follow-symlinks "s/^start_on_boot = .*/start_on_boot = $start_on_boot/" "$confile"
	sed -i --follow-symlinks "s/^enabled = .*/enabled = $enabled/" "$confile"
	sed -i --follow-symlinks "s#^pics_dir = .*#pics_dir = $pics_dir#" "$confile"
	sed -i --follow-symlinks "s/^recursive = .*/recursive = $recursive/" "$confile"
	sed -i --follow-symlinks "s/^idle_wait = .*/idle_wait = $idle_wait/" "$confile"
	sed -i --follow-symlinks "s/^slideshow_interval = .*/slideshow_interval = $slideshow_interval/" "$confile"
	sed -i --follow-symlinks "s/^randomize = .*/randomize = $randomize/" "$confile"
}

function start_screensaver {
	[[ "$tmp_picsdir" ]] && pics_dir="$tmp_picsdir"  # if user specificed a directory to use
	[[ "$tmp_interval" ]] && slideshow_interval="$tmp_interval"  # if user specificed a slideshow interval
	[[ "$tmp_randomize" ]] && randomize="$tmp_randomize"  # if user specificed random/not random order
	if [[ "$randomize" == "true" ]]; then
		randomize="--randomize"
	elif [[ "$randomize" == "false" ]]; then
		unset randomize
	fi
	echo "Starting screensaver..." | tee -a "$logfile"
	feh -r $randomize -Z -F -Y -N -q -D "$slideshow_interval" --zoom fill "$pics_dir" --action "xdg-open %F" --action1 "gimp %F" &
	pid_ss=$!
	sleep 2; echo "Please be patient..."
}

function screensaver_config {
	prev_start_on_boot="$start_on_boot"
	mm=$((idle_wait / 60 / 1000))
	val=$(yad --title "Screensaver - Settings" --bool-fmt=t --center --borders=10 --window-icon=settings-configure --form --geometry=550x375 \
		--field="Start On Boot":chk "$start_on_boot" \
		--field="Enabled":chk "$enabled" \
		--field="Pictures Directory: ":dir "$pics_dir" \
		--field="Recursive":chk "$recursive" \
		--field="Randomize":chk "$randomize" \
		--field="Start Screensaver After (Minutes): ":num "$mm!1..60" \
		--field="Change Images Every (Seconds): ":num "$slideshow_interval!1..60")
	x="$?"
	if [[ "$x" == "0" ]]; then
		start_on_boot=$(echo "$val" | cut -d '|' -f 1)
		enabled=$(echo "$val" | cut -d '|' -f 2)
		pics_dir=$(echo "$val" | cut -d '|' -f 3)
		recursive=$(echo "$val" | cut -d '|' -f 4)
		randomize=$(echo "$val" | cut -d '|' -f 5)
		mm=$(echo "$val" | cut -d '|' -f 6)
		idle_wait=$((mm * 1000 * 60))
		slideshow_interval=$(echo "$val" | cut -d '|' -f 7)
		write_confile
		if [[ "$start_on_boot" != "$prev_start_on_boot" ]]; then
			if [[ "$start_on_boot" == "false" ]]; then
				if [[ -f "$HOME/.config/autostart/screensaver.desktop" ]]; then
					mv -vf "$HOME/.config/autostart/screensaver.desktop" "$HOME/.config/autostart/disabled/" | tee -a "$logfile"
				fi
			else  # enable on boot
				if [[ -f "$HOME/.config/autostart/disabled/screensaver.desktop" ]]; then
					mv -vf "$HOME/.config/autostart/disabled/screensaver.desktop" "$HOME/.config/autostart/screensaver.desktop" | tee -a "$logfile"
				elif [[ -f "/mnt/home/$USER/.config/autostart/screensaver.desktop" ]]; then
					ln -sv "/mnt/home/$USER/.config/autostart/screensaver.desktop" "$HOME/.config/autostart/screensaver.desktop" | tee -a "$logfile"
				else
					~/bin/confrw.sh 'Desktop Entry' Exec "/bin/sh -c '/usr/bin/rmdir /var/tmp/screensaver.lock; exec /home/eli/bin/screensaver.sh 1>/dev/null 2>/tmp/screensaver.log'" "$HOME/.config/autostart/screensaver.desktop"
					~/bin/confrw.sh 'Desktop Entry' Icon dialog-scripts "$HOME/.config/autostart/screensaver.desktop"
					~/bin/confrw.sh 'Desktop Entry' Name Screensaver "$HOME/.config/autostart/screensaver.desktop"
					~/bin/confrw.sh 'Desktop Entry' Type Application "$HOME/.config/autostart/screensaver.desktop"
					~/bin/confrw.sh 'Desktop Entry' X-KDE-AutostartScript false "$HOME/.config/autostart/screensaver.desktop"
				fi
			fi
		fi
	fi
}

function background {
	echo -e "\n$(date '+%a %Y-%m-%d %k:%M:%S')\n------- ------ ----- ---- --- -- -" >> "$logfile"
	lockdir="screensaver.lock"  # lock mechanism to insure one instance only is running
	if ! mkdir "/var/tmp/$lockdir" 2> /dev/null; then
		echo "error: screensaver already running in background" | tee -a "$logfile"
		exit 1
	fi
	trap 'rm -fr "/var/tmp/$lockdir"; exit' SIGINT SIGTERM SIGQUIT EXIT #ERR  # delete lockdir on script exit
	echo "Running in background mode:" | tee -a "$logfile"
	script_time=$(stat -c "%Y" "$0")  # modification time of this script (for checking real time changes of script)
	config_time=$(stat --format=%Y "$confile")  # check (ahead) if config file was modified during script runtime
	while true; do
		sleep 30  # sleep 30 seconds between checking for idle time and script/config file changes

		new_script_time=$(stat -c "%Y" "$0")  # check for script changes (on disk)
		if [[ "$new_script_time" != "$script_time" ]]; then  # script changed. fork
			echo "[$(date '+%Y-%m-%d %k:%M:%S')]: Script changed on disk, launching new instance..." | tee -a "$logfile"
			bash -c "exec $0 -b --fork" &  # launch a new instance of this script and exit this one
			echo -e "Exiting\n\n" | tee -a "$logfile"
			exit
		fi

		new_config_time=$(stat --format=%Y "$confile")  # check for config file changes
		if [[ "$config_time" != "$new_config_time" ]]; then  # config file changed, reload config
			echo "[$(date '+%Y-%m-%d %k:%M:%S')]: Config file changed, reloading config" | tee -a "$logfile"
			read_confile
			config_time="$new_config_time"
		fi

		scrsize=$(xdotool search --name --maxdepth 0 '.*' getwindowgeometry | grep 'Geometry:' | tr -d ' ' | cut -f 2 -d ':')
		winsize=$(xdotool getactivewindow getwindowgeometry | grep 'Geometry:' | tr -d ' ' | cut -f 2 -d ':')
		winname=$(xdotool getactivewindow getwindowname | tr [:upper:] [:lower:])
		if [[ "$enabled" == "true" ]] && [[ "$winsize" != "$scrsize" || "$winname" == *"desktop"* ]] && [[ ! $(ps -A | grep screenlocker) ]]; then
			echo "Checking idle time..." #| tee -a "$logfile"
			unset idle
			if [[ $(type -p xprintidle) ]]; then
				idle=$(xprintidle)
			elif [[ $(type -p dbus-send) ]]; then
				idle=$(dbus-send --session --dest=org.freedesktop.ScreenSaver --type=method_call --print-reply=literal --reply-timeout=1000 /ScreenSaver org.freedesktop.ScreenSaver.GetSessionIdleTime | tr -s ' ' | cut -f 3 -d ' ')
			elif [[ $(type -p qdbus) ]]; then
				idle=$(qdbus org.kde.screensaver /ScreenSaver GetSessionIdleTime)
			fi
			if [[ "$idle" =~ ^[0-9]+$ ]]; then
				if [[ "$idle" -gt "$idle_wait" ]]; then
					echo "[$(date '+%Y-%m-%d %k:%M:%S')]: Idle time reached, starting screensaver" | tee -a "$logfile"
					start_screensaver
					echo "Waiting for process $pid_ss to finish" | tee -a "$logfile"
					wait $pid_ss  # no need to continue and check for config/script changes on disk, useless
				fi
			else
				echo "Error getting idle time (got '$idle')" | tee -a "$logfile"
			fi
		fi
	done
}
#  ------------------------------------------------------------------------------------------------ end of functions --

confdir="$HOME/.config/screensaver"
if [[ -d "$confdir" ]]; then
	if ! mkdir -p "$confdir"; then
		echo "warning: cannot create $confdir. defaulting to /tmp"
		confdir="/tmp"
	fi
fi
confile="$confdir/screensaver.conf"  # the config file, for storing configuration
logfile="$confdir/screensaver.log"  # the log file

if [[ ! -f "$logfile" ]]; then
	touch "$logfile"
elif [[ $(stat -c %s "$logfile") -gt "10240" ]]; then  # limit log file's max size to 10KB
	sed -i "1,$(($(wc -l "$logfile" | awk '{print $1}') - 200)) d" "$logfile"  # keep the last 200 lines
fi

if [[ -f "$confile" ]]; then
	read_confile  # read config file
else  # initialize config file
	echo "Config file does not exist, creating new one" | tee -a "$logfile"
	echo -e "# this is the 'Screen Saver' configuration file\n" >> "$confile"
	echo "# you can edit this file manually or use '$appname -c' to launch a small" >> "$confile"
	echo -e "# configuration utility.\n" >> "$confile"
	pics_dir="$HOME/pictures"
	recursive="true"
	randomize="true"
	slideshow_interval="5"
	idle_wait="420000"
	echo "pics_dir = $pics_dir" >> "$confile"
	echo "recursive = $recursive" >> "$confile"
	echo "randomize = $randomize" >> "$confile"
	echo "idle_wait = $idle_wait" >> "$confile"
	echo "slideshow_interval = $slideshow_interval" >> "$confile"
fi

case $action in
	start )			start_screensaver ;;
	conf )			screensaver_config ;;
	background )	background ;;
esac
