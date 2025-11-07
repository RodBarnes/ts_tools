#!/usr/bin/env bash

# Restore a backup using rsync command as done by TimeShift.

# Error codes:
# 1 -- not running as sudo
# 2 -- device issues
# 3 -- operation failure

# NOTE: This script expects to find the listed mountpoints.  If not present, they will be created.

# Grok conversation URL: https://grok.com/c/61141f41-643d-4a52-93c1-a0e58cd443d7

source ts_functions.sh

function show_syntax {
  echo "Restore a snapshot created with ts_backup; emulates TimeShift."
  echo "Syntax: $(basename $0) <backup_device> <restore_device> [-d|--dry-run] [-g|--grub-install boot_device] [-s:snapshot snapshotname]"
  echo "Where:  <backup_device> and <restore_device> can be a device designator (e.g., /dev/sdb6), a UUID, or a filesystem LABEL."
  echo "        [-d|--dry-run] means to do a 'dry-run' test without actually creating the backup."
  echo "        [-g--grub-install boot_device] means to rebuild grub on the specified device; e.g., /dev/sda1."
  echo "        [-s|--snapshot snapshotname] is the name (timestamp) of the snapshot to restore -- if not present, a selection is presented."
  echo "NOTE:   Must be run as sudo."
  exit  
}

select_snapshot() {
  local path=$1

  local snapshots=() comment count name

  # Get the snapshots and allow selecting
  echo "Listing backup files..." >&2

  while IFS= read -r backup; do
    if [ -f "$path/$backup/$g_descfile" ]; then
      comment=$(cat "$path/$backup/$g_descfile")
    else
      comment="<no desc>"
    fi
    snapshots+=("${backup}: $comment")
  done < <( find $path -mindepth 1 -maxdepth 1 -type d | cut -d '/' -f5 )

  # Get the count of options and increment to include the cancel
  count="${#snapshots[@]}"
  ((count++))

  COLUMNS=1
  select selection in "${snapshots[@]}" "Cancel"; do
    if [[ "$REPLY" =~ ^[0-9]+$ && "$REPLY" -ge 1 && "$REPLY" -le $count ]]; then
      case ${selection} in
        "Cancel")
          # If the user decides to cancel...
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

  echo "$name"
}

get_bootfile() {
  local restpath=$1

  local setupmode
  local securebootval
  local securebootvar="/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"
  local setupmodevar="/sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c"

  echo "---${FUNCNAME}---" &>> "$g_outputfile"

  # Check Secure Boot status
  echo "Checking SecureBoot EFI variable" &>> "$g_outputfile"
  if [ -f "$securebootvar" ]; then
    securebootval=$(sudo hexdump -v -e '/1 "%02x"' "$securebootvar" | tail -c 2)
    echo "SecureBoot last byte: $securebootval" &>> "$g_outputfile"
    if [ -f "$setupmodevar" ]; then
      setupmode=$(sudo hexdump -v -e '/1 "%02x"' "$setupmodevar" | tail -c 2)
      echo "SetupMode last byte: $setupmode" &>> "$g_outputfile"
    else
      echo "SetupMode variable not found" &>> "$g_outputfile"
    fi
    if [ "$securebootval" = "01" ]; then
      # Secure Boot enabled; use shimx64.efi if present
      if [ -f "$restpath/boot/efi/EFI/debian/shimx64.efi" ]; then
        g_bootfile="shimx64.efi"
        echo "SecureBoot enabled (EFI variable: $securebootval); using $g_bootfile." &>> "$g_outputfile"
      else
        echo "SecureBoot enabled but shimx64.efi not found; using $g_bootfile." &>> "$g_outputfile"
      fi
    else
      echo "SecureBoot disabled (EFI variable: $securebootval); using $g_bootfile." &>> "$g_outputfile"
    fi
  else
    echo "SecureBoot variable not found; defaulting to $g_bootfile" &>> "$g_outputfile"
    if [ -f "$setupmodevar" ]; then
      setupmode=$(sudo hexdump -v -e '/1 "%02x"' "$setupmodevar" | tail -c 2)
      echo "SetupMode last byte: $setupmode" &>> "$g_outputfile"
    fi
  fi
}

