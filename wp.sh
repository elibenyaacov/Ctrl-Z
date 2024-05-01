#!/bin/bash

## Change wallpapers on a schedule or by demand
##
## Author: eli ben ya'acov
##
## 3rd party apps: feh/nitrogen; yad; xrandr; xdg-open
##
## To-do: high cpu when wallpapers' directory not found or empty; recode all config system (and add option for separate_configs)

appname=$(basename $0)

function usage {
	echo
	echo "Wallpaper changer"
	echo
	echo "usage: $appname [ -l [filename] | -n | -p | -r | -o | -e | -s | -i | -c | -h ]"
	echo
	echo -e "  -l\t\t- set specified/random wallpaper"
	echo -e "  -n\t\t- next wallpaper"
	echo -e "  -p\t\t- previous wallpaper"
	echo -e "  -r\t\t- reload wallpaper"
	echo -e "  -o\t\t- open wallpaper in viewer"
	echo -e "  -e\t\t- edit wallpaper in editor"
	echo -e "  -s\t\t- backgroud mode - run in background and change wallpapers periodically (\e[4mdefault\e[0m)"
	echo -e "  -i\t\t- show wallpaper information"
	echo -e "  -c\t\t- change settings (config file: \e[3m~/.config/wpchanger/wp.conf\e[0m)"
	echo -e "  -h | --help\t- display help"
	echo
	echo -e "running \e[3m$appname\e[0m without any arguments will start in backgroud mode"
}

sleeptime=15
if [[ -z "$1" ]]; then
	action='backgroud'
else
	while [[ "$1" != "" ]]; do
		case "$1" in
			-h | --help )	usage; exit ;;
			-l )			action="new"
							imgFile="$2"
							shift
							;;
			-n )			action='next' ;;
			-p )			action='previous' ;;
			-r )			action='reload' ;;
			-o )			action='open' ;;
			-e )			action='edit' ;;
			-s )			action='backgroud' ;;
			-i )			action='info' ;;
			-c )			action='conf' ;;
			--noini | --no-ini)	noini="true" ;;
			--nomsg | --no-msg)	nomsg="true" ;;
			--fork )		sleep 10 ;;
			--test )		sleeptime=3 ;;
			* )			usage
							exit 1
							;;
		esac
		shift
	done
fi

if [[ "$imgFile" ]]; then
	if [[ ! -f "$imgFile" ]]; then  # if filename was specified on the command-line but no such file exist
		echo "Error: file not found: $imgFile"
		exit 1
	else
		imgFile=$(realpath "$imgFile")  # absolute pathname of the file
	fi
fi

# -- functions ----------------------------------------------------------------

