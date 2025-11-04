#!/usr/bin/env bash

# Create a snapshot using rsync command as done by TimeShift.
# One of the followin is required parameter: <backupdevice>, <label>, or <uuid> for mounting the backupdevice
# Optional parameter: <desc> -- Description of the snapshot, quote-bounded
# Optional parameter: -t -- Include to do a dry-run

# NOTE: This script expects to find the listed mountpoints.  If not present, it will create them.

source /usr/local/lib/colors

scriptname=$(basename $0)
backuppath=/mnt/backup
snapshotpath=$backuppath/ts
snapshotname=$(date +%Y-%m-%d-%H%M%S)
descfile=comment.txt
minspace=5000000
regex="^\S{8}-\S{4}-\S{4}-\S{4}-\S{12}$"

function printx {
  printf "${YELLOW}$1${NOCOLOR}\n"
}

function show_syntax () {
  echo "Create a TimeShift-like snapshot of the system file excluding those identified in /etc/backup-excludes."
  echo "Syntax: $scriptname <backup_device> [-d|--dry-run] [-c|--comment comment]"
  echo "Where:  <backup_device> can be a backupdevice designator (e.g., /dev/sdb6), a UUID, or a filesystem LABEL."
  echo "        [-d|--dry-run] means to do a 'dry-run' test without actually restoring the snapshot."
  echo "        [-c|--comment comment] is a quote-bounded comment for the snapshot"
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

function verify_available_space () {
  # Check how much space is left
  space=$(df /mnt/backup | sed -n '2p;')
  IFS=' ' read dev size used avail pcent mount <<< $space
  if [[ $avail -lt $minspace ]]; then
    printx "The backupdevice '$backupdevice' has less only $avail space left of the total $size."
    read -p "Do you want to proceed? (y/N) " yn
    if [[ $yn != "y" && $yn != "Y" ]]; then
      echo "Operation cancelled."
      unmount_backup_device
      exit
    fi
  fi
}

function create_snapshot () {
  # Create the snapshot
  if [ -n "$(find $snapshotpath -mindepth 1 -maxdepth 1 -type f -o -type d 2> /dev/null)" ]; then
    echo "Creating incremental snapshot on '$backupdevice'..."
    # Snapshots exist so create incremental snapshot referencing the latest
    sudo rsync -aAX $dryrun --delete --link-dest=../latest --exclude-from=/etc/ts_excludes / "$snapshotpath/$snapshotname/"
  else
    echo "Creating full snapshot on '$backupdevice'..."
    # This is the first snapshot so create full snapshot
    sudo rsync -aAX $dryrun --delete --exclude-from=/etc/ts_excludes / "$snapshotpath/$snapshotname/"
  fi

  if [ -z $dryrun ]; then
    # This was NOT a dry run so...
    # Update "latest"
    ln -sfn $snapshotname $snapshotpath/latest

    # Use a default description if one was not provided
    if [ -z "$description" ]; then
      description="<no desc>"
    fi

    # Create description in the snapshot directory
    echo "($(sudo du -sh $snapshotpath/$snapshotname | awk '{print $1}')) $description" > "$snapshotpath/$snapshotname/$descfile"

    # Done
    echo "The snapshot '$snapshotname' was successfully completed."
  else
    echo "Dry run complete"
  fi
}

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
      description="$2"
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

# echo "Device:$backupdevice"
# echo "Dry-run:$dryrun"
# echo "Desc:$description"
# exit

# Confirm running as sudo
if [[ "$EUID" != 0 ]]; then
  printx "This must be run as sudo.\n"
  exit 1
fi

# --------------------
# ------- MAIN -------
# --------------------

trap 'unmount_device_at_path "$backuppath"' EXIT

mount_device_at_path  "$backupdevice" "$backuppath"
verify_available_space
create_snapshot

echo "✅ Backup complete: $snapshotpath/$snapshotname"