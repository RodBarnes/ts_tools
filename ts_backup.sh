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
    printx "The backupdevice '$device' has less only $avail space left of the total $size." >&2
    read -p "Do you want to proceed? (y/N) " yn
    if [[ $yn != "y" && $yn != "Y" ]]; then
      echo "Operation cancelled." >&2
      exit
    else
      echo "User acknowledged that backup device has less than $avail space but proceeded." &>> "$g_outputfile"
    fi
  else
    echo "Backup device has $avail or more space avaiable; proceeding with backup." &>> "$g_outputfile"
  fi
}

create_snapshot() {
  local device=$1 path=$2 name=$3 note=$4 dry=$5 perm=$6

  if [[ ! -z $perm ]]; then
    echo "The backup device does not support permmissions or ownership." >&2
    echo "The rsync will be performed without attempting to set these options." >&2
  fi

  # Get the name of the most recent backup
  local latest=$(ls -1 "$path" | grep -E '^[0-9]{8}_[0-9]{6}$' | sort -r | sed -n '1p;')
  local type

  # Create the snapshot
  if [ ! -z $latest ]; then
    echo "Creating incremental snapshot on '$device'..." >&2
    type="incr"
    # Snapshots exist so create incremental snapshot referencing the latest
    sudo rsync -aAX $dry $perm --delete --link-dest="$g_backuppath/$latest" --exclude-from=/etc/ts_excludes / "$path/$name/" &>> "$g_outputfile"
  else
    echo "Creating full snapshot on '$device'..." >&2
    type="full"
    # This is the first snapshot so create full snapshot
    sudo rsync -aAX $dry $perm --delete --exclude-from=/etc/ts_excludes / "$path/$name/" &>> "$g_outputfile"
  fi

  if [ -z $dry ]; then
    # Use a default comment if one was not provided
    if [ -z "$note" ]; then
      note="<no desc>"
    fi

    # Create comment in the snapshot directory
    echo "($type $(sudo du -sh $path/$name | awk '{print $1}')) $note" > "$path/$name/$g_descfile"

    # Done
    echo "The snapshot '$name' was successfully completed." >&2
  else
    echo "Dry run complete" >&2
  fi
}

check_rsync_perm() {
  local path=$1

  unset noperm
  local fstype=$(lsblk --output MOUNTPOINTS,FSTYPE | grep "$path" | tr -s ' ' | cut -d ' ' -f2)
  echo "Backup device type is: $fstype" &>> "$g_outputfile" 
  case "$fstype" in
    "vfat"|"exfat")
      echo "NOTE: The backup device '$backupdevice' is $fstype." >&2
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
    echo "Using options '$noperm' to prevent attempt to change ownership or permissions." &>> "$g_outputfile"
  fi

  echo $noperm
}

# --------------------
# ------- MAIN -------
# --------------------

snapshotname=$(date +%Y%m%d_%H%M%S)
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

# echo "Device:$backupdevice"
# echo "Dry-run:$dryrun"
# echo "Comment:$comment"
# exit

# Confirm running as sudo
if [[ "$EUID" != 0 ]]; then
  printx "This must be run as sudo.\n"
  exit 1
fi

# Initialize the log file
echo -n &> "$g_outputfile"

mount_device_at_path  "$backupdevice" "$g_backuppath" "$g_backupdir"
verify_available_space "$backupdevice" "$g_backuppath" "$minimum_space"
perm_opt=$(check_rsync_perm "$g_backuppath")
create_snapshot "$backupdevice" "$g_backuppath/$g_backupdir" "$snapshotname" "$comment" "$dryrun" "$perm_opt"

echo "✅ Backup complete: $g_backuppath/$g_backupdir/$snapshotname"
echo "Details of the operation can be viewed in the file '$g_outputfile'"