function background_mode {  # -- background run ---------------------------
	if ! mkdir "$lockdir" 2> /dev/null; then  # can't establish a lock
		echo "error: wpchanger already running in background" | tee -a "$logfile"
		exit 1
	fi
	trap 'rm -fr "$lockdir"; exit' SIGINT SIGTERM SIGQUIT ERR EXIT  # delete lockdir on script exit

	echo -e "\n$(date '+%a %Y-%m-%d %k:%M:%S')\n$separator" >> "$logfile"
	echo "Wallpaper Changer Started (backgroud mode)" | tee -a "$logfile"
	[[ "$cwp" ]] && reload_wallpaper || new_wallpaper  # if ini file is empty load new wallpaper
# make a retry (only here) every 1+ minutes in case of network failure

	script_time=$(stat -c "%Y" "$0")  # modification time of this script (for checking real time changes of script)
	config_time=$(stat --format=%Y "$conFile")  # modification time of current config file
	counter=0  # counter till time for wallpaper change

	echo "Sleeping for $sleeptime/$slideshow_interval seconds..."
	while true; do  # enter backgroud mode
		sleep $sleeptime

		new_script_time=$(stat -c "%Y" "$0")  # check for script changes (on disk)
		if [[ "$new_script_time" != "$script_time" ]]; then  # script changed. fork
			echo "[$(date '+%Y-%m-%d %k:%M:%S')]: Script changed on disk, launching new instance..." | tee -a "$logfile"
			bash -c "exec $0 -s --fork" &  # launch a new instance of this script and exit this one
			echo -e "Exiting\n\n" | tee -a "$logfile"
			exit
		fi

		new_config_time=$(stat --format=%Y "$conFile")  # check for config file changes
		old_workspace="$workspace"  # check for workspace change

		if [[ "$new_config_time" != "$config_time" ]]; then  # config file changed, reload config
			echo "[$(date '+%Y-%m-%d %k:%M:%S')]: Config changed, reloading config..." | tee -a "$logfile"
			config_time="$new_config_time"
			old_wallpapers_dir="$wallpapers_dir"
			old_recursive="$recursive"
			read_IniFile
			read_ConfigFile
			if [[ "$old_wallpapers_dir" != "$wallpapers_dir" || "$old_recursive" != "$recursive" ]]; then
				counter="$slideshow_interval"  # time to change wallpaper
			fi
		fi

		get_WorkspaceName
		if [[ "$old_workspace" != "$workspace" ]]; then  # workspace changed
			echo "[$(date '+%Y-%m-%d %k:%M:%S')]: Workspace changed, reloading wallpaper..." | tee -a "$logfile"
			read_IniFile
			read_ConfigFile
			if [[ "$cwp" ]]; then
				[[ "$enabled" == "true" ]] && reload_wallpaper
			else
				counter="$slideshow_interval"  # time to change wallpaper
			fi
		fi

		counter=$((counter + $sleeptime))
		echo "Slept $counter/$slideshow_interval seconds"
		if [[ "$counter" -ge "$slideshow_interval" ]]; then  # time to change wallpaper
			if [[ "$enabled" == "true" ]]; then
				if [[ -d "$wallpapers_dir" ]]; then
					echo -n "[$(date '+%Y-%m-%d %k:%M:%S')]: " >> "$logfile"
					echo "Timeout reached, searching for a new wallpaper..." | tee -a "$logfile"
					unset imgFile
					new_wallpaper
					counter=0
				else
					echo "Error: directory '$wallpapers_dir' not found" | tee -a "$logfile"
				fi
			else
				echo "Screensaver is disabled. not invoking" | tee -a "$logfile"
			fi
		fi
	done
}

function get_WorkspaceName {  # get workspace/activity name
	[[ -f "$conFile" ]] && separate_configs=$(~/bin/confrw.sh common separate_configs "$conFile")
	if [[ "$separate_configs" == "true" ]]; then  # separate configs for each workspace/activity
		wm=$($HOME/bin/getosinfo.sh -s --wm | tr '[:upper:]' '[:lower:]')  # get the window manager
		case "$wm" in
			kwin )  # kde
				i=$(qdbus org.kde.ActivityManager /ActivityManager/Activities CurrentActivity)
				workspace=$(qdbus org.kde.ActivityManager /ActivityManager/Activities ActivityName $i)
				;;
			xfwm* )  # xfce
				workspace=$(wmctrl -d | grep '*' | awk -F " " '{print $NF}')
				;;
		esac
		if [[ ! "$workspace" ]]; then  # no workspaces/activities
			workspace="default"
		fi
	else  # configs are same for all workspaces/activities
		workspace="default"
	fi
	workspace=${workspace,,}
}

function read_ConfigFile {
	start_on_boot=$(~/bin/confrw.sh common start_on_boot "$conFile")
	separate_configs=$(~/bin/confrw.sh common separate_configs "$conFile")
	viewer=$(~/bin/confrw.sh common viewer "$conFile")
	viewer_app=$(~/bin/confrw.sh common viewer_app "$conFile")
	editor=$(~/bin/confrw.sh common editor "$conFile")
	editor_app=$(~/bin/confrw.sh common editor_app "$conFile")

	get_WorkspaceName
	if grep -q "^\[$workspace\]$" "$conFile"; then  # read workspace related options
		enabled=$(~/bin/confrw.sh "$workspace" enabled "$conFile")
		wallpapers_dir=$(~/bin/confrw.sh "$workspace" wallpapers_dir "$conFile")
		recursive=$(~/bin/confrw.sh "$workspace" recursive "$conFile")
		slideshow_interval=$(~/bin/confrw.sh "$workspace" slideshow_interval "$conFile")
		history_size=$(~/bin/confrw.sh "$workspace" history_size "$conFile")
	else  # no matching section for current workspace in config file, manually set options
		enabled="true"
		wallpapers_dir="$HOME/pictures"
		recursive="false"
		slideshow_interval="3600"
		history_size="100"
		write_ConfigFile
	fi
}

function write_ConfigFile {
	~/bin/confrw.sh common start_on_boot "$start_on_boot" "$conFile"
	~/bin/confrw.sh common separate_configs "$separate_configs" "$conFile"
	~/bin/confrw.sh common viewer "$viewer" "$conFile"
	~/bin/confrw.sh common viewer_app "$viewer_app" "$conFile"
	~/bin/confrw.sh common editor "$editor" "$conFile"
	~/bin/confrw.sh common editor_app "$editor_app" "$conFile"

	if [[ "$workspace" ]]; then
		~/bin/confrw.sh "$workspace" enabled "$enabled" "$conFile"
		~/bin/confrw.sh "$workspace" wallpapers_dir "$wallpapers_dir" "$conFile"
		~/bin/confrw.sh "$workspace" recursive "$recursive" "$conFile"
		~/bin/confrw.sh "$workspace" slideshow_interval "$slideshow_interval" "$conFile"
		~/bin/confrw.sh "$workspace" history_size "$history_size" "$conFile"
	fi
}

function read_IniFile {
	get_WorkspaceName
	cwp=$(~/bin/confrw.sh "$workspace" current_wallpaper "$iniFile")  # current wallpaper
	lwp=$(~/bin/confrw.sh "$workspace" last_wallpaper "$iniFile")  # last wallpaper (while going next/prev wallpaper)
}

function new_wallpaper {  # pick a new wallpaper
	[[ "$action" != "backgroud" ]] && echo -n "[$(date '+%a %Y-%m-%d %k:%M:%S')]: " >> "$logfile"
	[[ "$recursive" == "false" ]] && maxdepth="-maxdepth 1" || unset maxdepth
	if [[ -z "$imgFile" && -d "$wallpapers_dir" ]]; then  # an image file was not specified (and valid wallpapers directory)
		imgFile=$(find -L "$wallpapers_dir/" $maxdepth -path '*/os/*' -prune -o -type f -iname "*.jp[eg]*" \
		-print -or -iname "*.png" -print -or -iname "*.jfif" -print -or -iname "*.webp" -print | shuf -n 1)
	fi
	if [[ -f "$imgFile" ]]; then
		echo "Setting new wallpaper: '$imgFile'" | tee -a "$logfile"

		if set_wallpaper; then  # setting wallpaper succeeded
			echo "Wallpaper set successfully" | tee -a "$logfile"
			((cwp++))
			[[ "$cwp" -gt "$history_size" ]] && cwp=1  # reached end of history list
			~/bin/confrw.sh "$workspace" current_wallpaper "$cwp" "$iniFile"
			~/bin/confrw.sh "$workspace" last_wallpaper "$cwp" "$iniFile"
			~/bin/confrw.sh "$workspace" "$cwp" "'$imgFile'" "$iniFile"
		else
			echo "failed (:$exitCode)" | tee -a "$logfile"  # setting wallpaper failed
		fi
	else
		if [[ "$imgFile" ]]; then
			echo "Error: Can't find '$imgFile'" | tee -a "$logfile"
		else
			echo "Error: Can't find any images at '$wallpapers_dir'" | tee -a "$logfile"
		fi
	fi
}

function set_wallpaper {  # set the wallpaper on screen
	if [[ ! -f "$imgFile" ]]; then  # in case file was deleted or not found
		echo "Error: file not found: '$imgFile'" | tee -a "$logfile"
		return 1
	elif [[ $(type -p identify) ]]; then
		if ! identify "$imgFile" &>/dev/null; then
			echo "Warning: file is not a valid image file"
		fi
	fi
	wm=$($HOME/bin/getosinfo.sh -s --wm | tr '[:upper:]' '[:lower:]')  # get the window manager
	echo "Window Manager: $wm" | tee -a "$logfile"
	case "$wm" in
		kwin )  # kde
			echo "Activity: $workspace" | tee -a "$logfile"
			# get current activity ID
			activity=$(qdbus org.kde.ActivityManager /ActivityManager/Activities \
					org.kde.ActivityManager.Activities.CurrentActivity)
			if [[ "$activity" ]]; then
				exitCode=$(qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
					var actId = '$activity';
//					var scr = $screen;
					var scr = 0;
					var ds = desktops(); // load the containments
					for (let d of ds) { // and walk through them
						// skip any containment that does not match activity and screen
						if (d.readConfig('activityId') != actId || d.readConfig('lastScreen') != scr) continue;
						// prepare to read the General configuration (where plugins normally put the current image)
						d.currentConfigGroup = Array('Wallpaper',d.wallpaperPlugin,'General');
						// identify the wallpaper plugin so we can read/write it properly
						if (d.wallpaperPlugin == 'org.kde.image') { // THIS ONE GIVE RESULTS
							print(d.writeConfig('Image', 'file:///$imgFile'));
						}
						else if (d.wallpaperPlugin == 'org.kde.slideshow') {
							print(d.writeConfig('Image', 'file:///$imgFile'));
						}
						else {
							print('Unsupported wallpaper plugin: '+d.wallpaperPlugin+'\n');
						}
						break;
					}")
				exitCode="$?"
			else
				echo "Error: Activity for '$workspace' was not found" | tee -a "$logfile"
			fi
			;;
		'gnome shell' )  # gnome
			gsettings set org.gnome.desktop.background picture-uri "$imgFile"
			exitCode="$?"
			;;
		metacity* )  # mate
			gsettings set org.mate.background picture-filename "$imgFile"
			exitCode="$?"
			;;
		xfwm* )  # xfce
			m='monitor'$(xrandr --listactivemonitors | tail -n +2 | grep '+*' | tr -s ' ' | cut -d ' ' -f 5)
			w='workspace'$(wmctrl -d | grep "*" | cut -d ' ' -f 1)
			echo -e "Workspace: $workspace" | tee -a "$logfile"
			xfconf-query -c xfce4-desktop -p "/backdrop/screen0/$m/$w/last-image" -s "$imgFile"
			exitCode="$?"
			;;
		* )  # mutter/openbox
			unset exitCode
			for app in "${wpapps[@]}"; do
				echo "trying with: $app $imgFile" | tee -a "$logfile"
				$app "$imgFile" | tee -a "$logfile"
				exitCode="$?"
				[[ "$exitCode" == "0" ]] && break
			done
			;;
	esac
	if [[ "$action" != "backgroud" && "$nomsg" != "true" ]]; then
		~/bin/display-image-properties.sh "$imgFile"  # error: notify-send errors on filenames with spaces
	fi
	if [[ $exitCode =~ ^[0-9]+$ ]]; then  # if exitCode is a number
		return "$exitCode"  # return success or fail
	else
		return 99
	fi
}

function prev_next_wallpaper {  # helper function to prev_wallpaper and next_wallpaper functions
	echo -n "[$(date '+%a %Y-%m-%d %k:%M:%S')]: " >> "$logfile"
	echo "Loading $action wallpaper: '$imgFile'" | tee -a "$logfile"
	if set_wallpaper; then
		echo "Wallpaper set successfully" | tee -a "$logfile"
		~/bin/confrw.sh "$workspace" current_wallpaper "$cwp" "$iniFile"
	else
		echo "failed (:$exitCode)" | tee -a "$logfile"
	fi
}

function prev_wallpaper {  # reload previous wallpaper in history list
	((cwp--))
	[[ "$cwp" == "0" ]] && cwp="$history_size"
	imgFile=$(~/bin/confrw.sh "$workspace" "$cwp" "$iniFile")
	if [[ "$cwp" != "$lwp" && "$imgFile" ]]; then
		prev_next_wallpaper
	else
		echo "No more files in the list"
	fi
}

function next_wallpaper {  # reload next wallpaper in history list
	if [[ "$cwp" != "$lwp" ]]; then
		((cwp++))
		[[ "$cwp" -gt "$history_size" ]] && cwp=1
		imgFile=$(~/bin/confrw.sh "$workspace" "$cwp" "$iniFile")
		prev_next_wallpaper
	else
		echo "No more files in the list"
	fi
}

function reload_wallpaper {  # reload current wallpaper
	[[ "$action" != "backgroud" ]] && echo -n "[$(date '+%a %Y-%m-%d %k:%M:%S')]: " >> "$logfile"
	imgFile=$(~/bin/confrw.sh "$workspace" "$cwp" "$iniFile")
	echo "Reloading current wallpaper: '$imgFile'" | tee -a "$logfile"
	if set_wallpaper; then
		echo "Wallpaper reloaded successfully" | tee -a "$logfile"
	else
		echo "failed (:$exitCode)" | tee -a "$logfile"
	fi
}

function open_wallpaper {  # open current wallpaper in viewer app
	echo -n "[$(date '+%a %Y-%m-%d %k:%M:%S')]: " >> "$logfile"
	imgFile=$(~/bin/confrw.sh "$workspace" "$cwp" "$iniFile")
	echo "Opening current wallpaper: '$imgFile'" | tee -a "$logfile"
	echo "Viewer app: '$viewer_app'"
	[[ "$viewer" == "true" ]] && "$viewer_app" "$imgFile" || xdg-open "$imgFile"
}

function edit_wallpaper {  # open current wallpaper in editor app
	echo -n "[$(date '+%a %Y-%m-%d %k:%M:%S')]: " >> "$logfile"
	imgFile=$(~/bin/confrw.sh "$workspace" "$cwp" "$iniFile")
	echo "Editing current wallpaper: '$imgFile'" | tee -a "$logfile"
	echo "Editor app: '$editor_app'"
	[[ "$editor" == "true" ]] && "$editor_app" "$imgFile" || xdg-open "$imgFile"
}

function wallpaper_info {  # show information about current wallpaper
	imgFile=$(~/bin/confrw.sh "$workspace" "$cwp" "$iniFile")
	$HOME/bin/display-image-properties.sh "$imgFile"
}

function wp_config {  # dialog box for setting options
	prev_start_on_boot="$start_on_boot"
	mm=$((slideshow_interval / 60))
	val=$(yad --form --title "WallpaperChanger - Settings" --bool-fmt=t --center --borders=10 \
		--window-icon=settings-configure --geometry=550x725 \
		--field="[ Common Options ]":lbl "" \
		--field="------------------------------------":lbl "@disabled@" \
		--field="Start On Boot":chk "$start_on_boot" \
		--field="Separate Profiles"!"Use separate config files for each workspace/desktop/activity (please change manually)":chk "@disabled@" \
		--field="Image Viewer"!"Uncheck to use system default":chk "$viewer" \
		--field=:fl "$viewer_app" \
		--field="Image Editor"!"Uncheck to use system default":chk "$editor" \
		--field=:fl "$editor_app" \
		--field="":btn "@disabled@" \
		--field="[ Current Workspace: $workspace ]":lbl "" \
		--field="------------------------------------":lbl "@disabled@" \
		--field="Enabled":chk "$enabled" \
		--field="Pictures Directory: ":dir "$wallpapers_dir" \
		--field="Recursive":chk "$recursive" \
		--field="Change Wallpaper Every (Minutes): ":num "$mm!1..1440" \
		--field="History Size: ":num "$history_size!1..100")
	x="$?"
	if [[ "$x" == "0" ]]; then
		start_on_boot=$(echo "$val" | cut -d '|' -f 3)
#		separate_configs=$(echo "$val" | cut -d '|' -f 4)  # DO NO ENABLE THIS!!!
		viewer=$(echo "$val" | cut -d '|' -f 5)
		viewer_app=$(echo "$val" | cut -d '|' -f 6)
		editor=$(echo "$val" | cut -d '|' -f 7)
		editor_app=$(echo "$val" | cut -d '|' -f 8)
		enabled=$(echo "$val" | cut -d '|' -f 12)
		wallpapers_dir=$(echo "$val" | cut -d '|' -f 13)
		recursive=$(echo "$val" | cut -d '|' -f 14)
		mm=$(echo "$val" | cut -d '|' -f 15)
		slideshow_interval=$((mm * 60))
		history_size=$(echo "$val" | cut -d '|' -f 16)
		write_ConfigFile
		if [[ "$start_on_boot" != "$prev_start_on_boot" ]]; then
			if [[ "$start_on_boot" == "false" ]]; then
				if [[ -f "$HOME/.config/autostart/wp.desktop" ]]; then
					mv -vf "$HOME/.config/autostart/wp.desktop" "$HOME/.config/autostart/disabled/" | tee -a "$logfile"
				fi
			else  # enable on boot
				if [[ -f "$HOME/.config/autostart/disabled/wp.desktop" ]]; then
					mv -vf "$HOME/.config/autostart/disabled/wp.desktop" "$HOME/.config/autostart/wp.desktop" | tee -a "$logfile"
				elif [[ -f "/mnt/home/$USER/.config/autostart/wp.desktop" ]]; then
					ln -sv "/mnt/home/$USER/.config/autostart/wp.desktop" "$HOME/.config/autostart/wp.desktop" | tee -a "$logfile"
				else
					~/bin/confrw.sh 'Desktop Entry' Exec "/bin/sh -c '/usr/bin/rmdir /var/tmp/wpchanger.lock; exec /home/eli/bin/wp.sh 1>/tmp/wpchanger.log 2>&1'" "$HOME/.config/autostart/wp.desktop"
					~/bin/confrw.sh 'Desktop Entry' Icon dialog-scripts "$HOME/.config/autostart/wp.desktop"
					~/bin/confrw.sh 'Desktop Entry' Name WallpaperChanger "$HOME/.config/autostart/wp.desktop"
					~/bin/confrw.sh 'Desktop Entry' Type Application "$HOME/.config/autostart/wp.desktop"
					~/bin/confrw.sh 'Desktop Entry' X-KDE-AutostartScript false "$HOME/.config/autostart/wp.desktop"
				fi
			fi
		fi
	fi
}

