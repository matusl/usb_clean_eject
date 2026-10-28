# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Single-file macOS shell script (`usb_clean_eject.sh`) that detects mounted external USB drives, optionally removes Apple metadata files, and safely ejects the drive. After first run it also adds a `usb_eject` alias to `~/.zshrc`.

## Running the script

```bash
chmod +x usb_clean_eject.sh
./usb_clean_eject.sh
```

Requires macOS and bash 3.2+. No `sudo` is required — the script deliberately avoids it so it never prompts for a password.

There are no automated tests. To test, plug in a real USB drive and run the script interactively, or create a mock volume with `hdiutil create` / `hdiutil attach`.

> **Note:** The usage example in `README.md` shows the old single-prompt flow and is outdated — it does not reflect the current two-prompt design (clean? → if no, eject-only?).

## Script flow

1. **Discovery** — iterates `/dev/disk*s*` block devices, uses `diskutil info` to filter for removable/external media, collects mount points.
2. **Picker** — prints a numbered list with sizes; user selects one or quits.
3. **Confirm** — asks whether to clean dot files; if no, offers eject-only.
4. **Clean** (optional) — `find … -delete` for user-owned `.DS_Store` / `._*` only. Root-owned `.Spotlight-V100`, `.Trashes`, `.fseventsd` are intentionally left in place (removing them needs `sudo`).
5. **Eject** — tries `diskutil eject`, falls back to `hdiutil detach`.
6. **Alias** — appends `alias usb_eject='bash <abs-path>'` to `~/.zshrc` if not already present.

## Key behaviors to preserve

- `set -euo pipefail` is intentional; errors in sub-commands that should be non-fatal use `|| true` or `2>/dev/null`.
- Don't reintroduce `sudo` (including `mdutil`); the user chose to skip root-owned folders rather than be prompted for a password.
- The eject-without-cleaning path (step 3 "no → eject only") was added deliberately — don't collapse the two prompts into one.
- USB detection relies on `diskutil info` output parsing (not `diskutil list`); keep the `awk` field separator `': +'` when editing those lines.
