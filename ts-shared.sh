#!/usr/bin/env bash

# Shared code and variables for ts-tools

source /usr/local/lib/display.sh
source /usr/local/lib/device.sh

VERSION="20260713"

g_infofile=info.json
g_backuppath=/mnt/backup
g_backupdir="ts"
g_excludesfile="/etc/ts-excludes"
g_bootfile="grubx64.efi"  # Default for non-secure boot
g_snapshots=()            # Populated by collect_snapshots as needed

verify_sudo() {
  if [[ "$EUID" != 0 ]]; then
    showx "This must be run as sudo.\n"
    exit 1
  fi
}

get_device() {
  echo "/dev/$(lsblk -ln -o NAME,UUID,PARTUUID,LABEL | grep "${1#/dev/}" | tr -s ' ' | cut -d ' ' -f1)"
}

# Populate g_snapshots with all snapshots found under path.
# Each entry is "hostname/snapshotname|comment"
# Entries are sorted by hostname then snapshotname.
# If hostname_filter is given, only that hostname's snapshots are collected.
collect_snapshots() {
  local path=$1
  local hostname_filter=$2

  local comment
  local snapshot
  local infopath
  local hostnamedir
  local hostnamedirs=()
  local raw=()
  local entry

  g_snapshots=()

  if [ -n "$hostname_filter" ]; then
    if [ -d "$path/$hostname_filter" ]; then
      hostnamedirs=("$path/$hostname_filter")
    fi
  else
    while IFS= read -r hostnamedir; do
      hostnamedirs+=("$hostnamedir")
    done < <( find "$path" -mindepth 1 -maxdepth 1 -type d | sort )
  fi

  for hostnamedir in "${hostnamedirs[@]}"; do
    while IFS= read -r snapshot; do
      infopath="$hostnamedir/$snapshot/$g_infofile"
      if [ -f "$infopath" ]; then
        comment=$(jq -r '.comment' "$infopath")
      else
        comment="<no desc>"
      fi
      raw+=("${hostnamedir##*/}/$snapshot|$comment")
    done < <( find "$hostnamedir" -mindepth 1 -maxdepth 1 -type d | xargs -I{} basename {} | grep -E '^[0-9]{8}_[0-9]{6}$' | sort )
  done

  # Sort by hostname then snapshotname (both are in the key portion before |)
  while IFS= read -r entry; do
    g_snapshots+=("$entry")
  done < <( printf '%s\n' "${raw[@]}" | sort -t'|' -k1 )
}

# Print a single formatted snapshot line to stderr.
# With prefix="": ts-list style   — name  timestamp  description
# With prefix="N) ": ts-restore/delete style — N)  name  timestamp  description
# Column widths: name=8, timestamp=15, description fills to COLUMNS.
format_snapshot_line() {
  local key=$1      # hostname/snapshotname
  local comment=$2
  local prefix=$3   # e.g. " 1)  " or "" for ts-list

  local sysname
  local snapshot
  local desc_width
  local truncated

  sysname="${key%/*}"
  snapshot="${key##*/}"

  if [ -n "$prefix" ]; then
    # 4 (num field) + 8 (name) + 2 (gap) + 15 (timestamp) + 2 (gap) = 31
    desc_width=$(( COLUMNS - 31 ))
  else
    # 8 (name) + 2 (gap) + 15 (timestamp) + 2 (gap) = 27
    desc_width=$(( COLUMNS - 27 ))
  fi

  # Guard against very narrow terminals
  if [ "$desc_width" -lt 10 ]; then
    desc_width=10
  fi

  # Truncate comment if needed
  if [ "${#comment}" -gt "$desc_width" ]; then
    truncated="${comment:0:$(( desc_width - 3 ))}..."
  else
    truncated="$comment"
  fi

  printf "%s${WHITE}%-8s${NOCOLOR}  ${LTCYAN}%s${NOCOLOR}  ${YELLOW}%s${NOCOLOR}\n" \
    "$prefix" "$sysname" "$snapshot" "$truncated" >&2
}

select_snapshot() {
  local device=$1
  local path=$2
  local hostname_filter=$3

  local count
  local entry
  local key
  local comment
  local idx
  local reply
  local name

  collect_snapshots "$path" "$hostname_filter"

  if [ ${#g_snapshots[@]} -eq 0 ]; then
    if [ -n "$hostname_filter" ]; then
      showx "There are no backups on $device for server '$hostname_filter'"
    else
      showx "There are no backups on $device"
    fi
    return
  fi

  count="${#g_snapshots[@]}"
  local cancel=$(( count + 1 ))

  show ""

  idx=0
  for entry in "${g_snapshots[@]}"; do
    key="${entry%%|*}"
    comment="${entry##*|}"
    idx=$(( idx + 1 ))
    format_snapshot_line "$key" "$comment" "$(printf '%2d)  ' $idx)"
  done

  printf "%2d)  Cancel\n" "$cancel" >&2
  show ""

  while true; do
    printf "${YELLOW}Select [1-$cancel]:${NOCOLOR} " >&2
    read -r reply
    if [[ "$reply" =~ ^[0-9]+$ && "$reply" -ge 1 && "$reply" -le "$cancel" ]]; then
      if [ "$reply" -eq "$cancel" ]; then
        show "Operation cancelled."
        name=""
        break
      else
        name="${g_snapshots[$(( reply - 1 ))]%%|*}"
        break
      fi
    else
      showx "Invalid selection. Please enter a number between 1 and $cancel."
    fi
  done

  echo "$name"
}

show_device_space() {
  local device=$1
  df -h --output=source,size,used,avail,pcent "$device" | tail -1 | \
    awk '{printf "Device %s: %s total, %s used, %s available (%s)\n", $1, $2, $3, $4, $5}'
}
