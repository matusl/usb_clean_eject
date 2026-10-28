#!/bin/bash
# ============================================================
# usb_clean_eject.sh
# Lists mounted USB drives, lets the user pick one,
# deletes Apple dot files, optionally scans with ESET,
# then ejects the drive.
# Usage: ./usb_clean_eject.sh
# ============================================================

set -euo pipefail

# ── ESET CLI tool path ───────────────────────────────────────
ESET_CLI="/Applications/ESET Endpoint Security.app/Contents/MacOS/odscan"

# ── Discover mounted USB volumes ────────────────────────────
echo ""
echo "🔍  Scanning for mounted USB drives..."
echo ""

USB_VOLUMES=()
while IFS= read -r vol; do
  [[ -n "$vol" ]] && USB_VOLUMES+=("$vol")
done < <(
  for dev in /dev/disk[0-9]s[0-9]* /dev/disk[0-9][0-9]s[0-9]*; do
    [[ -b "$dev" ]] || continue
    info=$(diskutil info "$dev" 2>/dev/null) || continue
    echo "$info" | grep -qE 'Removable Media:.*Removable|Device Location:.*External' || continue
    mp=$(echo "$info" | awk -F': +' '/Mount Point/ { print $2 }')
    [[ -n "$mp" && "$mp" != "/" ]] && echo "$mp"
  done | sort -u
)

