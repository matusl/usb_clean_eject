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

  # ── Stop Spotlight indexing on this volume ─────────────────
  echo "⏸️   Suspending Spotlight on $USB_PATH ..."
  sudo mdutil -i off "$USB_PATH" > /dev/null 2>&1 && \
    echo "  ✔  Spotlight disabled." || \
    echo "  ⚠️   Could not disable Spotlight (continuing)."
  echo ""

  # ── Delete Apple dot files ────────────────────────────────
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

# ── Eject ───────────────────────────────────────────────────
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
