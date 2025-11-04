#!/usr/bin/env bash

# List the snapshots found on the specified backupdevice and allow selecting to delete.
# One of the following is required parameter: <backupdevice>, <label>, or <uuid> for mounting the backupdevice

# NOTE: This script expects to find the listed mountpoints.  If not present, it will fail.

source /usr/local/lib/colors

scriptname=$(basename $0)
backuppath=/mnt/backup
snapshotpath=$backuppath/ts
descfile=comment.txt
regex="^\S{8}-\S{4}-\S{4}-\S{4}-\S{12}$"

function printx {
  printf "${YELLOW}$1${NOCOLOR}\n"
}

function readx {
  printf "${YELLOW}$1${NOCOLOR}"
  read -p "" $2
}

function show_syntax () {
  echo "Delete a snapshot created with ts_backup."
  echo "Syntax: $scriptname <backup_device>"
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

function select_snapshot () {
  # Get the snapshots
  unset snapshots
  while IFS= read -r LINE; do
    snapshot=("${LINE}")
    if [ -f "$snapshotpath/$snapshot/$descfile" ]; then
      description="$(cat $snapshotpath/$snapshot/$descfile)"
    else
      description="<no desc>"
    fi
    snapshots+=("$snapshot: $description")
  done < <(find $snapshotpath -mindepth 1 -maxdepth 1 -type d | sort -r | cut -d '/' -f5)

  if [ ${#snapshots[@]} -eq 0 ]; then
    printx "There are no backups on $backupdevice"
  else
    printx "Snapshot files on $backupdevice"
    # Get the count of options and increment to include the cancel
    count="${#snapshots[@]}"
    ((count++))

    COLUMNS=1
    select selection in "${snapshots[@]}" "Cancel"; do
      if [[ "$REPLY" =~ ^[0-9]+$ && "$REPLY" -ge 1 && "$REPLY" -le $count ]]; then
        case ${selection} in
          "Cancel")
            # If the user decides to cancel...
            echo "Operation cancelled."
            break
            ;;
          *)
            snapshotname=$(echo $selection | cut -d ':' -f1)
            break
            ;;
        esac
      else
        printx "Invalid selection. Please enter a number between 1 and $count."
      fi
    done
  fi
}

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

# --------------------
# ------- MAIN -------
# --------------------

trap 'unmount_device_at_path "$backuppath"' EXIT

mount_device_at_path "$backupdevice" "$backuppath"
select_snapshot

if [ ! -z $snapshotname ]; then
  printx "This will completely DELETE the snapshot '$snapshotname' and is not recoverable."
  readx "Are you sure you want to proceed? (y/N) " yn
  if [[ $yn != "y" && $yn != "Y" ]]; then
    echo "Operation cancelled."
  else
    sudo rm -Rf $snapshotpath/$snapshotname
    echo "'$snapshotname' has been deleted."
    dircnt=$(find "$snapshotpath" -mindepth 1 -type d | wc -l)
    if [[ $dircnt > 0 ]]; then
      # There are still backups so fix the link to latest
      latest=$(find "$snapshotpath" -maxdepth 1 -type d -regextype posix-extended -regex '.*/[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}' | while read -r dir; do basename "$dir"; done | sort -r | head -n 1)
      ln -sfn $latest $snapshotpath/latest
    else
      sudo rm $snapshotpath/latest
    fi
  fi
fi