# ── Guard: no USB found ─────────────────────────────────────
if [[ ${#USB_VOLUMES[@]} -eq 0 ]]; then
  echo "❌  No mounted USB drives found."
  echo "    Plug in a USB stick and try again."
  exit 1
fi

# ── Print list / pick ────────────────────────────────────────
if [[ ${#USB_VOLUMES[@]} -eq 1 ]]; then
  USB_PATH="${USB_VOLUMES[0]}"
  SIZE=$(diskutil info "$USB_PATH" 2>/dev/null | awk -F': +' '/Disk Size/ { print $2 }' | grep -oE '[0-9.]+ [KMGT]B' | head -1 || echo "?")
  printf "  Auto-selected:  %-35s %s\n" "$USB_PATH" "$SIZE"
else
  echo "  Found USB drive(s):"
  echo ""
  for i in "${!USB_VOLUMES[@]}"; do
    VOL="${USB_VOLUMES[$i]}"
    SIZE=$(diskutil info "$VOL" 2>/dev/null | awk -F': +' '/Disk Size/ { print $2 }' | grep -oE '[0-9.]+ [KMGT]B' | head -1 || echo "?")
    printf "  [%d] %-35s %s\n" "$((i+1))" "$VOL" "$SIZE"
  done
  echo ""
  while true; do
    read -rp "  Enter number of the drive to clean & eject (or q to quit): " CHOICE
    [[ "$CHOICE" == "q" || "$CHOICE" == "Q" ]] && echo "  Aborted." && exit 0
    if [[ "$CHOICE" =~ ^[0-9]+$ ]] && \
       [[ "$CHOICE" -ge 1 ]] && \
       [[ "$CHOICE" -le "${#USB_VOLUMES[@]}" ]]; then
      USB_PATH="${USB_VOLUMES[$((CHOICE-1))]}"
      break
    fi
    echo "  ⚠️   Invalid choice. Please enter a number between 1 and ${#USB_VOLUMES[@]}."
  done
fi

echo ""
echo "  ✔  Selected: $USB_PATH"
echo ""

# ── Ask about ESET scan ──────────────────────────────────────
DO_SCAN=false
if [[ -f "$ESET_CLI" ]]; then
  read -rp "  🛡️   Run ESET virus scan before ejecting? [y/N] " SCAN_CHOICE
  [[ "$SCAN_CHOICE" =~ ^[Yy]$ ]] && DO_SCAN=true
  echo ""
else
  echo "  ℹ️   ESET Endpoint Security not found — skipping scan option."
  echo ""
fi

# ── Confirm cleanup + eject ─────────────────────────────────
read -rp "  🗑️   Delete Apple dot files before ejecting? [y/N] " CONFIRM
DO_CLEAN=false
if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
  DO_CLEAN=true
else
  read -rp "  ⏏️   Skip cleaning and just eject? [y/N] " EJECT_ONLY
  if [[ ! "$EJECT_ONLY" =~ ^[Yy]$ ]]; then
    echo "  Aborted."
    exit 0
  fi
fi
echo ""

# ── Clean dot files (if requested) ─────────────────────────
if [[ "$DO_CLEAN" == true ]]; then

  # ── Delete Apple dot files ────────────────────────────────
  # Only user-owned files; root-owned system folders (.Spotlight-V100,
  # .Trashes, .fseventsd) are left alone so no sudo is needed.
  echo "🗑️   Removing Apple dot files from $USB_PATH ..."
  echo ""

  find "$USB_PATH" -name ".DS_Store" -type f -print -delete 2>/dev/null || true
  find "$USB_PATH" -name "._*"       -type f -print -delete 2>/dev/null || true

  echo ""
  echo "✅  Apple dot files removed."
  echo ""

fi # DO_CLEAN

# ── ESET scan ────────────────────────────────────────────────
if [[ "$DO_SCAN" == true ]]; then
  echo "🛡️   Starting ESET scan of $USB_PATH ..."
  echo ""

  SCAN_LOG="/tmp/eset_usb_scan_$(date +%Y%m%d_%H%M%S).log"

  # Launch scan in background so we can poll progress while it runs
  "$ESET_CLI" --scan --profile="@Smart scan" --profile-priority=idle --show-scan-info "$USB_PATH" > "$SCAN_LOG" 2>&1 &
  SCAN_PID=$!
  SESSION_ID=""

  # On Ctrl-C, stop the scan too. Background jobs ignore SIGINT, so without
  # this odscan keeps scanning and holding the volume after the script exits.
  _stop_scan() {
    kill -0 "$SCAN_PID" 2>/dev/null || return 0
    [[ -n "$SESSION_ID" ]] && "$ESET_CLI" --stop="$SESSION_ID" > /dev/null 2>&1 || true
    kill "$SCAN_PID" 2>/dev/null || true
  }
  trap _stop_scan EXIT
  trap 'printf "\n\n⚠️   Scan cancelled — stopping ESET. Drive NOT ejected.\n"; exit 130' INT TERM

  # Wait up to 3s for session_id to appear in the log
  for i in 1 2 3 4 5 6; do
    sleep 0.5
    SESSION_ID=$(grep -o '"session_id":[^,}]*' "$SCAN_LOG" 2>/dev/null | grep -o '[0-9]*' || true)
    [[ -n "$SESSION_ID" ]] && break
  done

  if [[ -z "$SESSION_ID" ]]; then
    echo "  ⚠️   Could not parse session ID — waiting for scan to finish silently..."
    SCAN_EXIT=0; wait $SCAN_PID || SCAN_EXIT=$?
  else
    echo "  Session: $SESSION_ID"
    echo ""

    # Poll every second while background process is running
    while kill -0 $SCAN_PID 2>/dev/null; do
      LIST=$("$ESET_CLI" --list 2>/dev/null) || true

      COUNT=$(echo "$LIST" | grep -A20 "\"SessionId\":$SESSION_ID" | \
        grep '"ProgressCount"' | grep -o '[0-9]*' | head -1 || echo "0")
      TOTAL=$(echo "$LIST" | grep -A20 "\"SessionId\":$SESSION_ID" | \
        grep '"ProgressCountTotal"' | grep -o '[0-9]*' | head -1 || echo "0")
      DETECTED=$(echo "$LIST" | grep -A20 "\"SessionId\":$SESSION_ID" | \
        grep '"DetectedCount"' | grep -o '[0-9]*' | head -1 || echo "0")

      if [[ "$TOTAL" -gt 0 ]]; then
        PCT=$(( COUNT * 100 / TOTAL ))
        printf "\r  ⏳  %3d%%  files: %d / %d  threats: %s  " \
          "$PCT" "$COUNT" "$TOTAL" "$DETECTED"
      else
        printf "\r  ⏳  files scanned: %d  threats: %s  " "$COUNT" "$DETECTED"
      fi

      sleep 1
    done

    printf "\r%-80s\n" ""  # clear progress line
    SCAN_EXIT=0; wait $SCAN_PID || SCAN_EXIT=$?
  fi
  trap - EXIT INT TERM

  case ${SCAN_EXIT:-0} in
    0)
      echo "✅  ESET scan complete — no threats found."
      rm -f "$SCAN_LOG"
      ;;
    1)
      echo "⚠️   ESET found and handled threat(s) on the drive."
      echo "    Full report: $SCAN_LOG"
      echo ""
      read -rp "  Continue with eject anyway? [y/N] " EJECT_ANYWAY
      [[ ! "$EJECT_ANYWAY" =~ ^[Yy]$ ]] && echo "  Aborted. Drive NOT ejected." && exit 1
      ;;
    *)
      echo "⚠️   ESET scan finished with exit code $SCAN_EXIT."
      echo "    Full report: $SCAN_LOG"
      echo ""
      read -rp "  Continue with eject anyway? [y/N] " EJECT_ANYWAY
      [[ ! "$EJECT_ANYWAY" =~ ^[Yy]$ ]] && echo "  Aborted. Drive NOT ejected." && exit 1
      ;;
  esac
  echo ""
fi

# ── Eject ───────────────────────────────────────────────────
# Wait until odfeeder (ESET file feeder) fully releases the volume.
# Only needed if a scan was actually performed.
if [[ "$DO_SCAN" == true ]]; then
  echo "⏳  Waiting for ESET to release the volume..."
  sleep 5  # give odfeeder a moment to finish before we start polling
  WAIT=0
  while lsof "$USB_PATH" 2>/dev/null | grep -q "odfeeder"; do
    if [[ $WAIT -ge 30 ]]; then
      echo "  ⚠️   odfeeder still running after 30s — attempting eject anyway."
      break
    fi
    sleep 1
    (( ++WAIT ))
  done
  [[ $WAIT -gt 0 ]] && echo "  ✔  Released after ${WAIT}s."
fi

echo "⏏️   Ejecting $USB_PATH ..."

# Resolve the BSD whole-disk node (e.g. /dev/disk2) now, while still mounted.
DISK=$(diskutil info "$USB_PATH" 2>/dev/null \
  | awk -F': +' '/Part of Whole/ { print "/dev/" $2 }' \
  | head -1 || true)

# Processes with files open on the volume. lsof given a mount point lists
# everything open on that file system (much faster than a recursive +D).
_holders() {
  lsof "$USB_PATH" 2>/dev/null | awk 'NR>1 {print $1 " (pid " $2 ")"}' | sort -u || true
}

# Safe eject: never forces, so open files are not cut off.
_try_eject() {
  # 1. diskutil eject on the mount point
  if diskutil eject "$USB_PATH" 2>/dev/null; then
    echo "✅  USB stick ejected safely. You can unplug it now."
    return 0
  fi

  # 2. Unmount all partitions, then eject the whole disk
  if [[ -n "$DISK" ]]; then
    echo "⚠️   diskutil eject failed. Trying unmount + eject on $DISK..."
    if diskutil unmountDisk "$DISK" 2>/dev/null && diskutil eject "$DISK" 2>/dev/null; then
      echo "✅  USB stick ejected safely. You can unplug it now."
      return 0
    fi
  fi

  return 1
}

# Forced eject: only after the user confirms.
_force_eject() {
  if [[ -n "$DISK" ]]; then
    diskutil unmountDisk force "$DISK" 2>/dev/null || true
    if diskutil eject "$DISK" 2>/dev/null; then
      echo "✅  USB stick force-ejected. You can unplug it now."
      return 0
    fi
  fi

  echo "⚠️   Trying hdiutil detach..."
  if hdiutil detach "${DISK:-$USB_PATH}" -force 2>/dev/null; then
    echo "✅  Ejected via hdiutil."
    return 0
  fi

  return 1
}

EJECTED=false
_try_eject && EJECTED=true

if [[ "$EJECTED" == false ]] && _holders | grep -q backupd; then
  echo "⚠️   Time Machine is holding the disk. Stopping backup..."
  tmutil stopbackup 2>/dev/null || true
  sleep 3
  _try_eject && EJECTED=true
fi

if [[ "$EJECTED" == false ]]; then
  echo ""
  echo "⚠️   The volume is still in use."
  HOLDERS=$(_holders)
  if [[ -n "$HOLDERS" ]]; then
    echo "  Processes holding the volume open:"
    echo "$HOLDERS" | sed 's/^/    /'
  fi
  echo ""
  echo "  Force-ejecting may lose unsaved changes in those apps"
  echo "  and unmounts every partition on ${DISK:-the disk}."
  read -rp "  Force eject anyway? [y/N] " FORCE
  echo ""
  if [[ ! "$FORCE" =~ ^[Yy]$ ]]; then
    echo "  Aborted. Drive NOT ejected."
    echo "    Close those processes and eject manually from Finder."
    exit 1
  fi
  _force_eject || {
    echo ""
    echo "❌  Could not eject, even with force."
    exit 1
  }
fi

# ── Add alias to ~/.zshrc ────────────────────────────────────
SCRIPT_ABS="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
ALIAS_LINE="alias usb_eject='bash $SCRIPT_ABS'"
ZSHRC="$HOME/.zshrc"

if grep -qF "$ALIAS_LINE" "$ZSHRC" 2>/dev/null; then
  echo ""
  echo "ℹ️   Alias already present in $ZSHRC — nothing to do."
else
  echo "" >> "$ZSHRC"
  echo "# USB clean & eject helper" >> "$ZSHRC"
  echo "$ALIAS_LINE" >> "$ZSHRC"
  echo ""
  echo "✅  Alias added to $ZSHRC"
  echo "    Run 'source ~/.zshrc' or open a new terminal, then use:  usb_eject"
fi
