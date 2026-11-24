: env "${_f1:=$(tput setaf 1 2>/dev/null)}"
: env "${_f3:=$(tput setaf 3 2>/dev/null)}"
: env "${NORMAL:=$(tput sgr0 2>/dev/null)}"
python -m http.server &
srvpid=$!
stat=0
qemu-system-x86_64 ... || stat=$?

kill -9 ${srvpid-} || >&2 echo "${_f3-}E$? closing python http server (ignored)${NORMAL-}"
! ((stat)) || >&2 echo "${_f1-}QEMU returned E$?${NORMAL-}"
exit ${stat-}

# Id: run-template                               vim:set ft=bash sw=2 sts=2 et:
