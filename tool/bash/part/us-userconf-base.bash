us_userconf_ctx() {
	us_userconf_envdef
	us_userconf_loadbash ${HOST} ||
	us_userconf_loadbash host

	if [[ ! -d ${UCONF} ]]; then
		UCONF=$HOME/.conf
		if [[ ! -d ${UCONF} ]]; then
			>&2 echo "    [x] UCONF does not exist: ${UCONF@Q}"
			return 1
		else
			>&2 echo "    [-] UCONF not configured, using ${UCONF@Q}"
		fi
	fi

	PATH+=:${UCONF:?}/tool/bash/exec
	US_PATH=${UCONF:?}/tool/bash/part
	export PATH US_PATH
}

us_userconf_envdef() {
	: "${HOSTNAME:=$(hostname -s)}"
	: "${HOST:=$(hostname -f)}"
	: "${SRC_ROOT:=/src}"
	: "${SRV_ROOT:=/srv}"
	: "${VOLID:=local}"

	: "${HOME:=/home/${USER:?No user for session?}}"
	: "${HOME_LOCAL:=${SRV_ROOT}/home-${VOLID:?}}"
	: "${UCONF:=${HOME_LOCAL}/.conf}"
}

us_userconf_loadbash() {
	local conf="/etc/userconf/${1:-host}.conf"
	[ -r "$conf" ] && \builtin . "$conf"
}
