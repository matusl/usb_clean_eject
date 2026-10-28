#!/bin/bash
# ============================================================
# usb_clean_eject.sh
# Lists mounted USB drives, lets the user pick one,
# deletes Apple dot files, then ejects the drive.
# Usage: ./usb_clean_eject.sh
# ============================================================

set -euo pipefail

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

# ── Confirm ─────────────────────────────────────────────────
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

# ── Clean dot files (if requested) ──────────────────────────
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

# ── Eject ───────────────────────────────────────────────────
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
