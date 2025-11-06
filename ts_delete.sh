#!/usr/bin/env bash

# List the snapshots found on the specified backupdevice and allow selecting to delete.
# One of the following is required parameter: <backupdevice>, <label>, or <uuid> for mounting the backupdevice

# NOTE: This script expects to find the listed mountpoints.  If not present, it will fail.

source /usr/local/lib/colors

function printx {
  printf "${YELLOW}$1${NOCOLOR}\n"
}

function readx {
  printf "${YELLOW}$1${NOCOLOR}"
  read -p "" $2
}

function show_syntax {
  echo "Delete a snapshot created with ts_backup."
  echo "Syntax: $(basename $0) <backup_device>"
  echo "Where:  <backup_device> can be a backupdevice designator (e.g., /dev/sdb6), a UUID, or a filesystem LABEL."
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
  if [ -d "$mount" ]; then
    sudo umount $mount &> /dev/null
    if [ $? -ne 0 ]; then
      printx "Unable to locate or unmount '$mount'." >&2
      exit 2
    fi
  fi
}

function select_snapshot {
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

function delete_snapshot {
  local path=$1 name=$2

  local dircnt latest

  printx "This will completely DELETE the snapshot '$name' and is not recoverable." >&2
  readx "Are you sure you want to proceed? (y/N) " yn
  if [[ $yn != "y" && $yn != "Y" ]]; then
    echo "Operation cancelled." >&2
  else
    sudo rm -Rf $path/$name
    echo "'$name' has been deleted." >&2
    dircnt=$(find "$path" -mindepth 1 -type d | wc -l)
    if [[ $dircnt > 0 ]]; then
      # There are still backups so fix the link to latest
      latest=$(find "$path" -maxdepth 1 -type d -regextype posix-extended -regex '.*/[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}' | while read -r dir; do basename "$dir"; done | sort -r | head -n 1)
      ln -sfn $latest $path/latest
    else
      sudo rm $path/latest
    fi
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

if [[ "$EUID" != 0 ]]; then
  printx "This must be run as sudo.\n"
  exit 1
fi

mount_device_at_path "$backupdevice" "$backuppath" "$backupdir"
snapshotname=$(select_snapshot "$backupdevice" "$backuppath/$backupdir")

if [ ! -z $snapshotname ]; then
  delete_snapshot "$backuppath/$backupdir" "$snapshotname"
fi
