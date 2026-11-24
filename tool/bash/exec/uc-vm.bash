#!/usr/bin/env bash
#
# uc-vm: Experiment harness CLI for QEMU VMs in userconf
#
# Copyright B. van Berkum 2026 <berend@dotmpe.com>
# Distributed under terms of the MIT license.

set -euo pipefail

# TODO: see about building this script using us-pp/us-build,
# for now dynamic load works but it combines user profile now
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

#cd "$REPO_ROOT"

PATH+=:${U_S:?User profile broken}/tool/bash/include
. "us-core.inc.bash"
. "us-common.inc.bash"
#. "us-say.inc.bash"
. "us-shell.inc.bash"
. "us-use.inc.bash"
. "us-call.inc.bash"

script_cmdname=uc-vm
userscripts::call_all _init userscripts::{core,common,shell}
userscripts::use_all userscripts::{core,common}

PATH+=:${REPO_ROOT}/tool/bash/include
. "uc-qemu-vm.inc.bash"

usage() {
  cat <<EOF
Usage: ${0##*/} <command> [arguments...]

Commands:
  list                          List available VM compositions
  inspect <comp> [--json]       Show composition details (text or JSON)
  seeds                         List known seeds and ISOs
  fetch <seed_id>               Download a remote seed into local cache
  cmd <comp>                    Print compiled QEMU command line
  run <comp> [extra_args...]    Launch VM composition

EOF
  exit 1
}

cmd="${1:-}"
shift || true

case "$cmd" in
( list )
      qemu_vm::list_compositions
    ;;

( inspect )
      target="${1:?composition name required}"
      shift
      if [[ "${1:-}" == "--json" ]]; then
        qemu_vm::to_json "$target"
      else
        qemu_vm::load_composition "$target"
        qemu_vm::describe
      fi
    ;;

( seeds )
      qemu_vm::list_seeds
    ;;

( fetch )
      seed_id="${1:?seed ID required}"
      shift || true
      qemu_vm::fetch_seed "$seed_id" "$@"
    ;;

( cmd )
      target="${1:?composition name required}"
      declare -a vm_cmd=()
      qemu_vm::compose vm_cmd "$target"
      if [[ -n "${VM_BOOT_HINT:-}" ]]; then
        printf '%s\n' "$VM_BOOT_HINT" >&2
      fi
      if [[ -n "${VM_SHARE_SCRIPT:-}" ]]; then
        printf 'share supervisor: %s\n' "$VM_SHARE_SCRIPT" >&2
      fi
      qemu_vm::dump_cmd vm_cmd
    ;;

( run)
      target="${1:?composition name required}"
      shift || true
      declare -a vm_cmd=()
      qemu_vm::compose vm_cmd "$target"
      if [[ -n "${VM_BOOT_HINT:-}" ]]; then
        printf '%s\n' "$VM_BOOT_HINT" >&2
      fi
      echo "Launching VM: $target ..." >&2
      if [[ -n "${VM_SHARE_SCRIPT:-}" ]]; then
        bash "$VM_SHARE_SCRIPT" -- "${vm_cmd[@]}" "$@"
      else
        qemu_vm::run vm_cmd "$@"
      fi
    ;;

( * )
    usage
esac

# Id: tool/bash/exec/uc-vm.bash                  vim:set ft=bash sw=2 sts=2 et:
