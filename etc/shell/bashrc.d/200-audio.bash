us_probe_audio() {
    # Skip if pactl isn't installed or no PulseAudio/PipeWire daemon is running
    command -v pactl >/dev/null 2>&1 || return 0
    pactl info >/dev/null 2>&1 || return 0

    declare -gA us_pa_sinks=()
    declare -g  us_pa_default=""

    us_pa_default=$(pactl get-default-sink 2>/dev/null)

    # Read sinks: id, name, driver, spec, state
    local id name driver spec state
    while read -r id name driver spec state; do
        [ -z "$name" ] && continue
        us_pa_sinks["$name"]="$state|$driver|$spec"
    done < <(pactl list sinks short 2>/dev/null)

    # Print login summary matching your network block
    if [ -n "$us_pa_default" ] && [ -n "${us_pa_sinks[$us_pa_default]}" ]; then
        IFS='|' read -r state driver _ <<< "${us_pa_sinks[$us_pa_default]}"
        local icon="  "
        [[ "$driver" == *"tunnel"* ]] && icon="  "
        
        if [[ "$state" == "RUNNING" || "$state" == "IDLE" ]]; then
            echo "  [+] $state $icon sink — $us_pa_default ($driver)"
        else
            echo "  [-] $state $icon sink — $us_pa_default ($driver)"
        fi
    else
        echo "  [-] OFF    sink — no default audio route"
    fi
}
