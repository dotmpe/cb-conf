# QEMU Virtual Machine Functional Abstraction
#
# Provides functional abstractions for configuring, disk-managing,
# and executing QEMU virtual machines.
#
# Package: qemu_vm::*
#
# Copyright B. van Berkum 2026 <berend@dotmpe.com>
# Distributed under terms of the MIT license.
#shellcheck disable=2178  # variable is a by-name reference to array

# ----------------------------------------------------------------------
# 1. Host Capabilities & Disk/Image Management (qemu-img)
# ----------------------------------------------------------------------

qemu_vm::has_kvm() {
  [[ -r /dev/kvm && -w /dev/kvm ]]
}

qemu_vm::disk_create() {
  local disk=${1:?disk path required}
  local size=${2:?disk size required (e.g. 20G)}
  local fmt=${3:-qcow2}

  if [[ ! -s "$disk" ]]; then
    qemu-img create -f "$fmt" "$disk" "$size" &&
    std_info "Created disk ${disk@Q}" ||
      failerr "E$? while creating ${disk@Q}" || return
  fi
}

qemu_vm::disk_resize() {
  local disk=${1:?disk path required}
  local size=${2:?new size required (e.g. 20G)}

  qemu-img resize "$disk" "$size" &&
  std_info "Resized disk ${disk@Q}"
}

qemu_vm::disk_overlay() {
  local backing=${1:?backing image required}
  local overlay=${2:?overlay disk path required}
  local size=${3-}
  local backing_fmt=${4:-qcow2}

  [[ -s "$backing" ]] ||
    failerr "qemu_vm::disk_overlay: backing file not found: $backing" || return

  qemu-img create -f qcow2 -b "$backing" -F "$backing_fmt" "$overlay" || return
  [[ -z "$size" ]] ||
    qemu-img resize "$overlay" "$size" ||
      failerr "qemu_vm::disk_overlay: failed to resize ${overlay@Q}"
}

qemu_vm::disk_info() {
  local disk=${1:?disk path required}
  qemu-img info "$disk"
}

# ----------------------------------------------------------------------
# 2. VM Command Builder (Functional Nameref Abstraction)
# ----------------------------------------------------------------------

qemu_vm::init() {
  local -n _cmd_ref=${1:?command array variable name required}
  local arch=${2:-x86_64}
  local qemu_bin="qemu-system-${arch}"

  if ! \builtin command -v "$qemu_bin" >/dev/null 2>&1; then
    >&2 echo "qemu_vm::init: binary not found in PATH: $qemu_bin"
    return 1
  fi

  _cmd_ref=( "$qemu_bin" )
}

qemu_vm::accel() {
  local -n _cmd_ref=${1:?cmd array required}
  local mode=${2:-auto}

  case "$mode" in
    ( kvm ) _cmd_ref+=( -enable-kvm ) ;;
    ( tcg ) _cmd_ref+=( -accel tcg ) ;;
    ( auto )
        if qemu_vm::has_kvm; then
          _cmd_ref+=( -enable-kvm )
        else
          _cmd_ref+=( -accel tcg )
        fi
      ;;
    ( * )
      >&2 echo "qemu_vm::accel: unknown accel mode '$mode' (expected kvm|tcg|auto)"
      return 1
  esac
}

qemu_vm::cpu() {
  local -n _cmd_ref=${1:?cmd array required}
  local cores=${2:-2}
  local cpu_model=${3:-}

  _cmd_ref+=( -smp "${cores}" )
  if [[ -n "$cpu_model" ]]; then
    _cmd_ref+=( -cpu "$cpu_model" )
  elif qemu_vm::has_kvm; then
    _cmd_ref+=( -cpu host )
  else
    _cmd_ref+=( -cpu max )
  fi
}

qemu_vm::memory() {
  local -n _cmd_ref=${1:?cmd array required}
  local size=${2:-2G}

  _cmd_ref+=( -m "$size" )
}

qemu_vm::add_drive() {
  local -n _cmd_ref=${1:?cmd array required}
  local file=${2:?drive file required}
  local fmt=${3:-qcow2}
  local iface=${4:-virtio}
  local extra_opts=${5:-}

  local opt="file=$file,format=$fmt,if=$iface"
  if [[ -n "$extra_opts" ]]; then
    opt="${opt},${extra_opts}"
  fi
  _cmd_ref+=( -drive "$opt" )
}

qemu_vm::add_cdrom() {
  local -n _cmd_ref=${1:?cmd array required}
  local iso_file=${2:?iso file path required}
  local boot_cdrom=${3:-0}

  _cmd_ref+=( -cdrom "$iso_file" )
  if ((boot_cdrom)); then
    _cmd_ref+=( -boot d )
  fi
}

qemu_vm::net_user() {
  local -n _cmd_ref=${1:?cmd array required}
  local hostfwd=${2:-} # e.g. "tcp::2222-:22"
  local model=${3:-virtio}
  local mac=${4:-}

  local opt="user,model=$model"
  if [[ -n "$hostfwd" ]]; then
    opt="${opt},hostfwd=$hostfwd"
  fi
  if [[ -n "$mac" ]]; then
    opt="${opt},mac=$mac"
  fi

  _cmd_ref+=( -nic "$opt" )
}

qemu_vm::net_none() {
  local -n _cmd_ref=${1:?cmd array required}
  _cmd_ref+=( -nic none )
}

qemu_vm::_next_fsdev_id() {
  local -n __qvm_fs_cmd=${1:?cmd array required}
  local -n __qvm_out_id=${2:?output variable required}
  local count=0 item

  for item in "${__qvm_fs_cmd[@]}"; do
    if [[ $item =~ id=fsdev([0-9]+) ]]; then
      local idx="${BASH_REMATCH[1]}"
      if ((idx >= count)); then
        count=$((idx + 1))
      fi
    fi
  done
  __qvm_out_id="fsdev${count}"
}

