#!/usr/bin/env bash

# List the snapshots found on the specified backupdevice and allow selecting to delete.
# One of the following is required parameter: <backupdevice>, <label>, or <uuid> for mounting the backupdevice

# NOTE: This script expects to find the listed mountpoints.  If not present, it will fail.

source ts_functions.sh

show_syntax() {
  echo "Delete a snapshot created with ts_backup."
  echo "Syntax: $(basename $0) <backup_device>"
  echo "Where:  <backup_device> can be a backupdevice designator (e.g., /dev/sdb6), a UUID, or a filesystem LABEL."
  echo "NOTE:   Must be run as sudo."
  exit  
}

select_snapshot() {
  local device=$1 path=$2
  # Get the snapshots
  
  local snapshots=() name note count selected

  while IFS= read -r dirname; do
    name=("${dirname}")
    if [ -f "$path/$name/$g_descfile" ]; then
      note="$(cat $path/$name/$g_descfile)"
    else
      note="<no desc>"
    fi
    snapshots+=("$name: $note")
  done < <(find $path -mindepth 1 -maxdepth 1 -type d | sort -r | cut -d '/' -f5)

  if [ ${#snapshots[@]} -eq 0 ]; then
    printx "There are no backups on $device" >&2
  else
    printx "Snapshot files on $device" >&2
    # Get the count of options and increment to include the cancel
    count="${#snapshots[@]}"
    ((count++))

    COLUMNS=1
    select selection in "${snapshots[@]}" "Cancel"; do
      if [[ "$REPLY" =~ ^[0-9]+$ && "$REPLY" -ge 1 && "$REPLY" -le $count ]]; then
        case ${selection} in
          "Cancel")
            # If the user decides to cancel...
            echo "Operation cancelled." >&2
            break
            ;;
          *)
            selected=$(echo $selection | cut -d ':' -f1)
            break
            ;;
        esac
      else
        printx "Invalid selection. Please enter a number between 1 and $count." >&2
      fi
    done
  fi

  echo $selected
}

delete_snapshot() {
  local path=$1 name=$2

  printx "This will completely DELETE the snapshot '$name' and is not recoverable." >&2
  readx "Are you sure you want to proceed? (y/N) " yn
  if [[ $yn != "y" && $yn != "Y" ]]; then
    echo "Operation cancelled." >&2
  else
    sudo rm -Rf $path/$name
    echo "'$name' has been deleted." >&2
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
