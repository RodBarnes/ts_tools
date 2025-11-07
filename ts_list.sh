#!/usr/bin/env bash

# List the snapshots found on the specified backupdevice.
# One of the following is required parameter: <backupdevice>, <label>, or <uuid> for mounting the backupdevice

# NOTE: This script expects to find the listed mountpoints.  If not present, it will fail.

source ts_functions.sh

show_syntax() {
  echo "List all snapshots created by ts_backup."
  echo "Syntax: $(basename $0) <backup_device>"
  echo "Where:  <backup_device> can be a backupdevice designator (e.g., /dev/sdb6), a UUID, filesystem LABEL, or partition UUID"
  echo "NOTE:   Must be run as sudo."
  exit  
}

list_snapshots() {
  local device=$1 path=$2

  # Get the snapshots
  local snapshots=() note name

  while IFS= read -r dirname; do
    name=("${dirname}")
    if [ -f "$path/$name/$g_descfile" ]; then
      note="$(cat $path/$name/$g_descfile)"
    else
      note="<no desc>"
    fi
    snapshots+=("$name: $note")
  done < <( find $path -mindepth 1 -maxdepth 1 -type d | sort -r | cut -d '/' -f5 )

  if [ ${#snapshots[@]} -eq 0 ]; then
    printx "There are no backups on $device" >&2
  else
    echo "Snapshot files on $device" >&2
    for snapshot in "${snapshots[@]}"; do
      printf "$snapshot\n" >&2
    done
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
list_snapshots "$backupdevice" "$backuppath/$backupdir"