validate_boot_config() {
  local restdev=$1 restpath=$2

  local boot_valid=1

  echo "---${FUNCNAME}---" &>> "$g_outputfile"

  # Boot build was not requested so validate restored boot components
  # To see if it should be done anyway...
  echo "Validating restored boot components..." >&2
  if [ ! -f "$restpath/boot/grub/grub.cfg" ]; then
    echo "Warning: $restpath/boot/grub/grub.cfg not found" &>> "$g_outputfile"
    boot_valid=0
  fi
  if [ ! -d "$restpath/boot/grub" ]; then
    echo "Warning: $restpath/boot/grub directory not found" &>> "$g_outputfile"
    boot_valid=0
  fi
  if [ -z "$(ls $restpath/boot/vmlinuz* 2>/dev/null)" ]; then
    echo "Warning: No kernel images found in $restpath/boot/vmlinuz*" &>> "$g_outputfile"
    boot_valid=0
  fi
  if [ ! -f "$restpath/boot/efi/EFI/debian/$g_bootfile" ]; then
    echo "Warning: Bootloader file $restpath/boot/efi/EFI/debian/$g_bootfile not found" &>> "$g_outputfile"
    boot_valid=0
  fi
  if [ $boot_valid -eq 0 ]; then
    # There is an issue with the boot configuration
    printx "The boot configuration on '$restdev' seems incorrect.  To ensure it is bootable" >&2
    printx "it is recommended to update/install grub and verify/establish a EFI boot entry.  Proceed?" >&2
    while true; do
      readx "Enter the boot device (or press ENTER to skip):" bootdevice
      if [ -z "$bootdevice" ]; then
        printx "Skipping GRUB setup. Ensure the EFI boot entry is configured manually." >&2
        break
      elif sudo lsblk $bootdevice &> /dev/null; then
        break
      else
        printx "That is not a recognized device." >&2
      fi
    done
  else
    echo "Boot configuration appears valid." &>> "$g_outputfile"
  fi
}

build_boot() {
  local restdev=$1 restpath=$2

  local osid=$(grep "^ID=" "$restpath/etc/os-release" | cut -d'=' -f2 | tr -d '"')
  local partno=$(lsblk -no PARTN "$restdev" 2>/dev/null || echo "2")

  echo "---${FUNCNAME}---" &>> "$g_outputfile"

  # Mount the necessary directories
  sudo mount $bootdevice "$restpath/boot/efi"
  if [ $? -ne 0 ]; then
    printx "Unable to mount the EFI System Partition on $bootdevice." >&2
    exit 2
  fi
  sudo mount --bind /dev "$restpath/dev"
  sudo mount --bind /proc "$restpath/proc"
  sudo mount --bind /sys "$restpath/sys"
  sudo mount --bind /dev/pts "$restpath/dev/pts"

  echo "Installing grub on $restdev..." >&2
  sudo chroot "$restpath" grub-install --target=x86_64-efi --efi-directory=/boot/efi --boot-directory=/boot &>> "$g_outputfile"
  if [ $? -ne 0 ]; then
    printx "Something went wrong with 'grub-install'.  Check '$g_outputfile' for details." >&2
  fi
  
  echo "Updating grub on $restdev..." >&2
  # Use chroot to rebuild grub on the restored partion
  sudo chroot "$restpath" update-grub &>> "$g_outputfile"
  if [ $? -ne 0 ]; then
    printx "Something went wrong with 'update-grub'.  Check '$g_outputfile' for details." >&2
  fi
  
  echo "Checking EFI on $bootdevice" >&2
  # Check for an existing boot entry
  sudo efibootmgr | grep -q "$osid" &>> "$g_outputfile"
  if ! sudo efibootmgr | grep -q "$osid"; then
    echo "Building the UEFI boot entry on $bootdevice with an entry for $restdev..." >&2

    # Set UEFI boot entry -- where partno is the target partition for the boot entry
    sudo efibootmgr -c -d $bootdevice -p $partno -L $osid -l "/EFI/$osid/$g_bootfile" &>> "$g_outputfile"
    if [ $? -ne 0 ]; then
      printx "Something went wrong with 'efibootmgr'. Check '$g_outputfile' for details." >&2
    fi
  else
    echo "Confirmed EFI boot entry for '$osid' exists." &>> "$g_outputfile"
  fi

  if [ ! -f "$restorepath/boot/efi/EFI/BOOT/BOOTX64.EFI" ]; then
    # Copy bootloader to default EFI path as a fall back
    sudo cp "$restpath/boot/efi/EFI/$osid/$g_bootfile" "$restpath/boot/efi/EFI/BOOT/BOOTX64.EFI" &>> "$g_outputfile"
    if [ $? -ne 0 ]; then
      echo "Warning: Failed to copy $g_bootfile to EFI/BOOT/BOOTX64.EFI" &>> "$g_outputfile"
    else
      echo "Successfully copied $g_bootfile to EFI/BOOT/BOOTX64.EFI" &>> "$g_outputfile"
    fi
  else
    echo "Confirmed '$restorepath/boot/efi/EFI/BOOT/BOOTX64.EFI' exists for fallback." &>> "$g_outputfile"
  fi

  # Unbind the directories
  sudo umount "$restpath/boot/efi" "$restpath/dev/pts" "$restpath/dev" "$restpath/proc" "$restpath/sys"
}

