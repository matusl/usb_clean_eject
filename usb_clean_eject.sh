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

# ── Print numbered list ─────────────────────────────────────
echo "  Found USB drive(s):"
echo ""
for i in "${!USB_VOLUMES[@]}"; do
  VOL="${USB_VOLUMES[$i]}"
  SIZE=$(diskutil info "$VOL" 2>/dev/null | awk -F': +' '/Disk Size/ { print $2 }' | grep -oE '[0-9.]+ [KMGT]B' | head -1 || echo "?")
  printf "  [%d] %-35s %s\n" "$((i+1))" "$VOL" "$SIZE"
done
echo ""

# ── User picks ──────────────────────────────────────────────
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

# ── Stop Spotlight indexing on this volume ───────────────────
echo "⏸️   Suspending Spotlight on $USB_PATH ..."
sudo mdutil -i off "$USB_PATH" > /dev/null 2>&1 && \
  echo "  ✔  Spotlight disabled." || \
  echo "  ⚠️   Could not disable Spotlight (continuing)."
echo ""

# ── Delete Apple dot files ──────────────────────────────────
echo "🗑️   Removing Apple dot files from $USB_PATH ..."
echo ""

find "$USB_PATH" -name ".DS_Store" -type f -print -delete 2>/dev/null || true
find "$USB_PATH" -name "._*"       -type f -print -delete 2>/dev/null || true

NEEDS_SUDO=()
[[ -d "$USB_PATH/.Spotlight-V100" ]] && NEEDS_SUDO+=("$USB_PATH/.Spotlight-V100")
[[ -d "$USB_PATH/.Trashes"        ]] && NEEDS_SUDO+=("$USB_PATH/.Trashes")
[[ -d "$USB_PATH/.fseventsd"      ]] && NEEDS_SUDO+=("$USB_PATH/.fseventsd")

if [[ ${#NEEDS_SUDO[@]} -gt 0 ]]; then
  for d in "${NEEDS_SUDO[@]}"; do
    if sudo rm -rf "$d" 2>/dev/null; then
      echo "  ✔  Removed: $d"
    else
      echo "  ⚠️   Skipped (still locked): $d"
    fi
  done
  echo ""
fi

echo "✅  Apple dot files removed."
echo ""

fi # DO_CLEAN

# ── ESET scan ────────────────────────────────────────────────
if [[ "$DO_SCAN" == true ]]; then
  echo "🛡️   Starting ESET scan of $USB_PATH ..."
  echo ""

  SCAN_LOG="/tmp/eset_usb_scan_$(date +%Y%m%d_%H%M%S).log"

  # Launch scan in background so we can poll progress while it runs
  "$ESET_CLI" --scan --profile="@Smart scan" --profile-priority=idle       --show-scan-info "$USB_PATH" > "$SCAN_LOG" 2>&1 &
  SCAN_PID=$!

  # Wait up to 3s for session_id to appear in the log
  SESSION_ID=""
  for i in 1 2 3 4 5 6; do
    sleep 0.5
    SESSION_ID=$(grep -o '"session_id":[^,}]*' "$SCAN_LOG" 2>/dev/null | grep -o '[0-9]*' || true)
    [[ -n "$SESSION_ID" ]] && break
  done

  if [[ -z "$SESSION_ID" ]]; then
    echo "  ⚠️   Could not parse session ID — waiting for scan to finish silently..."
    wait $SCAN_PID || true
    SCAN_EXIT=$?
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
    wait $SCAN_PID; SCAN_EXIT=$?
  fi

  case ${SCAN_EXIT:-0} in
    0)
      echo "✅  ESET scan complete — no threats found."
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
# Timeout after 30 seconds to avoid hanging forever.
echo "⏳  Waiting for ESET to release the volume..."
sleep 2  # give odfeeder a moment to finish before we start polling
WAIT=0
while lsof +D "$USB_PATH" 2>/dev/null | grep -q "odfeeder"; do
  if [[ $WAIT -ge 30 ]]; then
    echo "  ⚠️   odfeeder still running after 30s — attempting eject anyway."
    break
  fi
  sleep 1
  (( WAIT++ ))
done
[[ $WAIT -gt 0 ]] && echo "  ✔  Released after ${WAIT}s."

echo "⏏️   Ejecting $USB_PATH ..."

if diskutil eject "$USB_PATH" 2>/dev/null; then
  echo "✅  USB stick ejected safely. You can unplug it now."
else
  echo "⚠️   diskutil eject failed. Trying hdiutil detach..."
  if hdiutil detach "$USB_PATH" 2>/dev/null; then
    echo "✅  Ejected via hdiutil."
  else
    echo ""
    echo "❌  Could not eject automatically."
    echo "    Try: lsof +D \"$USB_PATH\" to find what's keeping it open,"
    echo "    then close that process and eject manually from Finder."
    exit 1
  fi
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
