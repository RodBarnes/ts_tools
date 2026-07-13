#!/usr/bin/env bash

# Delete ts-backups

source /usr/local/lib/ts-shared.sh
LIB_VERSION="$VERSION"

VERSION="20260713"

show_syntax() {
  echo "Delete a snapshot created with ts-backup."
  echo "Syntax: $(basename $0) <backup_device> [server]"
  echo "Where:  <backup_device> can be a device designator (e.g., /dev/sdb6), a UUID, filesystem LABEL, or partition UUID"
  echo "        [server] optionally limits the selection list to snapshots for that server only."
  echo "        [-V|--version] will display the version."
  echo "NOTE:   Must be run as sudo."
  exit
}

delete_snapshot() {
  local path=$1
  local subpath=$2

  local snapshot_dir="$path/$subpath"
  local guid
  local empty_dir
  local yn

  empty_dir=$(mktemp -d /tmp/empty.XXXXXX)

  showx "This will completely and IRREVERSIBLY DELETE the snapshot '$subpath'."
  showx "All other remaining snapshots will stay fully intact and restorable."
  readx "Are you sure you want to proceed? (y/N)" yn
  if [[ $yn != "y" && $yn != "Y" ]]; then
    showx "Operation cancelled."
  else
    show "Safely deleting snapshot '$subpath' (this may take a while)..."

    rsync -a --delete --quiet \
          --filter="protect /dev/" \
          --filter="protect /proc/" \
          --filter="protect /sys/" \
          --filter="protect /run/" \
          --filter="protect /tmp/" \
          --filter="protect /mnt/" \
          --filter="protect /media/" \
          --filter="exclude *" \
          "$empty_dir/" "$snapshot_dir/"

    # Now remove the now-empty directory itself
    rmdir "$snapshot_dir" 2>/dev/null || rm -rf "$snapshot_dir"

    show "Snapshot '$subpath' deleted safely."
  fi

  rm -rf "$empty_dir"
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

show_device_space "$backupdevice"

while true; do
  # select_snapshot returns "hostname/snapshotname"
  snapshotsubpath=$(select_snapshot "$backupdevice" "$g_backuppath/$g_backupdir" "$server")
  if [ -n "$snapshotsubpath" ]; then
    delete_snapshot "$g_backuppath/$g_backupdir" "$snapshotsubpath"
  else
    exit
  fi
done
