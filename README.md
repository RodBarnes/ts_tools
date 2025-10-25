# ts_tools
A collection of `bash` scripts to emulate TimeShift backups on headless systems.  Each is intended to be instantiated within the `$PATH`, set as executable, and without the `.sh` extension.  The recommended location is `/usr/local/bin`.  

(NOTE: Yes, TimeShift has a command line but TimeShift includes all the GUI libraries it needs even if they are needed on a headless system.  Plus, this was a fun project.) 

## ts_backup.sh
Usage: `sudo ts_backup <device> [-d] [description]`

Creates a full or incrental snapshot (emulating TimeShift with the exception that managing information about the snapshots is handled differently).  This is designed for use on headless systems so there isn't the need to install TimeShift (with all its GUI libraries) in order to simply use the command line.

## ts_delete.sh
Usage: `sudo ts_delete <device>`

Lists the snapshots (created by `ts_backup`) found on the designated device and allows selecting one for deletion.

## ts_excludes
Place this file in `/etc`.  It is used by `ts_backup` and `ts_restore` to ignore specific directories and files.  As provided, it matches what TimeShift excludes as of v25.07.7.

## ts_list.sh
Usage: `sudo ts_list <device>`

Lists the snapshots (created by `ts_backup`) found on the designated device.

## ts_restore.sh
Usage: `sudo ts_restore <snapshot_device> <restore_device> [-d] [snapshot_name]`

Restores a snapshot (created by `ts_backup`).  As written, `ts_restore` is designed to be used from a server's recovery partition and has only been tested there.  It should also work from a live image but that has not been tested.

