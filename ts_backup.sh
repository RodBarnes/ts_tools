#!/usr/bin/env bash

# Create a snapshot using rsync command as done by TimeShift.

# NOTE: This script expects to find the listed mountpoints.  If not present, it will create them.

source /usr/local/lib/colors

function printx {
  printf "${YELLOW}$1${NOCOLOR}\n"
}

function show_syntax {
  echo "Create a TimeShift-like snapshot of the system file excluding those identified in /etc/backup-excludes."
  echo "Syntax: $(basename $0) <backup_device> [-d|--dry-run] [-c|--comment comment]"
  echo "Where:  <backup_device> can be a backupdevice designator (e.g., /dev/sdb6), a UUID, or a filesystem LABEL."
  echo "        [-d|--dry-run] means to do a 'dry-run' test without actually restoring the snapshot."
  echo "        [-c|--comment comment] is a quote-bounded comment for the snapshot"
  echo "NOTE:   Must be run as sudo."
  exit
}

function mount_device_at_path {
  local device=$1 mount=$2 dir=$3
  
  # Ensure mount point exists
  if [ ! -d $mount ]; then
    sudo mkdir -p $mount &> /dev/null
    if [ $? -ne 0 ]; then
      printx "Unable to locate or create '$mount'." >&2
      exit 2
    fi
  fi

  # Attempt to mount the device
  sudo mount $device $mount &> /dev/null
  if [ $? -ne 0 ]; then
    printx "Unable to mount the backup backupdevice '$device'." >&2
    exit 2
  fi

  if [ ! -z $dir ] && [ ! -d "$mount/$dir" ]; then
    # Ensure the directory structure exists
    sudo mkdir "$mount/$dir" &> /dev/null
    if [ $? -ne 0 ]; then
      printx "Unable to locate or create '$mount/$dir'." >&2
      exit 2
    fi
  fi
}

function unmount_device_at_path {
  local mount=$1

  # Unmount if mounted
  if [ -d "$mount/fs" ]; then
    sudo umount $mount &> /dev/null
    if [ $? -ne 0 ]; then
      printx "Unable to locate or unmount '$mount'." >&2
      exit 2
    fi
  fi
}

function verify_available_space {
  local device=$1 minspace=$2

  # Check how much space is left
  space=$(df /mnt/backup | sed -n '2p;')
  IFS=' ' read dev size used avail pcent mount <<< $space
  if [[ $avail -lt $minspace ]]; then
    printx "The backupdevice '$device' has less only $avail space left of the total $size." >&2
    read -p "Do you want to proceed? (y/N) " yn
    if [[ $yn != "y" && $yn != "Y" ]]; then
      echo "Operation cancelled." >&2
      exit
    fi
  fi
}

function create_snapshot {
  local device=$1 path=$2 name=$3 note=$4 dry=$5

  # Create the snapshot
  if [ -n "$(find $path -mindepth 1 -maxdepth 1 -type f -o -type d 2> /dev/null)" ]; then
    echo "Creating incremental snapshot on '$device'..." >&2
    # Snapshots exist so create incremental snapshot referencing the latest
    sudo rsync -aAX $dry --delete --link-dest=../latest --exclude-from=/etc/ts_excludes / "$path/$name/"
  else
    echo "Creating full snapshot on '$device'..." >&2
    # This is the first snapshot so create full snapshot
    sudo rsync -aAX $dry --delete --exclude-from=/etc/ts_excludes / "$path/$name/"
  fi

  if [ -z $dry ]; then
    # This was NOT a dry run so...
    # Update "latest"
    ln -sfn $name $path/latest

    # Use a default comment if one was not provided
    if [ -z "$note" ]; then
      note="<no desc>"
    fi

    # Create comment in the snapshot directory
    echo "($(sudo du -sh $path/$name | awk '{print $1}')) $note" > "$path/$name/$g_descfile"

    # Done
    echo "The snapshot '$name' was successfully completed." >&2
  else
    echo "Dry run complete" >&2
  fi
}

# --------------------
# ------- MAIN -------
# --------------------

g_descfile=comment.txt
backuppath=/mnt/backup
backupdir="ts"
snapshotname=$(date +%Y-%m-%d-%H%M%S)
minimum_space=5000000


trap 'unmount_device_at_path "$backuppath"' EXIT

# Get the arguments
arg_short=dc:
arg_long=dry-run,comment:
arg_opts=$(getopt --options "$arg_short" --long "$arg_long" --name "$0" -- "$@")
if [ $? != 0 ]; then
  show_syntax
  exit 1
fi

eval set -- "$arg_opts"
while true; do
  case "$1" in
    -d|--dry-run)
      dryrun=true
      shift
      ;;
    -c|--comment)
      comment="$2"
      shift 2
      ;;
    --) # End of options
      shift
      break
      ;;
    *)
      echo "Error parsing arguments: arg=$1"
      exit 1
      ;;
  esac
done

uuid_regex="^\S{8}-\S{4}-\S{4}-\S{4}-\S{12}$"
if [ $# -ge 1 ]; then
  arg="$1"
  shift 1
  if [[ "$arg" =~ "/dev/" ]]; then
    backupdevice="$arg"
  elif [[ "$arg" =~ $uuid_regex ]]; then
    backupdevice="UUID=$arg"
  else
    # Assume it is a label
    backupdevice="LABEL=$arg"
  fi
else
  show_syntax >&2
  exit 1
fi

# echo "Device:$backupdevice"
# echo "Dry-run:$dryrun"
# echo "Comment:$comment"
# exit

# Confirm running as sudo
if [[ "$EUID" != 0 ]]; then
  printx "This must be run as sudo.\n"
  exit 1
fi

mount_device_at_path  "$backupdevice" "$backuppath" "$backupdir"
verify_available_space "$backupdevice" "$minimum_space"
create_snapshot "$backupdevice" "$backuppath/$backupdir" "$snapshotname" "$comment" "$dryrun"

echo "✅ Backup complete: $backuppath/$backupdir/$snapshotname"