us_net_ctx() {
	declare -gn us_nets='us_session_data[net_con]'

	declare -gA us_net_link=()
	declare -gA us_net_addr=()

	declare -gn net_ipv4='us_net_addr["$iface:inet:ipv4"]'
	declare -gn net_ipv6='us_net_addr["$iface:inet:ipv6"]'
}

us_net_upshow() {
	echo "nets-up: 
    ${us_nets//$'\n'/$'\n    '}"
}

us_net_links_ctx(){
	while read -r num name ip_show_rest; do
	  us_net_link[${name%:}]=$up_show_rest
	done <<< "${us_nets//$'\n    '/ }"
}

# Unicode glyphs:
# Checkmark (Heavy): ✔	✘	U+2714 / U+2718
# Checkmark (Light): ✓	✗	U+2713 / U+2717
# Generic null: ∅	(U+2205, Empty Set) 
gl_null='∅'
# Generic null: —	(U+2014, Em Dash)
gl_em='—'
#

us_net_ctx
us_nets=$(ip link show)
#us_net_upshow
us_net_links_ctx

for iface in "${!us_net_link[@]}"; do
	net_ipv4=$(ip -4 addr show "$iface")
	net_ipv6=$(ip -6 addr show "$iface")

	# FIXME: match whole addr in extraction, use parts later?
	ipv4_suf=$(<<< "$net_ipv4" grep -oP '(?<=inet\s)\d+\.\d+\.\d+\K\.\d+')
	ipv6_suf=$(<<< "$net_ipv6" grep -oP '(?<=inet6\s)[0-9a-f:]+:[0-9a-f]:\K[0-9a-f]+(?=/)' | head -n 1)

	if [[ ${ipv4_suf:+set} || ${ipv6_suf:+set} ]]; then
		echo "    [+] UP 󰛳 inet 󰈀 ${ipv4_suf:-$gl_em} ${ipv6_suf:-$gl_em} via $iface"
	fi
done