function debug {
echo -e "\n--------------"
echo "iniFile:  $iniFile"
echo "conFile:  $conFile"
echo
echo "Start on Boot:  $start_on_boot"
echo "Separate Configs:  $separate_configs"
echo "Viewer:  $viewer"
echo "Viewer App:  $viewer_app"
echo "Edior:  $editor"
echo "Editor App:  $editor_app"
echo
echo "Workspace Name:  $workspace"
echo
echo "ScreenSaver enabled:  $enabled"
echo "Directory:  $wallpapers_dir"
echo "Recuresive:  $recursive"
echo "Interval:  $slideshow_interval"
echo "History:  $history_size"
echo
echo "Current Wallpapaer:  $cwp"
echo "Last Wallpaper:  $lwp"
echo "Wallpaper File:  $imgFile"
echo
}

# -----------------------------------------------------------------------------
#  start of script
# -----------------------------------------------------------------------------

separator="--------- -------- ------- ------ ----- ---- --- -- -"

lockdir="/var/tmp/wpchanger.lock"  # lock mechanism to insure only one instance is running
confdir="$HOME/.config/wpchanger"

if [[ -d "$confdir" ]]; then
	if ! mkdir -p "$confdir"; then
		echo "warning: cannot create $confdir. defaulting to /tmp"
		confdir="/tmp"
	fi
fi

logfile="$confdir/wp.log"  # the log file
iniFile="$confdir/wp.ini"  # the ini file, for storing current image and history list
conFile="$confdir/wp.conf"  # the config file, for storing configuration

if [[ ! -f "$logfile" ]]; then
	touch "$logfile"
elif [[ $(stat -c %s "$logfile") -gt "10240" ]]; then  # limit log file's max size to 10KB
	sed -i "1,$(($(wc -l "$logfile" | awk '{print $1}') - 200)) d" "$logfile"  # keep the last 200 lines
fi

if [[ ! -f "$conFile" ]]; then  # no config file, manually set options and initialize a config file (only 1st part)
	echo "Config file '$conFile' does not exist, creating new one" | tee -a "$logfile"
	echo "# this is the 'wallpaper changer' configuration file" >> "$conFile"
	echo "# you can edit this file manually or use '$appname -c' to launch a small" >> "$conFile"
	echo -e "# configuration utility.\n" >> "$conFile"
	start_on_boot="true"
	separate_configs="false"
	viewer="false"
	viewer_app="/usr/bin/gwenview"
	editor="true"
	editor_app="/usr/bin/gimp"
	write_ConfigFile
	workspace="default"
fi
read_ConfigFile  # read config file or (if no config file) write 2nd part (workspace related) of options in config file

if [[ "$noini" == "true" ]]; then
	iniFile="/tmp/wp.ini"
elif [[ ! -f "$iniFile" ]]; then  # initialize ini file
	get_WorkspaceName
	echo "Ini file '$iniFile' does not exist, creating new one" | tee -a "$logfile"
	echo -e "[$workspace]\ncurrent_wallpaper = \nlast_wallpaper = \n" >> "$iniFile"
	chmod 600 "$iniFile"
else
	read_IniFile
fi

#debug; exit

declare -a wpapps=(  # apps used to set the desktop background
	"nitrogen --set-zoom-fill"
	"feh --no-fehbg --bg-fill"
)

case $action in
	new )			new_wallpaper ;;
	next )		[[ "$cwp" ]] && next_wallpaper ;;
	previous )	[[ "$cwp" ]] && prev_wallpaper ;;
	reload )		[[ "$cwp" ]] && reload_wallpaper ;;
	open )		[[ "$cwp" ]] && open_wallpaper ;;
	edit )		[[ "$cwp" ]] && edit_wallpaper ;;
	info )		[[ "$cwp" ]] && wallpaper_info ;;
	conf )		wp_config ;;
	backgroud )	background_mode ;;
esac
