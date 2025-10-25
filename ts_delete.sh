#!/usr/bin/env bash

# List the snapshots found on the specified backupdevice and allow selecting to delete.
# One of the following is required parameter: <backupdevice>, <label>, or <uuid> for mounting the backupdevice

# NOTE: This script expects to find the listed mountpoints.  If not present, it will fail.

source /usr/local/lib/colors

scriptname=$(basename $0)
backuppath=/mnt/backup
snapshotpath=$backuppath/snapshots
descfile=snapshot.desc
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

function mount_backup_device () {
  sudo mount $backupdevice $backuppath
  if [ $? -ne 0 ]; then
    printx "Unable to mount the backup backupdevice."
    exit 2
  fi
}

function unmount_backup_device () {
  sudo umount $backuppath
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

function parse_arguments () {
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

  # echo "Device:$backupdevice"
}

args=("$@")
argcnt=$#
if [ $argcnt == 0 ]; then
  show_syntax
fi

parse_arguments

if [[ "$EUID" != 0 ]]; then
  printx "This must be run as sudo.\n"
  exit 1
fi

# --------------------
# ------- MAIN -------
# --------------------

mount_backup_device
select_snapshot

if [ ! -z $snapshotname ]; then
  printx "This will completely DELETE the snapshot '$snapshotname' and is not recoverable."
  readx "Are you sure you want to proceed? (y/N) " yn
  if [[ $yn != "y" && $yn != "Y" ]]; then
    echo "Operation cancelled."
  else
    sudo rm -Rf $snapshotpath/$snapshotname
    echo "'$snapshotname' has been deleted."
    dircnt=$(find /mnt/backup/snapshots -mindepth 1 -type d | wc -l)
    if [[ $dircnt > 0 ]]; then
      # There are still backups so fix the link to latest
      latest=$(find /mnt/backup/snapshots -maxdepth 1 -type d -regextype posix-extended -regex '.*/[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}' | while read -r dir; do basename "$dir"; done | sort -r | head -n 1)
      ln -sfn $latest $snapshotpath/latest
    else
      sudo rm $snapshotpath/latest
    fi
  fi
fi

unmount_backup_device