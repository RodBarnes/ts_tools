#!/usr/bin/env bash

# Collection of functions used by ts_tools

source /usr/local/lib/colors

printx() {
  printf "${YELLOW}$1${NOCOLOR}\n"
}

readx() {
  printf "${YELLOW}$1${NOCOLOR}"
  read -p "" $2
}

mount_device_at_path() {
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

unmount_device_at_path() {
  local path=$1

  # Unmount if mounted
  if mountpoint -q $path; then
    sudo umount $path &> /dev/null
    if [ $? -ne 0 ]; then
      printx "Unable to locate or unmount '$path'." >&2
      exit 2
    fi
  fi
}

select_snapshot() {
  local device=$1 path=$2

  local snapshots=() comment count name

  # Get the snapshots and allow selecting
  while IFS= read -r backup; do
    if [ -f "$path/$backup/$g_descfile" ]; then
      comment=$(cat "$path/$backup/$g_descfile")
    else
      comment="<no desc>"
    fi
    snapshots+=("${backup}: $comment")
  done < <( find $path -mindepth 1 -maxdepth 1 -type d | cut -d '/' -f5 )

  if [ ${#snapshots[@]} -eq 0 ]; then
    printx "There are no backups on $device" >&2
  else
    echo "Listing backup files..." >&2

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
            name="${selection%%:*}"
            break
            ;;
        esac
      else
        printx "Invalid selection. Please enter a number between 1 and $count." >&2
      fi
    done
  fi

  echo "$name"
}