#!/usr/bin/env bash

# List the snapshots found on the specified backupdevice.
# One of the following is required parameter: <backupdevice>, <label>, or <uuid> for mounting the backupdevice

# NOTE: This script expects to find the listed mountpoints.  If not present, it will fail.

source /usr/local/lib/colors

backuppath=/mnt/backup
snapshotpath=$backuppath/ts
descfile=comment.txt
regex="^\S{8}-\S{4}-\S{4}-\S{4}-\S{12}$"

function printx {
  printf "${YELLOW}$1${NOCOLOR}\n"
}

function show_syntax {
  echo "List all snapshots created by ts_backup."
  echo "Syntax: $(basename $0) <backup_device>"
  echo "Where:  <backup_device> can be a backupdevice designator (e.g., /dev/sdb6), a UUID, or a filesystem LABEL."
  echo "NOTE:   Must be run as sudo."
  exit  
}

function mount_device_at_path {
  local device=$1 mount=$2
  
  # Ensure mount point exists
  if [ ! -d $mount ]; then
    sudo mkdir -p $mount
    if [ $? -ne 0 ]; then
      printx "Unable to locate or create '$mount'." >&2
      exit 2
    fi
  fi

  # Attempt to mount the device
  sudo mount $device $mount
  if [ $? -ne 0 ]; then
    printx "Unable to mount the backup backupdevice '$device'." >&2
    exit 2
  fi

  # Ensure the directory structure exists
  if [ ! -d "$mount/ts" ]; then
    sudo mkdir "$mount/ts"
    if [ $? -ne 0 ]; then
      printx "Unable to locate or create '$mount/ts'." >&2
      exit 2
    fi
  fi
}

function unmount_device_at_path {
  local mount=$1

  # Unmount if mounted
  if [ -d "$mount/fs" ]; then
    sudo umount $mount
  fi
}

function list_snapshots {
  local device=$1 path=$2

  # Get the snapshots
  local snapshots=() note name

  while IFS= read -r dirname; do
    name=("${dirname}")
    if [ -f "$path/$name/$descfile" ]; then
      note="$(cat $path/$name/$descfile)"
    else
      note="<no desc>"
    fi
    snapshots+=("$name: $note")
  done < <( find $path -mindepth 1 -maxdepth 1 -type d | sort -r | cut -d '/' -f5 )

  if [ ${#snapshots[@]} -eq 0 ]; then
    printx "There are no backups on $device"
  else
    printx "Snapshot files on $device"
    for snapshot in "${snapshots[@]}"; do
      printf "$snapshot\n"
    done
  fi
}

# --------------------
# ------- MAIN -------
# --------------------

trap 'unmount_device_at_path "$backuppath"' EXIT

# Get the arguments
if [ $# -ge 1 ]; then
  arg="$1"
  shift 1
  if [[ "$arg" =~ "/dev/" ]]; then
    backupdevice="$arg"
  elif [[ "$arg" =~ $regex ]]; then
    backupdevice="UUID=$arg"
  else
    # Assume it is a label
    backupdevice="LABEL=$arg"
  fi
else
  show_syntax >&2
  exit 1
fi

if [[ "$EUID" != 0 ]]; then
  printx "This must be run as sudo.\n"
  exit 1
fi

mount_device_at_path "$backupdevice" "$backuppath"
list_snapshots "$backupdevice" "$snapshotpath"
