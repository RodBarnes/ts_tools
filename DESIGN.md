# DESIGN

## Server-scoped snapshot filtering (2026-07-13)

`ts-list` and `ts-delete` accept an optional 2nd positional argument, `<server>`, after
the backup device. When given, it must match a hostname directory name exactly under
`<backup_root>/ts/<hostname>/` and restricts the listing/selection to that server's
snapshots only. Omitting it preserves the original behavior (all servers shown).

Rationale: on a shared backup device holding snapshots for multiple hosts (e.g. boss and
shrek both backing up to the same external drive), listing/deleting was previously
all-or-nothing across every host on the device.

### Function signature convention

`collect_snapshots(path, [hostname_filter])` and `select_snapshot(device, path,
[hostname_filter])` in `ts-shared.sh` both take the hostname filter as a trailing optional
argument, defaulting to empty (no filtering). This preserves backward compatibility for
callers that don't pass it — `ts-restore.sh` calls `select_snapshot` with only 2 args and
is unaffected.

If a server name doesn't match any hostname directory, the result is an empty snapshot
list — same code path as "no backups found," no separate error case.
