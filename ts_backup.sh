#!/usr/bin/env bash

# Create a snapshot using rsync command as done by TimeShift.

source /usr/local/lib/ts_shared

show_syntax() {
  echo "Create a TimeShift-like snapshot of the system file excluding those identified in /etc/backup-excludes."
  echo "Syntax: $(basename $0) <backup_device> [-d|--dry-run] [-c|--comment comment]"
  echo "Where:  <backup_device> can be a device designator (e.g., /dev/sdb6), a UUID, filesystem LABEL, or partition UUID"
  echo "        [-d|--dry-run] means to do a 'dry-run' test without actually restoring the snapshot."
  echo "        [-c|--comment comment] is a quote-bounded comment for the snapshot"
  echo "NOTE:   Must be run as sudo."
  exit
}

verify_available_space() {
  local device=$1 path=$2 minspace=$3

  # Check how much space is left
  line=$(df "$path" -BG | sed -n '2p;')
  IFS=' ' read dev size used avail pcent mount <<< $line
  space=${avail%G}
  if [[ $space -lt $minspace ]]; then
    showx "The backupdevice '$device' has less only $avail space left of the total $size."
    read -p "Do you want to proceed? (y/N) " yn
    if [[ $yn != "y" && $yn != "Y" ]]; then
      show "Operation cancelled."
      exit
    else
      echo "User acknowledged that backup device has less than $avail space but proceeded." &>> "$g_logfile"
    fi
  else
    echo "Backup device has $avail or more space avaiable; proceeding with backup." &>> "$g_logfile"
  fi
}

create_snapshot() {
  local device=$1 path=$2 name=$3 note=$4 dry=$5 perm=$6

  if [[ ! -z $perm ]]; then
    show "The backup device does not support permmissions or ownership."
    show "The rsync will be performed without attempting to set these options."
  fi

  # Get the name of the most recent backup
  local latest=$(ls -1 "$path" | grep -E '^[0-9]{8}_[0-9]{6}$' | sort -r | sed -n '1p;')
  local type

  if [ -f "$g_excludesfile" ]; then
    excludearg="--exclude-from=$g_excludesfile"
  else
    printx "No excludes file found at '$g_excludesfile'."
    readx "Proceed with a complete backup with no exclusions (y/N)" yn
    if [[ $yn != "y" && $yn != "Y" ]]; then
      show "Operation cancelled."
      exit
    fi
  fi

  # Create the snapshot
  if [ ! -z $latest ]; then
    show "Creating incremental snapshot on '$device'..."
    type="incr"
    # Snapshots exist so create incremental snapshot referencing the latest
    echo "rsync -aAX $dry $perm --delete --link-dest=\"$g_backuppath/$g_backupdir/$latest\" $excludearg / \"$path/$name/\"" &>> "$g_logfile"
    sudo rsync -aAX $dry $perm --delete --link-dest="$g_backuppath/$g_backupdir/$latest" $excludearg / "$path/$name/" &>> "$g_logfile"
  else
    show "Creating full snapshot on '$device'..."
    type="full"
    # This is the first snapshot so create full snapshot
    echo "rsync -aAX $dry $perm --delete $excludearg / \"$path/$name/\"" &>> "$g_logfile"
    sudo rsync -aAX $dry $perm --delete $excludearg / "$path/$name/" &>> "$g_logfile"
  fi

  if [ -z $dry ]; then
    # Use a default comment if one was not provided
    if [ -z "$note" ]; then
      note="<no desc>"
    fi

    # Create comment in the snapshot directory
    echo "($type $(sudo du -sh $path/$name | awk '{print $1}')) $note" > "$path/$name/$g_descfile"

    # Done
    show "The snapshot '$name' was successfully completed."
  else
    show "Dry run complete"
  fi
}

check_rsync_perm() {
  local path=$1

  unset noperm
  local fstype=$(lsblk --output MOUNTPOINTS,FSTYPE | grep "$path" | tr -s ' ' | cut -d ' ' -f2)
  echo "Backup device type is: $fstype" &>> "$g_logfile"
  case "$fstype" in
    "vfat"|"exfat")
      show "NOTE: The backup device '$backupdevice' is $fstype."
      noperm="--no-perms --no-owner"
      ;;
    "ntfs")
      sudo pgrep -a ntfs-3g | grep "$path" | grep -q "permissions" 
      if [ $? -ne 0 ]; then
          # Permissions not found
          noperm="--no-perms --no-owner"
      fi
      ;;
    *)
      ;;
  esac

  if [ ! -z $noperm ]; then
    echo "Using options '$noperm' to prevent attempt to change ownership or permissions." &>> "$g_logfile"
  fi

  echo $noperm
}

# --------------------
# ------- MAIN -------
# --------------------

snapshotname=$g_timestamp
minimum_space=5 # Amount in GB

trap 'unmount_device_at_path "$g_backuppath"' EXIT

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

# show "g_backuppath=$g_backuppath"
# show "g_backupdir=$g_backupdir"
# show "g_logfile=$g_logfile"
# show "backupdevice=$backupdevice"
# show "snapshotname=$snapshotname"
# show "minimum_space=$minimum_space"
# show "dryrun=$dryrun"
# show "comment=$comment"
# exit

# Confirm running as sudo
if [[ "$EUID" != 0 ]]; then
  printx "This must be run as sudo.\n"
  exit 1
fi

# Initialize the log file
echo -n &> "$g_logfile"

mount_device_at_path  "$backupdevice" "$g_backuppath" "$g_backupdir"
verify_available_space "$backupdevice" "$g_backuppath" "$minimum_space"
perm_opt=$(check_rsync_perm "$g_backuppath")
create_snapshot "$backupdevice" "$g_backuppath/$g_backupdir" "$snapshotname" "$comment" "$dryrun" "$perm_opt"

echo "✅ Backup complete: $g_backuppath/$g_backupdir/$snapshotname"
echo "Details of the operation can be viewed in the file '$g_logfile'"