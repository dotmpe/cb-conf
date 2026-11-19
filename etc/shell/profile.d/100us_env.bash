. "${UCONF:-$HOME/.local/share/dotfiles}/tool/bash/part/us-userconf-base.bash"

us_userconf_ctx

us_loadbash() {
	local us_lb
	local -n _us_path=US_PATH

	for us_lb; do
		PATH=$_us_path \builtin . "$us_lb" || return
	done
}

declare -gA us_session_data=()

echo "  [$HOSTNAME]" $(uptime)

if [[ ${SSH_CONNECTION:+set} ]]; then
	if [[ ${DISPLAY:+set} ]]; then
		echo "    [-] Display $DISPLAY forwarded for ${SSH_CLIENT%% *}"
	fi
fi

bt_status() {
    # Check if radio is blocked at kernel level
    if rfkill -n -o TYPE,SOFT,HARD | grep -q "bluetooth.*blocked"; then
        echo "    [/] OFF    bt/ble — rfkill blocked"
        return
    fi

    # Check if BlueZ controller is powered on
    if bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then
        local devs
        devs=$(bluetoothctl devices Connected | cut -d' ' -f3- | paste -sd ", " -)
        if [ -n "$devs" ]; then
            echo "    [+] ON     bt/ble CONN $devs"
        else
            echo "    [+] ON     bt/ble idle"
        fi
    else
        echo "    [/] OFF    bt/ble powered down"
    fi
}

SYS_BT_POWER=$(bluetoothctl show 2>/dev/null | awk '/Powered:/ {print $2}')
SYS_BT_DEVS=$(bluetoothctl devices Connected | cut -d' ' -f3- | paste -sd "," -)
cat <<EOF > "/run/user/$UID/sysinfo.env"
SYS_BT_POWER="${SYS_BT_POWER:-no}"
SYS_BT_DEVS="${SYS_BT_DEVS}"
EOF


