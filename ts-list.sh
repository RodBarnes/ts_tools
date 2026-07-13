#!/usr/bin/env bash

# List the ts-backups

source /usr/local/lib/ts-shared.sh
LIB_VERSION="$VERSION"

VERSION="20260713"

show_syntax() {
  echo "List all snapshots created by ts-backup."
  echo "Syntax: $(basename $0) <backup_device> [server]"
  echo "Where:  <backup_device> can be a device designator (e.g., /dev/sdb6), a UUID, filesystem LABEL, or partition UUID"
  echo "        [server] optionally filters the list to snapshots for that server only."
  echo "        [-V|--version] will display the version."
  echo "NOTE:   Must be run as sudo."
  exit
}

list_snapshots() {
  local device=$1
  local path=$2
  local server=$3

  local entry
  local key
  local comment

  collect_snapshots "$path" "$server"

  if [ ${#g_snapshots[@]} -eq 0 ]; then
    if [ -n "$server" ]; then
      showx "There are no backups on $device for server '$server'"
    else
      showx "There are no backups on $device"
    fi
    return
  fi

  show_device_space "$device"
  show ""

  for entry in "${g_snapshots[@]}"; do
    key="${entry%%|*}"
    comment="${entry##*|}"
    format_snapshot_line "$key" "$comment" ""
  done
}

cleanup() {
  unmount_device_at_path "$g_backuppath"
}

# --------------------
# ------- MAIN -------
# --------------------

trap 'cleanup' EXIT

# Get the arguments
if [[ "$1" == "-V" || "$1" == "--version" ]]; then
  echo "$(basename $0) v$VERSION, ts-shared.sh v$LIB_VERSION"
  exit 0
elif [ $# -ge 1 ]; then
  backupdevice=$(get_device "$1")
  server="$2"
else
  show_syntax
fi

verify_sudo

if [[ ! -b $backupdevice ]]; then
  printx "No valid backup device was found for '$backupdevice'."
  exit
fi

mount_device_at_path "$backupdevice" "$g_backuppath" "$g_backupdir"
list_snapshots "$backupdevice" "$g_backuppath/$g_backupdir" "$server"
