#!/usr/bin/env bash

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
