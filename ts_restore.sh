#!/usr/bin/env bash

# Restore a backup using rsync command as done by TimeShift.

# Error codes:
# 1 -- not running as sudo
# 2 -- device issues
# 3 -- operation failure

# NOTE: This script expects to find the listed mountpoints.  If not present, they will be created.

# Grok conversation URL: https://grok.com/c/61141f41-643d-4a52-93c1-a0e58cd443d7

source /usr/local/lib/colors

function printx {
  printf "${YELLOW}$1${NOCOLOR}\n"
}

function readx {
  printf "${YELLOW}$1${NOCOLOR}"
  read -p "" $2
}

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
  if [ -d "$mount/fs" ]; then
    sudo umount $mount &> /dev/null
    if [ $? -ne 0 ]; then
      printx "Unable to locate or unmount '$mount'." >&2
      exit 2
    fi
  fi
}

function select_snapshot {
  # Get the snapshots and allow selecting
  echo "Listing backup files..."

  # Get the snapshots
  unset snapshots
  while IFS= read -r backup; do
    echo "path=$g_snapshotpath/$backup/$g_descfile" >&2
    if [ -f "$g_snapshotpath/$backup/$g_descfile" ]; then
      comment=$(cat "$g_snapshotpath/$backup/$g_descfile")
    else
      comment="<no desc>"
    fi
    snapshots+=("${backup}: $comment")
  done < <( find $g_snapshotpath -mindepth 1 -maxdepth 1 -type d | cut -d '/' -f5 )

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
          snapshotname="${selection%%:*}"
          break
          ;;
      esac
    else
      printx "Invalid selection. Please enter a number between 1 and $count."
    fi
  done
}

function get_bootfile {
  local restpath=$1

  local outsecureboot="ts_secureboot.out"
  local setupmode
  local securebootval
  local securebootvar="/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"
  local setupmodevar="/sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c"

  # Check Secure Boot status
  echo "Checking SecureBoot EFI variable" > "/tmp/$outsecureboot"
  if [ -f "$securebootvar" ]; then
    securebootval=$(sudo hexdump -v -e '/1 "%02x"' "$securebootvar" | tail -c 2)
    echo "SecureBoot last byte: $securebootval" >> "/tmp/$outsecureboot"
    if [ -f "$setupmodevar" ]; then
      setupmode=$(sudo hexdump -v -e '/1 "%02x"' "$setupmodevar" | tail -c 2)
      echo "SetupMode last byte: $setupmode" >> "/tmp/$outsecureboot"
    else
      echo "SetupMode variable not found" >> "/tmp/$outsecureboot"
    fi
    if [ "$securebootval" = "01" ]; then
      # Secure Boot enabled; use shimx64.efi if present
      if [ -f "$restpath/boot/efi/EFI/debian/shimx64.efi" ]; then
        g_bootfile="shimx64.efi"
        echo "SecureBoot enabled (EFI variable: $securebootval); using $g_bootfile." >> "/tmp/$outsecureboot"
      else
        echo "SecureBoot enabled but shimx64.efi not found; using $g_bootfile." >> "/tmp/$outsecureboot"
      fi
    else
      echo "SecureBoot disabled (EFI variable: $securebootval); using $g_bootfile." >> "/tmp/$outsecureboot"
    fi
  else
    echo "SecureBoot variable not found; defaulting to $g_bootfile" >> "/tmp/$outsecureboot"
    if [ -f "$setupmodevar" ]; then
      setupmode=$(sudo hexdump -v -e '/1 "%02x"' "$setupmodevar" | tail -c 2)
      echo "SetupMode last byte: $setupmode" >> "/tmp/$outsecureboot"
    fi
  fi

  g_output_file_list+="$outsecureboot "
}

function validate_boot_config {
  local restdev=$1 restpath=$2

  local outbootvalidate="ts_boot_validation.out"
  local boot_valid=1

  # Boot build was not requested so validate restored boot components
  # To see if it should be done anyway...
  echo "Validating restored boot components..." >&2
  if [ ! -f "$restpath/boot/grub/grub.cfg" ]; then
    echo "Warning: $restpath/boot/grub/grub.cfg not found" > "/tmp/$outbootvalidate"
    boot_valid=0
  fi
  if [ ! -d "$restpath/boot/grub" ]; then
    echo "Warning: $restpath/boot/grub directory not found" >> "/tmp/$outbootvalidate"
    boot_valid=0
  fi
  if [ -z "$(ls $restpath/boot/vmlinuz* 2>/dev/null)" ]; then
    echo "Warning: No kernel images found in $restpath/boot/vmlinuz*" >> "/tmp/$outbootvalidate"
    boot_valid=0
  fi
  if [ ! -f "$restpath/boot/efi/EFI/debian/$g_bootfile" ]; then
    echo "Warning: Bootloader file $restpath/boot/efi/EFI/debian/$g_bootfile not found" >> "/tmp/$outbootvalidate"
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
  fi

  g_output_file_list+="$outbootvalidate "
}

function build_boot {
  local restdev=$1 restpath=$2

  local outgrubinstall="ts_grub-install.out"
  local outgrubupdate="ts_update-grub.out"
  local outefiboot="ts_efibootmgr.out"
  local osid=$(grep "^ID=" "$restpath/etc/os-release" | cut -d'=' -f2 | tr -d '"')
  local partno=$(lsblk -no PARTN "$restdev" 2>/dev/null || echo "2")

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

  echo "Updating grub on $restdev..." >&2
  # Use chroot to rebuild grub on the restored partion
  sudo chroot "$restpath" update-grub &> "/tmp/$outgrubupdate"
  if [ $? -ne 0 ]; then
    printx "Something went wrong with 'update-grub'.  The details are in /tmp/$outgrubupdate."
  fi
  g_output_file_list+="$outgrubupdate "

  echo "Installing grub on $restdev..." >&2
  sudo chroot "$restpath" grub-install --target=x86_64-efi --efi-directory=/boot/efi --boot-directory=/boot &> "/tmp/$outgrubinstall"
  if [ $? -ne 0 ]; then
    printx "Something went wrong with 'grub-install'.  The details are in /tmp/$outgrubinstall." >&2
  fi
  g_output_file_list+="$outgrubinstall "

  # Check for an existing boot entry
  if ! sudo efibootmgr | grep -q "$osid"; then
    echo "Building the UEFI boot entry on $bootdevice with an entry for $restdev..." >&2

    # Set UEFI boot entry -- where partno is the target partition for the boot entry
    sudo efibootmgr -c -d $bootdevice -p $partno -L $osid -l "/EFI/$osid/$g_bootfile" &> "/tmp/$outefiboot"
    if [ $? -ne 0 ]; then
      printx "Something went wrong with 'efibootmgr'. The details are in /tmp/$outefiboot." >&2
    fi
  fi
  # Copy bootloader to default EFI path as a fall back
  sudo cp "$restpath/boot/efi/EFI/$osid/$g_bootfile" "$restpath/boot/efi/EFI/BOOT/BOOTX64.EFI"
  if [ $? -ne 0 ]; then
    echo "Warning: Failed to copy $g_bootfile to EFI/BOOT/BOOTX64.EFI" >> "/tmp/$outefiboot"
  else
    echo "Successfully copied $g_bootfile to EFI/BOOT/BOOTX64.EFI" >> "/tmp/$outefiboot"
  fi

  # Unbind the directories
  sudo umount "$restpath/boot/efi" "$restpath/dev/pts" "$restpath/dev" "$restpath/proc" "$restpath/sys"

  g_output_file_list+="$outefiboot "
}

function restore_snapshot {
  local restpath=$1

  local outrsync="ts_rsync.out"

  # Restore the snapshot
  echo rsync -aAX --delete --verbose "--exclude-from=$g_excludespathname" "$g_snapshotpath/$snapshotname/" "$restpath/" > "/tmp/$outrsync"
  sudo rsync -aAX --delete --verbose "--exclude-from=$g_excludespathname" "$g_snapshotpath/$snapshotname/" "$restpath/" >> "/tmp/$outrsync"
  if [ $? -ne 0 ]; then
    printx "Something went wrong with the restore.  The details are in /tmp/$outrsync."
    exit 3
  fi
  g_output_file_list+="$outrsync "

  if [ -f "$g_snapshotpath/$g_descfile" ]; then
    # Delete the description file from the target
    sudo rm "$g_snapshotpath/$g_descfile"
  fi
}

function restore_dryrun {
  local restpath=$1

  local outrsync="ts_rsync.out"

  # Do a dry run and record the output
  echo rsync -aAX --dry-run --delete --verbose "--exclude-from=$g_excludespathname" "$g_snapshotpath/$snapshotname/" "$restpath/" > "/tmp/$outrsync"
  sudo rsync -aAX --dry-run --delete --verbose "--exclude-from=$g_excludespathname" "$g_snapshotpath/$snapshotname/" "$restpath/" >> "/tmp/$outrsync"
  echo "The dry run restore has completed.  The results are found in '$outrsync'."
}

# --------------------
# ------- MAIN -------
# --------------------

g_descfile=comment.txt
g_output_file_list=()
backuppath="/mnt/backup"
backupdir="ts"
restorepath="/mnt/restore"

g_snapshotpath="$backuppath/ts"
g_excludespathname="/etc/ts_excludes"
g_bootfile="grubx64.efi"  # Default for non-secure boot

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

mount_device_at_path "$restoredevice" "$restorepath"
mount_device_at_path "$backupdevice" "$backuppath" "$backupdir"

if [ -z $snapshotname ]; then
  select_snapshot
fi

if [ ! -z $snapshotname ]; then
  if [ ! -z $dryrun ]; then
    restore_dryrun "$restorepath"
  else
    printx "This will completely OVERWRITE the operating system on '$restoredevice'."
    readx "Are you sure you want to proceed? (y/N) " yn
    if [[ $yn != "y" && $yn != "Y" ]]; then
      echo "Operation cancelled."
      exit
    else
      restore_snapshot "$restorepath"
      echo "The snapshot '$snapshotname' was successfully restored."
    fi

    echo "Before get_bootfile..."
    echo "restoredevice=$restoredevice"
    echo "g_bootfile=$g_bootfile"
    echo "bootdevice=$bootdevice"
    get_bootfile "$restorepath"

    if [ -z $bootdevice ]; then
      echo "Before validate_boot_config..."
      echo "restoredevice=$restoredevice"
      echo "g_bootfile=$g_bootfile"
      echo "bootdevice=$bootdevice"
      validate_boot_config "$restoredevice" "$restorepath"
    fi

    if [ ! -z $bootdevice ]; then
      echo "Before get_build_boot..."
      echo "restoredevice=$restoredevice"
      echo "g_bootfile=$g_bootfile"
      echo "bootdevice=$bootdevice"
      build_boot "$restoredevice" "$restorepath"
    fi

    echo "After all boot stuff..."
    echo "restoredevice=$restoredevice"
    echo "g_bootfile=$g_bootfile"
    echo "bootdevice=$bootdevice"

    # Done
    echo "✅ Restore complete: $g_snapshotpath/$snapshotname"
    echo "The system may now be rebooted into the restored partition."
    echo "Details of the operation can be viewed in these files found in /tmp: $g_output_file_list"
  fi
else
  echo "Operation cancelled."
fi
