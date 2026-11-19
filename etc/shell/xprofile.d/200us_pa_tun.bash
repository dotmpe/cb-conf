userscript::pulseaudio::us_init_pa_tunnel() {
    local conf="/etc/userconf/audio.conf"
    [ -r "$conf" ] && source "$conf"

    [ "${PA_TUNNEL_ENABLED:-0}" -eq 1 ] || return 0
    pactl info >/dev/null 2>&1 || return 1

    # Load the tunnel module only if the sink isn't already registered
    if ! pactl list sinks short | awk '{print $2}' | grep -qx "$PA_TUNNEL_SINK"; then
        pactl load-module module-tunnel-sink \
            server="$PA_TUNNEL_SERVER" \
            sink_name="$PA_TUNNEL_SINK" >/dev/null
    fi

    # Set it as default
    pactl set-default-sink "$PA_TUNNEL_SINK"
}
