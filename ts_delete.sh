#!/usr/bin/env bash

# Delete ts_backups

source /usr/local/lib/ts_shared

show_syntax() {
  echo "Delete a snapshot created with ts_backup."
  echo "Syntax: $(basename $0) <backup_device>"
  echo "Where:  <backup_device> can be a device designator (e.g., /dev/sdb6), a UUID, filesystem LABEL, or partition UUID"
  echo "NOTE:   Must be run as sudo."
  exit  
}

delete_snapshot() {
  local path=$1 name=$2

  printx "This will completely DELETE the snapshot '$name' and is not recoverable." >&2
  readx "Are you sure you want to proceed? (y/N) " yn
  if [[ $yn != "y" && $yn != "Y" ]]; then
    echo "Operation cancelled." >&2
  else
    echo "Deleting '$name'." >&2
    sudo rm -Rf $path/$name
  fi
}

# --------------------
# ------- MAIN -------
# --------------------

g_descfile=comment.txt
backuppath=/mnt/backup
backupdir="ts"

trap 'unmount_device_at_path "$backuppath"' EXIT

# Get the arguments
if [ $# -ge 1 ]; then
  arg="$1"
  shift 1
  device="${arg#/dev/}" # in case it is a device designator
  backupdevice="/dev/$(lsblk -ln -o NAME,UUID,PARTUUID,LABEL | grep "$device" | tr -s ' ' | cut -d ' ' -f1)"
  if [ -z $backupdevice ]; then
    printx "No valid device was found for '$device'."
    exit
  fi
else
  show_syntax
fi

if [ -z $backupdevice ]; then
  show_syntax
fi

if [[ "$EUID" != 0 ]]; then
  printx "This must be run as sudo.\n"
  exit 1
fi

mount_device_at_path "$backupdevice" "$backuppath" "$backupdir"
while true; do
  snapshotname=$(select_snapshot "$backupdevice" "$backuppath/$backupdir")
  if [ ! -z $snapshotname ]; then
    delete_snapshot "$backuppath/$backupdir" "$snapshotname"
  else
    exit
  fi
done