restore_snapshot() {
  local backpath=$1 name=$2 restpath=$3

  local excludespathname="/etc/ts_excludes"

  echo "---${FUNCNAME}---" &>> "$g_outputfile"

  # Restore the snapshot
  echo rsync -aAX --delete --verbose "--exclude-from=$excludespathname" "$backpath/$name/" "$restpath/" &>> "$g_outputfile"
  sudo rsync -aAX --delete --verbose "--exclude-from=$excludespathname" "$backpath/$name/" "$restpath/" &>> "$g_outputfile"
  if [ $? -ne 0 ]; then
    printx "Something went wrong with the restore.  Check '$g_outputfile' for details." >&2
    exit 3
  fi

  if [ -f "$backpath/$g_descfile" ]; then
    # Delete the description file from the target
    sudo rm "$backpath/$g_descfile"
  fi
}

dryrun_snapshot() {
  local backpath=$1 name=$2 restpath=$3

  local excludespathname="/etc/ts_excludes"

  echo "---${FUNCNAME}---" &>> "$g_outputfile"

  # Do a dry run and record the output
  echo rsync -aAX --dry-run --delete --verbose "--exclude-from=$excludespathname" "$backpath/$name/" "$restpath/" &>> "$g_outputfile"
  sudo rsync -aAX --dry-run --delete --verbose "--exclude-from=$excludespathname" "$backpath/$name/" "$restpath/" &>> "$g_outputfile"
}

# --------------------
# ------- MAIN -------
# --------------------

g_bootfile="grubx64.efi"  # Default for non-secure boot
g_descfile=comment.txt
g_outputfile="/tmp/ts_restore.out"
backuppath="/mnt/backup"
backupdir="ts"
restorepath="/mnt/restore"

trap 'unmount_device_at_path "$backuppath"; unmount_device_at_path "$restorepath"' EXIT

# Get the arguments
arg_short=dg:s:
arg_long=dry-run,grub-install:,snapshot:
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
    -g|--grub-install)
      bootdevice="$2"
      shift 2
      ;;
    -s|--snapshot)
      snapshotname="$2"
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
if [ $# -ge 2 ]; then
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
  arg="$1"
  shift 1
  if [[ "$arg" =~ "/dev/" ]]; then
    restoredevice="$arg"
  elif [[ "$arg" =~ $uuid_regex ]]; then
    restoredevice="UUID=$arg"
  else
    # Assume it is a label
    restoredevice="LABEL=$arg"
  fi
else
  show_syntax >&2
  exit 1
fi

# echo "Backup device:$backupdevice"
# echo "Restore device:$restoredevice"
# echo "Dry-run:$dryrun"
# echo "Boot device:$bootdevice"
# echo "Snapshot:$snapshotname"
# exit

if [[ "$EUID" != 0 ]]; then
  printx "This must be run as sudo.\n"
  exit 1
fi

if [ ! -e $restoredevice ]; then
  printx "There is no such device: $restoredevice."
  exit 2
fi

# Initialize the log file
echo &> "$g_outputfile"

mount_device_at_path "$restoredevice" "$restorepath"
mount_device_at_path "$backupdevice" "$backuppath" "$backupdir"

# Since a snapshot was not specified, present a list for selection
if [ -z $snapshotname ]; then
  snapshotname=$(select_snapshot "$backuppath/$backupdir")
fi

if [ ! -z $snapshotname ]; then
  if [ -z $dryrun ]; then
    printx "This will completely OVERWRITE the operating system on '$restoredevice'."
    readx "Are you sure you want to proceed? (y/N) " yn
    if [[ $yn != "y" && $yn != "Y" ]]; then
      echo "Operation cancelled."
      exit
    fi
    echo "Restoring '$snapshotname' to '$restoredevice'..."
    restore_snapshot "$backuppath/$backupdir" "$snapshotname" "$restorepath"

    # echo "Before get_bootfile..."
    # echo "restoredevice=$restoredevice"
    # echo "g_bootfile=$g_bootfile"
    # echo "bootdevice=$bootdevice"
    # echo
    get_bootfile "$restorepath"

    if [ -z $bootdevice ]; then
      # echo "Before validate_boot_config..."
      # echo "restoredevice=$restoredevice"
      # echo "g_bootfile=$g_bootfile"
      # echo "bootdevice=$bootdevice"
      # echo
      validate_boot_config "$restoredevice" "$restorepath"
    fi

    if [ ! -z $bootdevice ]; then
      # echo "Before get_build_boot..."
      # echo "restoredevice=$restoredevice"
      # echo "g_bootfile=$g_bootfile"
      # echo "bootdevice=$bootdevice"
      # echo
      build_boot "$restoredevice" "$restorepath"
    fi

    # echo "After all boot stuff..."
    # echo "restoredevice=$restoredevice"
    # echo "g_bootfile=$g_bootfile"
    # echo "bootdevice=$bootdevice"
    # echo

    # Done
    echo "✅ Restore complete: $backuppath/$backupdir/$snapshotname"
    echo "The system may now be rebooted into the restored partition."
  else
    echo "Performing dry-run restore of '$snapshotname' to '$restoredevice'..."
    dryrun_snapshot "$backuppath/$backupdir" "$snapshotname" "$restorepath"
  fi
  echo "Details of the operation can be viewed in these files found in /tmp: $g_outputfile"
else
  echo "Operation cancelled."
fi
