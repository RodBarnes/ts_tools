# ts_tools
A collection of `bash` scripts that emulate TimeShift backups on headless systems.  It requires `rsync` be installed.

These are written for bash on debian-based distros.  They may work as is or should be easily modified to work on other distros.

NOTE: Yes, TimeShift provides a command line but TimeShift includes all the GUI dependicies even if they aren't required on a headless system.  Plus, this was a fun project.

## ts_backup.sh
Usage: `sudo ts_backup <backup_device> [-d|--dry-run] [-c|--comment "comment"]`

Creates a full or incrental snapshot on the `backup_device` of the current active partition from which it is run.

## ts_delete.sh
Usage: `sudo ts_delete <backup_device>`

Lists the `ts_backup` snapshots found on the designated device and allows selecting one for deletion.

## ts_excludes
Place this file in `/etc`.  It is used by `ts_backup` and `ts_restore` to ignore specific directories and files.  As provided, it matches what TimeShift excludes as of v25.07.7.

## ts_list.sh
Usage: `sudo ts_list <backup_device>`

Lists the `ts_backup` snapshots found on the designated device.

## ts_restore.sh
Usage: `sudo ts_restore <backup_device> <restore_device> [-d|--dry-run] [-g|--grub-install boot_device] [-s|--snapshot snapshot_name]`

Restores a `ts_backup` snapshot from the `backup_device` to the `restore_device`.

NOTE: As written, `ts_restore` is intended to be used from a server's recovery partition to elmininate discrepancies by running on an active partition.  But it has been tested under both situations and works.  It should also work from a live image but that has not been tested.

## ts_shared.sh
Shared functions and variables used by `ts_tools`.
