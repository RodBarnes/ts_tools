#!/usr/bin/env bash

# Restore a backup using rsync command as done by TimeShift.
# One of the followin is required parameter: <device>, <label>, or <uuid> for mounting the device
# Optional parameter: -t -- Include to do a dry-run

# Error codes:
# 1 -- not running as sudo
# 2 -- device issues
# 3 -- operation failure

# NOTE: This script expects to find the listed mountpoints.  If not present, they will be created.

# Grok conversation URL: https://grok.com/c/61141f41-643d-4a52-93c1-a0e58cd443d7

source /usr/local/lib/colors

scriptname=$(basename $0)
backuppath=/mnt/backup
restorepath=/mnt/restore
snapshotpath=$backuppath/snapshots
excludespathname=/etc/ts_excludes
descfile=backup.desc
outrsync=ts_rsync.out
outgrubinstall=ts_grub-install.out
outgrubupdate=ts_update-grub.out
outsecureboot=ts_secureboot.out
outefiboot=ts_efibootmgr.out
outbootvalidate=ts_boot_validation.out
regex="^\S{8}-\S{4}-\S{4}-\S{4}-\S{12}$"

function printx {
  printf "${YELLOW}$1${NOCOLOR}\n"
}

function readx {
  printf "${YELLOW}$1${NOCOLOR}"
  read -p "" $2
}

function show_syntax () {
  echo "Restore a snapshot created with ts_backup; emulates TimeShift."
  echo "Syntax: $scriptname <backup_device> <restore_device> [-d] [-g <boot_device>] [-s snapshot]"
  echo "Where:  <backup_device> and <restore_device> can be a device designator (e.g., /dev/sdb6), a UUID, or a filesystem LABEL."
  echo "        [-d] means to do a 'dry-run' test without actually creating the backup."
  echo "        [-g] means to rebuild grub on the specified device; e.g., /dev/sda1."
  echo "        [snapshot] is the name (timestamp) of the snapshot to restore -- if not present, a selection is presented."
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
    printx "Unable to mount the backup device."
    exit 2
  fi
}

function unmount_backup_device () {
  sudo umount $backuppath
}

function mount_restore_device () {
  if [ ! -d $restorepath ]; then
    printx "'$restorepath' was not found; creating it..."
    sudo mkdir $restorepath
  fi

  sudo mount $restoredevice $restorepath
  if [ $? -ne 0 ]; then
    printx "Unable to mount the restore device."
    exit 2
  fi
}

function unmount_restore_device () {
  sudo umount $restorepath
}

function select_snapshot () {
  # Get the snapshots and allow selecting
  echo "Listing backup files..."

  # Get the snapshots
  unset snapshots
  while IFS= read -r LINE; do
    snapshots+=("${LINE}")
  done < <( find $snapshotpath -mindepth 1 -maxdepth 1 -type d | cut -d '/' -f5 )

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
          snapshotname=$selection
          break
          ;;
      esac
    else
      printx "Invalid selection. Please enter a number between 1 and $count."
    fi
  done
}

function get_bootfile () {
  # Check Secure Boot status
  bootfile="grubx64.efi"  # Default for non-secure boot
  securebootvar="/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"
  setupmodevar="/sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c"
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
      if [ -f "$restorepath/boot/efi/EFI/debian/shimx64.efi" ]; then
        bootfile="shimx64.efi"
        echo "SecureBoot enabled (EFI variable: $securebootval); using $bootfile." >> "/tmp/$outsecureboot"
      else
        echo "SecureBoot enabled but shimx64.efi not found; using $bootfile." >> "/tmp/$outsecureboot"
      fi
    else
      echo "SecureBoot disabled (EFI variable: $securebootval); using $bootfile." >> "/tmp/$outsecureboot"
    fi
  else
    echo "SecureBoot variable not found; defaulting to $bootfile" >> "/tmp/$outsecureboot"
    if [ -f "$setupmodevar" ]; then
      setupmode=$(sudo hexdump -v -e '/1 "%02x"' "$setupmodevar" | tail -c 2)
      echo "SetupMode last byte: $setupmode" >> "/tmp/$outsecureboot"
    fi
  fi
  output_file_list+="$outsecureboot "
}

function validate_boot_config () {
  # Boot build was not requested so validate restored boot components
  # To see if it should be done anyway...
  echo "Validating restored boot components..."
  boot_valid=1
  if [ ! -f "$restorepath/boot/grub/grub.cfg" ]; then
    echo "Warning: $restorepath/boot/grub/grub.cfg not found" > "/tmp/$outbootvalidate"
    boot_valid=0
  fi
  if [ ! -d "$restorepath/boot/grub" ]; then
    echo "Warning: $restorepath/boot/grub directory not found" >> "/tmp/$outbootvalidate"
    boot_valid=0
  fi
  if [ -z "$(ls $restorepath/boot/vmlinuz* 2>/dev/null)" ]; then
    echo "Warning: No kernel images found in $restorepath/boot/vmlinuz*" >> "/tmp/$outbootvalidate"
    boot_valid=0
  fi
  if [ ! -f "$restorepath/boot/efi/EFI/debian/$bootfile" ]; then
    echo "Warning: Bootloader file $restorepath/boot/efi/EFI/debian/$bootfile not found" >> "/tmp/$outbootvalidate"
    boot_valid=0
  fi
  if [ $boot_valid -eq 0 ]; then
    # There is an issue with the boot configuration
    printx "The boot configuration on '$restoredevice' seems incorrect.  To ensure it is bootable"
    printx "it is recommended to update/install grub and verify/establish a EFI boot entry.  Proceed?"
    while true; do
      readx "Enter the boot device (or press ENTER to skip):" bootdevice
      if [ -z "$bootdevice" ]; then
        printx "Skipping GRUB setup. Ensure the EFI boot entry is configured manually."
        break
      elif sudo lsblk $bootdevice &> /dev/null; then
        break
      else
        printx "That is not a recognized device."
      fi
    done
  fi
}

function build_boot () {
  # Mount the necessary directories
  sudo mount $bootdevice "$restorepath/boot/efi"
  if [ $? -ne 0 ]; then
    printx "Unable to mount the EFI System Partition on $bootdevice."
    unmount_backup_device
    unmount_restore_device
    exit 2
  fi
  sudo mount --bind /dev "$restorepath/dev"
  sudo mount --bind /proc "$restorepath/proc"
  sudo mount --bind /sys "$restorepath/sys"
  sudo mount --bind /dev/pts "$restorepath/dev/pts"

  echo "Updating grub on $restoredevice..."
  # Use chroot to rebuild grub on the restored partion
  sudo chroot "$restorepath" update-grub &> "/tmp/$outgrubupdate"
  if [ $? -ne 0 ]; then
    printx "Something went wrong with 'update-grub'.  The details are in /tmp/$outgrubupdate."
  fi
  output_file_list+="$outgrubupdate "

  echo "Installing grub on $restoredevice..."
  sudo chroot "$restorepath" grub-install --target=x86_64-efi --efi-directory=/boot/efi --boot-directory=/boot &> "/tmp/$outgrubinstall"
  if [ $? -ne 0 ]; then
    printx "Something went wrong with 'grub-install'.  The details are in /tmp/$outgrubinstall."
  fi
  output_file_list+="$outgrubinstall "

  # Check for an existing boot entry
  osid=$(grep "^ID=" "$restorepath/etc/os-release" | cut -d'=' -f2 | tr -d '"')
  if ! sudo efibootmgr | grep -q "$osid"; then
    echo "Building the UEFI boot entry on $bootdevice with an entry for $restoredevice..."

    # Set UEFI boot entry -- where partno is the target partition for the boot entry
    partno=$(lsblk -no PARTN "$restoredevice" 2>/dev/null || echo "2")
    sudo efibootmgr -c -d $bootdevice -p $partno -L $osid -l "/EFI/$osid/$bootfile" &> "/tmp/$outefiboot"
    if [ $? -ne 0 ]; then
      printx "Something went wrong with 'efibootmgr'. The details are in /tmp/$outefiboot."
    fi
  fi
  # Copy bootloader to default EFI path as a fall back
  sudo cp "$restorepath/boot/efi/EFI/$osid/$bootfile" "$restorepath/boot/efi/EFI/BOOT/BOOTX64.EFI"
  if [ $? -ne 0 ]; then
    echo "Warning: Failed to copy $bootfile to EFI/BOOT/BOOTX64.EFI" >> "/tmp/$outefiboot"
  else
    echo "Successfully copied $bootfile to EFI/BOOT/BOOTX64.EFI" >> "/tmp/$outefiboot"
  fi
  output_file_list+="$outefiboot "

  # Unbind the directories
  sudo umount "$restorepath/boot/efi" "$restorepath/dev/pts" "$restorepath/dev" "$restorepath/proc" "$restorepath/sys"
}

function restore_snapshot () {
  # Restore the snapshot
  echo rsync -aAX --delete --verbose "--exclude-from=$excludespathname" "$snapshotpath/$snapshotname/" "$restorepath/" > "/tmp/$outrsync"
  sudo rsync -aAX --delete --verbose "--exclude-from=$excludespathname" "$snapshotpath/$snapshotname/" "$restorepath/" >> "/tmp/$outrsync"
  if [ $? -ne 0 ]; then
    printx "Something went wrong with the restore.  The details are in /tmp/$outrsync."
    exit 3
  fi
  output_file_list+="$outrsync "

  if [ -f "$snapshotpath/$descfile" ]; then
    # Delete the description file from the target
    sudo rm "$snapshotpath/$descfile"
  fi
}

function restore_dryrun () {
  # Do a dry run and record the output
  echo rsync -aAX --dry-run --delete --verbose "--exclude-from=$excludespathname" "$snapshotpath/$snapshotname/" "$restorepath/" > "/tmp/$outrsync"
  sudo rsync -aAX --dry-run --delete --verbose "--exclude-from=$excludespathname" "$snapshotpath/$snapshotname/" "$restorepath/" >> "/tmp/$outrsync"
  echo "The dry run restore has completed.  The results are found in '$outrsync'."
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

  # Get the restore_device
  i=1
  if [[ "${args[$i]}" =~ "/dev/" ]]; then
    restoredevice="${args[$i]}"
  elif [[ "${args[$i]}" =~ $regex ]]; then
    restoredevice="UUID=${args[$i]}"
  else
    # Assume it is a label
    restoredevice="LABEL=${args[$i]}"
  fi

  # Get optional parameters
  i=2
  while [ $i -le $argcnt ]; do
    if [ "${args[$i]}" == "-d" ]; then
      dryrun=--dry-run
    elif [ "${args[$i]}" == "-g" ]; then
      ((i++))
      bootdevice="${args[$i]}"
    elif [ "${args[$i]}" == "-s" ]; then
      ((i++))
      snapshotname="${args[$i]}"
    fi
    ((i++))
  done

  # echo "Backup device:$backupdevice"
  # echo "Restore device:$restoredevice"
  # echo "Dry-run:$dryrun"
  # echo "Boot device:$bootdevice"
  # echo "Snapshot:$snapshotname"
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

if [ ! -e $restoredevice ]; then
  printx "There is no such device: $restoredevice."
  exit 2
fi

# --------------------
# ------- MAIN -------
# --------------------

mount_restore_device
mount_backup_device

if [ -z $snapshotname ]; then
  select_snapshot
fi

if [ ! -z $snapshotname ]; then
  if [ ! -z $dryrun ]; then
    restore_dryrun
  else
    printx "This will completely OVERWRITE the operating system on '$restoredevice'."
    readx "Are you sure you want to proceed? (y/N) " yn
    if [[ $yn != "y" && $yn != "Y" ]]; then
      echo "Operation cancelled."
      unmount_backup_device
      unmount_restore_device
      exit
    else
      restore_snapshot
      echo "The snapshot '$snapshotname' was successfully restored."
    fi

    get_bootfile

    if [ -z $bootdevice ]; then
      validate_boot_config
    fi

    if [ ! -z $bootdevice ]; then
      build_boot
    fi

    # Done
    echo "The system may now be rebooted into the restored partition."
    echo "Details of the operation can be viewed in these files found in /tmp: $output_file_list"
  fi
else
  echo "No snapshot was identified."
fi

unmount_backup_device
unmount_restore_device