qemu_vm::add_9p() {
  local -n _cmd_ref=${1:?cmd array required}
  local mount_tag=${2:?mount tag required}
  local host_path=${3:?host path required}
  local sec_model=${4:-mapped-xattr}
  local readonly=${5:-0}

  local fs_id
  qemu_vm::_next_fsdev_id "$1" fs_id

  local fsdev_opt="local,id=${fs_id},path=${host_path},security_model=${sec_model}"
  if ((readonly)); then
    fsdev_opt="${fsdev_opt},readonly=on"
  fi

  _cmd_ref+=(
    -fsdev "$fsdev_opt"
    -device "virtio-9p-pci,fsdev=${fs_id},mount_tag=${mount_tag}"
  )
}

qemu_vm::smbios_nocloud() {
  local -n _cmd_ref=${1:?cmd array required}
  local seed_url=${2:?seed url required (e.g. http://10.0.2.2:8003/)}

  _cmd_ref+=( -smbios "type=1,serial=ds=nocloud;s=${seed_url}" )
}

qemu_vm::cidata_drive() {
  local -n _cmd_ref=${1:?cmd array required}
  local cidata_img=${2:?cidata image path required}

  _cmd_ref+=( -drive "file=${cidata_img},format=raw,if=virtio" )
}

qemu_vm::display() {
  local -n _cmd_ref=${1:?cmd array required}
  local disp=${2:-none}  # none|gtk|sdl|vnc|curses
  local vga=${3:-virtio} # virtio|std|none

  case "$disp" in
  ( none) _cmd_ref+=( -display none ) ;;
  ( vnc=*) _cmd_ref+=( -display none -vnc "${disp#vnc=}" ) ;;
  ( gtk|sdl|curses)
        _cmd_ref+=( -display "$disp" )
      ;;
  ( *) _cmd_ref+=( -display "$disp" )
  esac

  if [[ -n "$vga" && "$vga" != "none" ]]; then
    _cmd_ref+=( -vga "$vga" )
  fi
}

qemu_vm::serial() {
  local -n _cmd_ref=${1:?cmd array required}
  local mode=${2:-mon:stdio} # mon:stdio, stdio, null, file:path

  _cmd_ref+=( -serial "$mode" )
}

qemu_vm::kernel_boot() {
  local -n _cmd_ref=${1:?cmd array required}
  local kernel=${2:?kernel path required}
  local initrd=${3:-}
  local cmdline=${4:-}

  _cmd_ref+=( -kernel "$kernel" )
  if [[ -n "$initrd" ]]; then
    _cmd_ref+=( -initrd "$initrd" )
  fi
  if [[ -n "$cmdline" ]]; then
    _cmd_ref+=( -append "$cmdline" )
  fi
}

qemu_vm::ovmf() {
  local -n _cmd_ref=${1:?cmd array required}
  local code_fd=${2:-/usr/share/OVMF/OVMF_CODE.fd}
  local vars_fd=${3:-}

  if [[ -r "$code_fd" ]]; then
    _cmd_ref+=( -drive "if=pflash,format=raw,readonly=on,file=$code_fd" )
  fi
  if [[ -n "$vars_fd" && -r "$vars_fd" ]]; then
    _cmd_ref+=( -drive "if=pflash,format=raw,file=$vars_fd" )
  fi
}

# ----------------------------------------------------------------------
# 3. Execution & Debug Helpers
# ----------------------------------------------------------------------

qemu_vm::dump_cmd() {
  local -n _cmd_ref=${1:?cmd array required}
  printf '%q ' "${_cmd_ref[@]}"
  echo
}

qemu_vm::run() {
  local -n _cmd_ref=${1:?cmd array required}
  shift
  local extra_args=( "$@" )

  \builtin command "${_cmd_ref[@]}" "${extra_args[@]}"
}

# ----------------------------------------------------------------------
# 4. Configuration, Composition & Serialization
# ----------------------------------------------------------------------

qemu_vm::resolve_file() {
  local target=${1:?target name or file required}
  local base_dir=${2:-config/vm/compositions}

  if [[ -f "$target" ]]; then
    echo "$target"
  elif [[ -f "${base_dir}/${target}" ]]; then
    echo "${base_dir}/${target}"
  elif [[ -f "${base_dir}/${target}.conf" ]]; then
    echo "${base_dir}/${target}.conf"
  elif [[ -f "config/vm/${target}" ]]; then
    echo "config/vm/${target}"
  elif [[ -f "config/vm/${target}.conf" ]]; then
    echo "config/vm/${target}.conf"
  else
    return 1
  fi
}

qemu_vm::load_seeds() {
  local seeds_file=${1:-config/vm/seeds.conf}
  if [[ -f "$seeds_file" ]]; then
    # shellcheck source=/dev/null
    \builtin . "$seeds_file" || return
  fi
}

qemu_vm::reset_composition() {
  VM_NAME=""
  VM_ARCH="x86_64"
  VM_SEED=""
  VM_ISO=""
  VM_BOOT_CDROM=0
  VM_CPUS=2
  VM_MEMORY="2G"
  VM_DISK_SIZE="20G"
  VM_DRIVE_IF="virtio"
  VM_EPHEMERAL=1
  VM_VOLID=""
  VM_NET_MODE="user"
  VM_DISPLAY="none"
  VM_VGA="none"
  VM_SERIAL="mon:stdio"
  VM_PROVISION=""
  VM_PROVISION_URL=""
  VM_CLOUD_DIR=""
  VM_BOOTSTRAP_DIR=""
  VM_BOOTSTRAP=""
  VM_GIT_URL=""
  VM_GIT_DEST=""
  VM_SHARE="9p"
  VM_SHARE_PORT=""
  VM_SHARE_SCRIPT=""
  VM_BOOT_HINT=""
  VM_PROV_IMG=""
  VM_KERNEL=""
  VM_INITRD=""
  VM_CMDLINE=""
  VM_USB_TABLET=0
  declare -ga VM_PORT_FORWARDS=()
  declare -gA VM_MOUNTS_9P=()
  declare -ga VM_MOUNTS=()
  declare -ga VM_M_NAME=()
  declare -ga VM_M_HOST=()
  declare -ga VM_M_GUEST=()
  declare -ga VM_M_MODE=()
  declare -ga VM_EXTRA_ARGS=()
}

# name:host:guest:mode
# host may contain colons. The name, guest path, and mode may not.
qemu_vm::parse_mount() {
  local spec=${1:?mount spec required}
  local -n _pm_name=${2:?name variable required}
  local -n _pm_host=${3:?host variable required}
  local -n _pm_guest=${4:?guest variable required}
  local -n _pm_mode=${5:?mode variable required}
  local rest

  [[ "$spec" == *:*:*:* ]] ||
    failerr "uc-vm: mount spec needs name:host:guest:mode: $spec" || return
  _pm_name=${spec%%:*}
  rest=${spec#*:}
  _pm_mode=${rest##*:}
  rest=${rest%:*}
  _pm_guest=${rest##*:}
  _pm_host=${rest%:*}

  [[ "$_pm_name" =~ ^[A-Za-z][A-Za-z0-9_]{0,31}$ ]] ||
    failerr "uc-vm: mount name must be a short identifier: ${_pm_name}" || return
  [[ -n "$_pm_host" && "$_pm_guest" == /* ]] ||
    failerr "uc-vm: mount ${_pm_name} needs an absolute guest path: $spec" || return
  [[ "$_pm_mode" == ro || "$_pm_mode" == rw ]] ||
    failerr "uc-vm: mount ${_pm_name} mode must be ro or rw: $spec" || return
  [[ "$_pm_host" != *,* && "$_pm_guest" != *,* ]] ||
    failerr "uc-vm: mount paths cannot contain a comma: $spec" || return
}

qemu_vm::squote_ok() {
  local s=$1
  if [[ "$s" == *\'* ]]; then
    failerr "uc-vm: value contains a single quote: $s" || return
  fi
}

qemu_vm::yaml_dquote() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  printf '"%s"' "$s"
}

qemu_vm::json_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

qemu_vm::p9_server() {
  local here
  here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || return
  echo "${here}/../../py/uc-vm-9p.py"
}

# Fill VM_M_* from VM_MOUNTS. Create missing rw directories.
qemu_vm::collect_mounts() {
  local spec name host guest mode seen=""
  VM_M_NAME=()
  VM_M_HOST=()
  VM_M_GUEST=()
  VM_M_MODE=()

  for spec in "${VM_MOUNTS[@]}"; do
    qemu_vm::parse_mount "$spec" name host guest mode || return
    [[ " $seen " != *" $name "* ]] ||
      failerr "uc-vm: duplicate mount name: $name" || return
    seen+=" $name"
    if [[ ! -d "$host" ]]; then
      if [[ "$mode" == rw ]]; then
        mkdir -p "$host" ||
          failerr "uc-vm: cannot create mount ${name} at ${host}" || return
      else
        failerr "uc-vm: mount ${name}: host path is not a directory: $host" || return
      fi
    fi
    host=$(realpath "$host") || return
    VM_M_NAME+=("$name")
    VM_M_HOST+=("$host")
    VM_M_GUEST+=("$guest")
    VM_M_MODE+=("$mode")
  done
  qemu_vm::mounts_overlap || return
}

# Parent and child exports share host inodes and break the 9p client.
qemu_vm::mounts_overlap() {
  local i j a b
  for i in "${!VM_M_HOST[@]}"; do
    for j in "${!VM_M_HOST[@]}"; do
      ((i < j)) || continue
      a=${VM_M_HOST[$i]}
      b=${VM_M_HOST[$j]}
      if [[ "$a" == "$b" || "$a" == "$b"/* || "$b" == "$a"/* ]]; then
        failerr "uc-vm: mounts ${VM_M_NAME[$i]} and ${VM_M_NAME[$j]} overlap ($a and $b)" || return
      fi
    done
  done
}

qemu_vm::apply_mounts() {
  local cmdname=${1:?cmd array name required}
  local work_dir=${2:?work dir required}

  if ((${#VM_MOUNTS[@]} == 0)); then
    local tag
    for tag in "${!VM_MOUNTS_9P[@]}"; do
      qemu_vm::add_9p "$cmdname" "$tag" "${VM_MOUNTS_9P[$tag]}"
    done
    return 0
  fi

  qemu_vm::collect_mounts || return

  case "${VM_SHARE:-9p}" in
  ( 9p )
      local i ro
      for i in "${!VM_M_NAME[@]}"; do
        ro=0
        if [[ "${VM_M_MODE[$i]}" == ro ]]; then
          ro=1
        fi
        qemu_vm::add_9p "$cmdname" "${VM_M_NAME[$i]}" "${VM_M_HOST[$i]}" none "$ro"
      done
    ;;
  ( u9fs )
      qemu_vm::prepare_u9fs "$work_dir" || return
    ;;
  ( * )
      failerr "uc-vm: unknown VM_SHARE '${VM_SHARE}' (expected 9p|u9fs)" || return
    ;;
  esac
}

qemu_vm::prepare_u9fs() {
  local work_dir=${1:?work dir required}
  local server port exports i host
  server=$(qemu_vm::p9_server) || return
  [[ -f "$server" ]] ||
    failerr "uc-vm: 9P2000 server is missing: $server" || return
  command -v python3 >/dev/null 2>&1 ||
    failerr "uc-vm: python3 is required to serve 9P2000 to 9front" || return
  port=${VM_SHARE_PORT:-15640}
  [[ "$port" =~ ^[0-9]+$ ]] ||
    failerr "uc-vm: VM_SHARE_PORT must be numeric: $port" || return
  VM_SHARE_PORT=$port
  exports="${work_dir}/${VM_NAME:-vm}-9p.exports"
  : > "$exports"
  for i in "${!VM_M_NAME[@]}"; do
    host=${VM_M_HOST[$i]}
    [[ "$host" != *$'\t'* ]] ||
      failerr "uc-vm: mount path contains a tab: $host" || return
    printf '%s\t%s\n' "${VM_M_MODE[$i]}" "$host" >> "$exports"
  done
  VM_SHARE_SCRIPT="${work_dir}/${VM_NAME:-vm}-shares.bash"
  qemu_vm::write_share_supervisor "$VM_SHARE_SCRIPT" "$server" "$exports" "$port"
}

qemu_vm::write_share_supervisor() {
  local path=${1:?script path required}
  local server=${2:?9p server required}
  local exports=${3:?exports file required}
  local port=${4:?port required}
  local log="${path%.bash}.log"
  {
    echo '#!/usr/bin/env bash'
    echo 'set -euo pipefail'
    printf 'server=%q\n' "$server"
    printf 'exports=%q\n' "$exports"
    printf 'port=%q\n' "$port"
    printf 'log=%q\n' "$log"
    cat <<'EOF'
python3 "$server" --addr 127.0.0.1 --port "$port" --exports "$exports" >"$log" 2>&1 &
pid=$!
cleanup() {
  if [[ -n ${pid:-} ]]; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT
ok=0
for _ in $(seq 1 50); do
  if { echo >/dev/tcp/127.0.0.1/"$port"; } 2>/dev/null; then
    ok=1
    break
  fi
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "uc-vm: 9P2000 server exited" >&2
    cat "$log" >&2 || true
    exit 1
  fi
  sleep 0.1
done
if [[ "$ok" != 1 ]]; then
  echo "uc-vm: 9P2000 server did not listen on 127.0.0.1:${port}" >&2
  cat "$log" >&2 || true
  exit 1
fi
[[ $# -gt 0 && "$1" == -- ]] && shift
"$@"
EOF
  } > "$path"
  chmod +x "$path"
}

qemu_vm::forbid_cloud_keys() {
  local src=${1:?user-data.in required}
  local key
  for key in runcmd write_files ssh_authorized_keys; do
    if grep -Eq "^${key}:" "$src"; then
      failerr "uc-vm: ${src} must not define ${key}; guest work goes in bootstrap" || return
    fi
  done
}

qemu_vm::append_guest_env_debian() {
  local dest=${1:?user-data path required}
  qemu_vm::squote_ok "$VM_GIT_URL" || return
  qemu_vm::squote_ok "$VM_GIT_DEST" || return
  qemu_vm::squote_ok "${VM_BOOTSTRAP:-}" || return
  {
    echo "write_files:"
    echo "  - path: /etc/uc-vm/guest.env"
    echo '    permissions: "0644"'
    echo "    content: |"
    printf "      GIT_URL='%s'\n" "$VM_GIT_URL"
    printf "      GIT_DEST='%s'\n" "$VM_GIT_DEST"
    printf "      BOOTSTRAP='%s'\n" "${VM_BOOTSTRAP:-}"
  } >> "$dest"
}

qemu_vm::append_ssh_keys() {
  local dest=${1:?user-data path required}
  local -a keys=()
  local k line
  for k in "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_rsa.pub" "$HOME/.ssh/id_ecdsa.pub"; do
    [[ -r "$k" ]] || continue
    IFS= read -r line < "$k" || continue
    [[ "$line" == ssh-* ]] || continue
    keys+=("$line")
  done
  ((${#keys[@]})) || return 0
  {
    echo "ssh_authorized_keys:"
    for line in "${keys[@]}"; do
      printf '  - %s\n' "$(qemu_vm::yaml_dquote "$line")"
    done
  } >> "$dest"
}

qemu_vm::append_runcmd() {
  local dest=${1:?user-data path required}
  local i name guest mode opts cmd
  {
    echo "runcmd:"
    echo "  - $(qemu_vm::yaml_dquote "modprobe 9pnet_virtio 2>/dev/null || true")"
    for i in "${!VM_M_NAME[@]}"; do
      name=${VM_M_NAME[$i]}
      guest=${VM_M_GUEST[$i]}
      mode=${VM_M_MODE[$i]}
      opts="trans=virtio,version=9p2000.L,cache=none,msize=1048576"
      [[ "$mode" == ro ]] && opts+=",ro"
      cmd="mkdir -p $(printf '%q' "$guest")"
      echo "  - $(qemu_vm::yaml_dquote "$cmd")"
      cmd="mount -t 9p -o $(printf '%q' "$opts") $(printf '%q' "$name") $(printf '%q' "$guest")"
      echo "  - $(qemu_vm::yaml_dquote "$cmd")"
    done
    if [[ -n "${VM_BOOTSTRAP:-}" ]]; then
      cmd="if [ -f $(printf '%q' "$VM_BOOTSTRAP") ]; then sh $(printf '%q' "$VM_BOOTSTRAP"); fi"
      echo "  - $(qemu_vm::yaml_dquote "$cmd")"
    fi
  } >> "$dest"
}

qemu_vm::build_cidata() {
  local work_dir=${1:?work dir required}
  local src_dir=${VM_CLOUD_DIR:?VM_CLOUD_DIR required for cidata}
  local src="${src_dir}/user-data.in"
  local stage user_data meta img sum
  [[ -f "$src" ]] ||
    failerr "uc-vm: missing cloud-init user-data.in: $src" || return
  [[ -z "${VM_BOOTSTRAP:-}" || -f "${src_dir}/bootstrap" ]] ||
    failerr "uc-vm: missing guest bootstrap: ${src_dir}/bootstrap" || return
  command -v cloud-localds >/dev/null 2>&1 ||
    failerr "uc-vm: cloud-localds is required (cloud-image-utils)" || return
  qemu_vm::forbid_cloud_keys "$src" || return

  stage="${work_dir}/${VM_NAME:-vm}-cidata"
  mkdir -p "$stage"
  user_data="${stage}/user-data"
  meta="${stage}/meta-data"
  img="${work_dir}/${VM_NAME:-vm}-cidata.img"
  cp "$src" "$user_data"
  [[ -s "$user_data" && $(tail -c1 "$user_data") == "" ]] || echo >> "$user_data"
  qemu_vm::append_guest_env_debian "$user_data" || return
  qemu_vm::append_ssh_keys "$user_data" || return
  qemu_vm::append_runcmd "$user_data" || return
  sum=$(cksum "$user_data" | awk '{print $1}')
  cat > "$meta" <<EOF
instance-id: ${VM_NAME:-vm}-${sum}
local-hostname: ${VM_NAME:-vm}
dsmode: local
EOF
  rm -f "$img"
  cloud-localds "$img" "$user_data" "$meta" >&2 ||
    failerr "uc-vm: cloud-localds failed for ${img}" || return
  echo "uc-vm: wrote ${img}" >&2
  VM_PROV_IMG=$img
  VM_BOOT_HINT=$(
    cat <<EOF
${VM_NAME}: cloud-init mounts the shares, then runs ${VM_BOOTSTRAP:-<no bootstrap>}
  clone: ${VM_GIT_URL:-<none>} -> ${VM_GIT_DEST:-<none>}
  ssh:   ssh -p 2222 debian@127.0.0.1
EOF
  )
}

qemu_vm::build_bootiso() {
  local work_dir=${1:?work dir required}
  local src_dir=${VM_BOOTSTRAP_DIR:?VM_BOOTSTRAP_DIR required for iso9660}
  local stage img port i
  [[ -f "${src_dir}/bootstrap.rc" ]] ||
    failerr "uc-vm: missing ${src_dir}/bootstrap.rc" || return
  command -v genisoimage >/dev/null 2>&1 ||
    failerr "uc-vm: genisoimage is required to build the 9front config disc" || return
  qemu_vm::squote_ok "$VM_GIT_URL" || return
  qemu_vm::squote_ok "$VM_GIT_DEST" || return
  qemu_vm::squote_ok "${VM_BOOTSTRAP:-}" || return
  local h
  for h in "${VM_M_HOST[@]}"; do
    qemu_vm::squote_ok "$h" || return
  done

  port=${VM_SHARE_PORT:-15640}
  stage="${work_dir}/${VM_NAME:-vm}-boot"
  rm -rf "$stage"
  mkdir -p "$stage"
  cp "${src_dir}/bootstrap.rc" "${stage}/bootstrap.rc"
  {
    printf "GIT_URL='%s'\n" "$VM_GIT_URL"
    printf "GIT_DEST='%s'\n" "$VM_GIT_DEST"
    printf "BOOTSTRAP='%s'\n" "${VM_BOOTSTRAP:-}"
  } > "${stage}/guest.env"
  {
    cat <<'EOF'
# uc-vm config disc. At a 9front prompt:
#   9660srv
#   mounted=()
#   for (d in /dev/sdD0/data /dev/sd*/data) {
#     if (~ $#mounted 0) {
#       if (mount /srv/9660 /n/cfg $d >[2]/dev/null) {
#         if (test -f /n/cfg/startup.rc) { mounted=$d; echo $d }
#         if not unmount /n/cfg
#       }
#     }
#   }
#   . /n/cfg/startup.rc

if (! grep -s '10\.0\.2\.' /net/ipselftab >[2]/dev/null)
	ip/ipconfig

fn ucvmshare {
	srv tcp!10.0.2.2!__UCVM_PORT__ $1
	mkdir -p $3
	if (~ $4 rw)
		mount -c /srv/$1 $3 $2
	if not
		mount /srv/$1 $3 $2
}

EOF
    for i in "${!VM_M_NAME[@]}"; do
      printf "ucvmshare %s '%s' %s %s\n" \
        "${VM_M_NAME[$i]}" "${VM_M_HOST[$i]}" "${VM_M_GUEST[$i]}" "${VM_M_MODE[$i]}"
    done
    cat <<'EOF'

if (test -f /n/cfg/guest.env)
	. /n/cfg/guest.env
if (~ $#BOOTSTRAP 1 && test -f $BOOTSTRAP)
	. $BOOTSTRAP
if not if (test -f /n/cfg/bootstrap.rc)
	. /n/cfg/bootstrap.rc
EOF
  } > "${stage}/startup.rc"
  sed -i "s/__UCVM_PORT__/${port}/g" "${stage}/startup.rc"

  img="${work_dir}/${VM_NAME:-vm}-boot.iso"
  rm -f "$img"
  (
    cd "$stage"
    genisoimage -o "$img" -V cfg -R -J .
  ) >/dev/null ||
    failerr "uc-vm: genisoimage failed for ${img}" || return
  echo "uc-vm: wrote ${img}" >&2
  VM_PROV_IMG=$img
  VM_BOOT_HINT=$(cat <<EOF
${VM_NAME}: 9P2000 server on 127.0.0.1:${port} (guest dials 10.0.2.2).
At a 9front prompt:
  9660srv
  mounted=()
  for (d in /dev/sdD0/data /dev/sd*/data) {
    if (~ \$#mounted 0) {
      if (mount /srv/9660 /n/cfg \$d >[2]/dev/null) {
        if (test -f /n/cfg/startup.rc) { mounted=\$d; echo \$d }
        if not unmount /n/cfg
      }
    }
  }
  . /n/cfg/startup.rc
EOF
)
}

qemu_vm::add_data_cdrom() {
  local -n _cmd_ref=${1:?cmd array required}
  local file=${2:?cdrom image required}
  local iface=${3:-ide}
  local index=${4:-2}

  [[ "$file" != *,* ]] ||
    failerr "uc-vm: cdrom path cannot contain a comma: $file" || return
  # index 2 is the secondary master, clear of the disk on ide index 0.
  # Do not set -boot d: this disc is config, not an installer.
  _cmd_ref+=(
    -drive "file=${file},format=raw,if=${iface},media=cdrom,index=${index},readonly=on"
  )
}

qemu_vm::load_composition() {
  local target=${1:?composition name or file required}
  local comp_path
  comp_path=$(qemu_vm::resolve_file "$target") ||
    failerr "qemu_vm::load_composition: composition not found: $target" || return

  # shellcheck source=/dev/null
  qemu_vm::load_seeds "${SEEDS_CONF:-config/vm/seeds.conf}" &&
  qemu_vm::reset_composition &&

  \builtin . "$comp_path"
}

qemu_vm::compose() {
  local -n _out_cmd=${1:?cmd array variable required}
  local target=${2:?composition name or file required}
  local work_dir=${3:-${VM_WORK_DIR:-${PWD}/.vm-work}}

  qemu_vm::load_composition "$target" || return 1

  qemu_vm::init _out_cmd "${VM_ARCH:-x86_64}" || return 1
  qemu_vm::accel _out_cmd auto || return 1
  qemu_vm::cpu _out_cmd "${VM_CPUS:-2}"
  qemu_vm::memory _out_cmd "${VM_MEMORY:-2G}"

  # 1. Drive / Storage handling
  if [[ -n "${VM_SEED:-}" ]]; then
    local seed_cache="${VM_CACHE_DIR:-${HOME}/.cache/vm-seeds}/${VM_SEED}.qcow2"
    local run_disk="${work_dir}/${VM_NAME:-vm}.qcow2"

    mkdir -p "$work_dir"

    local drive_if="${VM_DRIVE_IF:-virtio}"

    if ((VM_EPHEMERAL)); then
      local overlay_disk="${work_dir}/${VM_NAME:-vm}-overlay.qcow2"
      # Drop the previous overlay so a cidata first-boot runs on every launch.
      rm -f "$overlay_disk" || return
      if [[ -f "$seed_cache" ]]; then
        qemu_vm::disk_overlay "$seed_cache" "$overlay_disk" "${VM_DISK_SIZE:-}" || return 1
        qemu_vm::add_drive _out_cmd "$overlay_disk" qcow2 "$drive_if"
      elif [[ -f "$run_disk" ]]; then
        qemu_vm::disk_overlay "$run_disk" "$overlay_disk" "${VM_DISK_SIZE:-}" || return 1
        qemu_vm::add_drive _out_cmd "$overlay_disk" qcow2 "$drive_if"
      else
        # Fallback to fresh disk if no seed cached yet
        qemu_vm::disk_create "$overlay_disk" "${VM_DISK_SIZE:-20G}" qcow2 || return 1
        qemu_vm::add_drive _out_cmd "$overlay_disk" qcow2 "$drive_if"
      fi
    else
      qemu_vm::disk_create "$run_disk" "${VM_DISK_SIZE:-20G}" qcow2 || return 1
      qemu_vm::add_drive _out_cmd "$run_disk" qcow2 "$drive_if"
    fi
  elif [[ -n "${VM_ISO:-}" ]]; then
    local iso_path="${VM_ISOS[$VM_ISO]:-$VM_ISO}"
    local run_disk="${work_dir}/${VM_NAME:-vm}.qcow2"
    local drive_if="${VM_DRIVE_IF:-virtio}"
    mkdir -p "$work_dir"
    qemu_vm::disk_create "$run_disk" "${VM_DISK_SIZE:-20G}" qcow2 || return 1
    qemu_vm::add_drive _out_cmd "$run_disk" qcow2 "$drive_if"
    qemu_vm::add_cdrom _out_cmd "$iso_path" "${VM_BOOT_CDROM:-0}"
  fi

  # 2. Networking
  if [[ "${VM_NET_MODE:-user}" == "user" ]]; then
    local fwd_str="" item
    for item in "${VM_PORT_FORWARDS[@]}"; do
      if [[ -z "$fwd_str" ]]; then
        fwd_str="$item"
      else
        fwd_str="${fwd_str},hostfwd=${item}"
      fi
    done
    qemu_vm::net_user _out_cmd "$fwd_str"
  elif [[ "${VM_NET_MODE:-}" == "none" ]]; then
    qemu_vm::net_none _out_cmd
  fi

  # 3. Shares. 9p becomes virtio devices; u9fs becomes a diod sidecar.
  mkdir -p "$work_dir" &&
  qemu_vm::apply_mounts _out_cmd "$work_dir" || return 1

  # 4. Display & Serial
  qemu_vm::display _out_cmd "${VM_DISPLAY:-none}" "${VM_VGA:-none}"
  if [[ -n "${VM_SERIAL:-}" ]]; then
    qemu_vm::serial _out_cmd "$VM_SERIAL"
  fi

  # 5. Provisioning
  if [[ "${VM_PROVISION:-}" == "smbios" && -n "${VM_PROVISION_URL:-}" ]]; then
    qemu_vm::smbios_nocloud _out_cmd "$VM_PROVISION_URL"
  elif [[ "${VM_PROVISION:-}" == "cidata" ]]; then
    [[ "${VM_SHARE:-9p}" == 9p ]] ||
      failerr "uc-vm: cidata bootstrap mounts virtio-9p; set VM_SHARE=9p" || return 1
    qemu_vm::build_cidata "$work_dir" || return 1
    qemu_vm::cidata_drive _out_cmd "$VM_PROV_IMG"
  elif [[ "${VM_PROVISION:-}" == "iso9660" ]]; then
    [[ "${VM_SHARE:-}" == u9fs ]] ||
      failerr "uc-vm: iso9660 bootstrap dials a 9p server; set VM_SHARE=u9fs" || return 1
    qemu_vm::build_bootiso "$work_dir" || return 1
    qemu_vm::add_data_cdrom _out_cmd "$VM_PROV_IMG" "${VM_DRIVE_IF:-ide}" 2
  elif [[ -n "${VM_CIDATA_IMG:-}" ]]; then
    qemu_vm::cidata_drive _out_cmd "$VM_CIDATA_IMG"
  fi

  # 6. Direct kernel boot (if specified)
  if [[ -n "${VM_KERNEL:-}" ]]; then
    qemu_vm::kernel_boot _out_cmd "$VM_KERNEL" "${VM_INITRD:-}" "${VM_CMDLINE:-}"
  fi

  # 7. Pointing Device (USB Tablet for absolute mouse tracking)
  if ((VM_USB_TABLET)); then
    _out_cmd+=( -usb -device usb-tablet )
  fi

  # 8. Extra user arguments
  if ((${#VM_EXTRA_ARGS[@]} > 0)); then
    _out_cmd+=( "${VM_EXTRA_ARGS[@]}" )
  fi
}

qemu_vm::to_json() {
  local target=${1:?composition name or file required}
  qemu_vm::load_composition "$target" || return 1

  local pf_json="[]"
  if ((${#VM_PORT_FORWARDS[@]} > 0)); then
    local items=() item
    for item in "${VM_PORT_FORWARDS[@]}"; do
      items+=( "\"${item}\"" )
    done
    local IFS=,
    pf_json="[${items[*]}]"
  fi

  local m9p_json="{}"
  if ((${#VM_MOUNTS_9P[@]} > 0)); then
    local entries=() k
    for k in "${!VM_MOUNTS_9P[@]}"; do
      entries+=( "\"$(qemu_vm::json_escape "$k")\": \"$(qemu_vm::json_escape "${VM_MOUNTS_9P[$k]}")\"" )
    done
    local IFS=,
    m9p_json="{${entries[*]}}"
  fi

  local mounts_json
  mounts_json=$(qemu_vm::mounts_json) || return

  cat <<EOF
{
  "name": "${VM_NAME}",
  "arch": "${VM_ARCH}",
  "seed": "${VM_SEED}",
  "iso": "${VM_ISO}",
  "boot_cdrom": ${VM_BOOT_CDROM:-0},
  "cpus": ${VM_CPUS:-2},
  "memory": "${VM_MEMORY:-2G}",
  "disk_size": "${VM_DISK_SIZE:-20G}",
  "ephemeral": $( ((VM_EPHEMERAL)) && echo true || echo false ),
  "volid": "${VM_VOLID:-}",
  "net_mode": "${VM_NET_MODE:-user}",
  "port_forwards": ${pf_json},
  "share": "${VM_SHARE:-9p}",
  "share_port": "${VM_SHARE_PORT:-}",
  "mounts": ${mounts_json},
  "mounts_9p": ${m9p_json},
  "bootstrap": "$(qemu_vm::json_escape "${VM_BOOTSTRAP:-}")",
  "git": {
    "url": "$(qemu_vm::json_escape "${VM_GIT_URL:-}")",
    "dest": "$(qemu_vm::json_escape "${VM_GIT_DEST:-}")"
  },
  "display": "${VM_DISPLAY:-none}",
  "vga": "${VM_VGA:-none}",
  "serial": "${VM_SERIAL:-mon:stdio}",
  "provision": {
    "type": "${VM_PROVISION:-none}",
    "url": "${VM_PROVISION_URL:-}",
    "dir": "$(qemu_vm::json_escape "${VM_CLOUD_DIR:-${VM_BOOTSTRAP_DIR:-}}")"
  }
}
EOF
}

qemu_vm::mounts_json() {
  local spec name host guest mode
  local json="[" sep=""
  if ((${#VM_MOUNTS[@]} == 0)); then
    echo "[]"
    return 0
  fi
  for spec in "${VM_MOUNTS[@]}"; do
    qemu_vm::parse_mount "$spec" name host guest mode || return
    json+="${sep}{\"name\":\"$(qemu_vm::json_escape "$name")\",\"host\":\"$(qemu_vm::json_escape "$host")\",\"guest\":\"$(qemu_vm::json_escape "$guest")\",\"mode\":\"${mode}\"}"
    sep=","
  done
  printf '%s\n' "${json}]"
}

qemu_vm::print_mounts() {
  local spec name host guest mode tag
  if ((${#VM_MOUNTS[@]})); then
    for spec in "${VM_MOUNTS[@]}"; do
      qemu_vm::parse_mount "$spec" name host guest mode || return
      printf 'Mount:        %s  %s -> %s (%s)\n' "$name" "$host" "$guest" "$mode"
    done
  elif ((${#VM_MOUNTS_9P[@]})); then
    for tag in "${!VM_MOUNTS_9P[@]}"; do
      printf 'Mount:        %s  %s (9p)\n' "$tag" "${VM_MOUNTS_9P[$tag]}"
    done
  else
    echo "Mount:        <none>"
  fi
}

qemu_vm::describe() {
  local pdir=${VM_CLOUD_DIR:-${VM_BOOTSTRAP_DIR:-}}
  cat <<EOF
Composition:  ${VM_NAME}
Arch:         ${VM_ARCH}
Seed:         ${VM_SEED:-<none>}
ISO:          ${VM_ISO:-<none>}
CPUs / RAM:   ${VM_CPUS} cores / ${VM_MEMORY}
Disk Size:    ${VM_DISK_SIZE} (ephemeral: ${VM_EPHEMERAL})
Display:      ${VM_DISPLAY} (vga: ${VM_VGA:-none})
Serial:       ${VM_SERIAL}
Port Fwd:     ${VM_PORT_FORWARDS[*]:-<none>}
Share:        ${VM_SHARE:-9p}${VM_SHARE_PORT:+ (port ${VM_SHARE_PORT})}
Bootstrap:    ${VM_BOOTSTRAP:-<none>}
Git:          ${VM_GIT_URL:-<none>} -> ${VM_GIT_DEST:-<none>}
Provision:    ${VM_PROVISION:-none}${pdir:+ ($pdir)}${VM_PROVISION_URL:+ ($VM_PROVISION_URL)}
EOF
  qemu_vm::print_mounts
}

qemu_vm::list_compositions() {
  local dir=${1:-config/vm/compositions}
  if [[ -d "$dir" ]]; then
    for f in "$dir"/*.conf; do
      [[ -e "$f" ]] || continue
      local base="${f##*/}"
      echo "${base%.conf}"
    done
  fi
}

qemu_vm::list_seeds() {
  local seeds_file=${1:-config/vm/seeds.conf}
  qemu_vm::load_seeds "$seeds_file" || return
  if [[ ${VM_SEEDS[*]:+set} ]]; then
    echo "Seeds:"
    for k in "${!VM_SEEDS[@]}"; do
      echo "  $k -> ${VM_SEEDS[$k]}"
    done
  else
    failmsg "No seed keys/URLs configured! (vm/seeds.conf: VM_SEED)"
  fi
  if [[ ${VM_ISOS[*]:+set} ]]; then
    echo "ISOs:"
    for k in "${!VM_ISOS[@]}"; do
      echo "  $k -> ${VM_ISOS[$k]}"
    done
  else
    failmsg "No seed ISO image configured! (vm/seeds.conf: VM_ISOS)"
  fi
}

qemu_vm::fetch_seed() {
  local seed_id=${1:?seed ID required}
  local seed_ratio=${2:-${VM_SEED_RATIO:-2.0}}
  local seed_time=${3:-${VM_SEED_TIME:-60}} # minutes

  qemu_vm::load_seeds "${SEEDS_CONF:-config/vm/seeds.conf}" || return

  local url="${VM_SEEDS[$seed_id]:-}"
  [[ -n "$url" ]] ||
    failerr "qemu_vm::fetch_seed: unknown seed ID: $seed_id" || return

  local cache_dir="${VM_CACHE_DIR:-${HOME}/.cache/vm-seeds}"
  mkdir -p "$cache_dir" || return

  local target_qcow2="${cache_dir}/${seed_id}.qcow2"
  if [[ -s "$target_qcow2" ]]; then
    faillerr "Seed already exists at: $target_qcow2" ${_E_done:-200} || return
  fi

  if [[ "$url" =~ \.torrent$ ]]; then
    \builtin command -v aria2c >/dev/null 2>&1 ||
      failerr "qemu_vm::fetch_seed: aria2c is required for BitTorrent downloads" || return

    echo "==> Fetching torrent seed: $seed_id from $url"
    echo "==> P2P parameters: seed-ratio ${seed_ratio}, seed-time ${seed_time}m"

    aria2c \
      --dir="$cache_dir" \
      --seed-ratio="$seed_ratio" \
      --seed-time="$seed_time" \
      --follow-torrent=mem \
      --summary-interval=5 \
      "$url" || return

    local torrent_file="${url##*/}"
    local base_name="${torrent_file%.torrent}"
    local payload="${cache_dir}/${base_name}"

    if [[ -f "$payload" ]]; then
      if [[ "$payload" =~ \.gz$ ]]; then
        local uncompressed="${payload%.gz}"
        if [[ ! -f "$uncompressed" ]]; then
          echo "==> Decompressing $payload -> $uncompressed ..."
          gzip -dk "$payload" || return
        fi
        if [[ "$uncompressed" != "$target_qcow2" && ! -f "$target_qcow2" ]]; then
          ln -sf "$uncompressed" "$target_qcow2" || return
        fi
      elif [[ "$payload" != "$target_qcow2" ]]; then
        ln -sf "$payload" "$target_qcow2" || return
      fi
    fi

    echo "==> Seed ready at: $target_qcow2"

  else
    echo "==> Fetching HTTP seed: $seed_id from $url"
    if \builtin command -v aria2c >/dev/null 2>&1; then
      aria2c -d "$cache_dir" -o "${seed_id}.qcow2" "$url" || return
    elif \builtin command -v curl >/dev/null 2>&1; then
      curl -fL "$url" -o "$target_qcow2" || return
    else
      wget "$url" -O "$target_qcow2" || return
    fi
  fi
}

# Id: tool/bash/include/qemu-vm.inc.bash  vim:set ft=bash sw=2 sts=2 et:
