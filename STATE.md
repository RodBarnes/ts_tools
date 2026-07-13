# STATE

## Current state
Working tree is dirty (uncommitted) with a server-filter feature added to `ts-list` and
`ts-delete`. Not yet tested by the user, not yet committed.

## Last worked on (2026-07-13)
Added an optional `<server>` argument to `ts-list` and `ts-delete` so the snapshot listing
can be filtered to a single hostname instead of showing all servers on the backup device.

Changes:
- `ts-shared.sh`: `collect_snapshots(path, [hostname_filter])` — when a filter is given,
  only scans `$path/$hostname_filter` instead of every hostname dir. `select_snapshot(device,
  path, [hostname_filter])` gained the same optional 3rd arg and passes it through. Both
  are backward compatible (filter defaults to empty = all hosts), so `ts-restore.sh`'s
  existing 2-arg call to `select_snapshot` is unaffected. VERSION bumped to `20260713`.
- `ts-list.sh`: optional 2nd positional arg `<server>`, passed to `collect_snapshots`.
  Syntax message and "no backups" message updated. VERSION bumped to `20260713`.
- `ts-delete.sh`: optional 2nd positional arg `<server>`, passed to `select_snapshot` in
  the delete loop. Syntax message updated. VERSION bumped to `20260713`.

`bash -n` syntax-checked clean on all three files. Not yet deployed or run on boss/shrek.

## What's next
- User to test on a real system (deploy via `ts-deploy.sh`, then run `ts-list <device>
  <server>` and `ts-delete <device> <server>` against actual snapshot data on boss/shrek).
- Commit once verified.

## Known blockers / open questions
None currently. No regression risk expected for `ts-restore.sh` since its call to
`select_snapshot` doesn't pass a 3rd argument.
