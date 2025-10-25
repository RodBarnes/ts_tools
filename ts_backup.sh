#!/usr/bin/env bash

# Create a snapshot using rsync command as done by TimeShift.
# One of the followin is required parameter: <backupdevice>, <label>, or <uuid> for mounting the backupdevice
# Optional parameter: <desc> -- Description of the snapshot, quote-bounded
# Optional parameter: -t -- Include to do a dry-run

# NOTE: This script expects to find the listed mountpoints.  If not present, it will fail.

source /usr/local/lib/colors

scriptname=$(basename $0)
backuppath=/mnt/backup
snapshotpath=$backuppath/snapshots
snapshotname=$(date +%Y-%m-%d-%H%M%S)
descfile=snapshot.desc
minspace=5000000
regex="^\S{8}-\S{4}-\S{4}-\S{4}-\S{12}$"

function printx {
  printf "${YELLOW}$1${NOCOLOR}\n"
}

function show_syntax () {
  echo "Create a TimeShift-like snapshot of the system file excluding those identified in /etc/backup-excludes."
  echo "Syntax: $scriptname <backup_device> [-d] [-c comment]"
  echo "Where:  <backup_device> can be a backupdevice designator (e.g., /dev/sdb6), a UUID, or a filesystem LABEL."
  echo "        [-d] means to do a 'dry-run' test without actually restoring the snapshot."
  echo "        [-c comment] is a quote-bounded comment for the snapshot"
  echo "NOTE:   Must be run as sudo."
  exit
}

function mount_backup_device () {
  if [ ! -d $backuppath ]; then
    printx "'$backuppath' was not found; creating it..."
    sudo mkdir $backuppath
  fi

  sudo mount $backupdevice $backuppath
  if [ $? -ne 0 ]; then
    printx "Unable to mount the backup backupdevice."
    exit 2
  fi
}

function unmount_backup_device () {
  sudo umount $backuppath
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

function parse_arguments() {
  # Get the backup_device
  i=0
  if [[ "${args[$i]}" =~ "/dev/" ]]; then
    backupdevice="${args[$i]}"
  elif [[ "${args[$i]}" =~ $regex ]]; then
    backupdevice="UUID=${args[$i]}"
  else
    # Assume it is a label
    backupdevice="LABEL=${args[$i]}"
  fi

  # Get optional parameters
  i=1
  while [ $i -lt $argcnt ]; do
    if [ "${args[$i]}" == "-t" ]; then
      dryrun=--dry-run
    elif [ "${args[$i]}" == "-c" ]; then
      ((i++))
      description="${args[$i]}"
    fi
    ((i++))
  done

  # echo "Device:$backupdevice"
  # echo "Dry-run:$dryrun"
  # echo "Desc:$description"
}

args=("$@")
argcnt=$#
if [ $argcnt == 0 ]; then
  show_syntax
fi

parse_arguments

# Confirm running as sudo
if [[ "$EUID" != 0 ]]; then
  printx "This must be run as sudo.\n"
  exit 1
fi

# --------------------
# ------- MAIN -------
# --------------------

mount_backup_device
verify_available_space
create_snapshot
unmount_backup_device
