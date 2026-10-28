# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Single-file macOS bash script (`usb_clean_eject.sh`) that detects mounted external USB drives, optionally removes Apple metadata files, optionally scans the drive with ESET Endpoint Security, and safely ejects it. On every successful run it ensures a `usb_eject` alias exists in `~/.zshrc`.

## Branches

- `main` — clean & eject only.
- `feature/eset-scan` — everything on `main` plus the optional ESET scan. Shared fixes (eject logic, detection, prompts) are committed to both branches separately (the histories have diverged, same messages with different hashes), so a fix made here usually needs to be ported to `main` too, and vice versa. The `main` branch also carries its own `CLAUDE.md`.

## Running / testing

```bash
./usb_clean_eject.sh        # or: bash usb_clean_eject.sh
bash -n usb_clean_eject.sh  # syntax check
```

Requires macOS, bash 3.2+ (the system `/bin/bash` — avoid bash 4+ features such as associative arrays or `mapfile`). No `sudo` is required — the script deliberately avoids it so it never prompts for a password.

There are no automated tests. Test interactively with a real USB drive, or a mock volume via `hdiutil create` / `hdiutil attach`. Note that running the script appends the alias to `~/.zshrc` if missing.

## Script flow

1. **Discovery** — iterates `/dev/disk*s*` block devices, keeps those whose `diskutil info` reports removable or external media, collects mount points.
2. **Pick** — auto-selects when exactly one drive is found; otherwise a numbered picker (`q` quits).
3. **ESET prompt** — only offered if `odscan` exists at `$ESET_CLI` (inside `ESET Endpoint Security.app`).
4. **Clean prompt** — "delete dot files?"; if no, a second prompt "just eject?"; if no again, abort.
5. **Clean** (optional) — `find … -delete` for user-owned `.DS_Store` / `._*` only. Root-owned `.Spotlight-V100`, `.Trashes`, `.fseventsd` are intentionally left in place (removing them needs `sudo`).
6. **ESET scan** (optional) — runs `odscan --scan --profile="@Smart scan"` in the background logging to `/tmp/eset_usb_scan_*.log`, parses `session_id` from that log, then polls `odscan --list` each second for `ProgressCount` / `ProgressCountTotal` / `DetectedCount` of that session. Exit code 0 = clean (log deleted); 1 = threats handled; anything else = error. Non-zero codes keep the log and ask before ejecting. While the scan runs, `_stop_scan` is trapped on EXIT/INT/TERM: it calls `odscan --stop=<session>` and kills the background process (background jobs ignore SIGINT, so Ctrl-C alone would leave the scan running and holding the volume).
7. **Wait for ESET release** — only if a scan ran: sleep 5s, then poll `lsof <mountpoint>` for `odfeeder` for up to 30s.
8. **Eject** — `DISK` (whole-disk node from `Part of Whole`) is resolved up front. `_try_eject` is non-forcing: `diskutil eject <mountpoint>` → `diskutil unmountDisk` + `diskutil eject` on `DISK`. If that fails and `backupd` holds the volume, runs `tmutil stopbackup` and retries once. If still busy, lists holders (`_holders`) and asks before `_force_eject` (`unmountDisk force` + eject → `hdiutil detach -force`); declining exits 1.
9. **Alias** — appends `alias usb_eject='bash <abs-path>'` to `~/.zshrc` if not present.

## Conventions to preserve

- `set -euo pipefail` is intentional. Any command that may legitimately fail (grep with no match, `diskutil`, `wait` on a non-zero child) must be guarded with `|| true`, `|| echo default`, or the `VAR=0; cmd || VAR=$?` pattern used for `SCAN_EXIT`. Use `(( ++WAIT ))`, not `(( WAIT++ ))` (the latter returns 1 when WAIT is 0 and kills the script).
- Don't reintroduce `sudo` (including `mdutil`); the user chose to skip root-owned folders rather than be prompted for a password.
- Never force-unmount without the confirmation prompt — forcing can lose unsaved data and unmounts every partition on the disk.
- Use `lsof <mountpoint>`, not `lsof +D` (recursive, takes seconds on large drives). `lsof` exits 1 when nothing is open, so guard it under `pipefail`.
- The two-prompt clean/eject-only design is deliberate — don't collapse it into one prompt.
- `diskutil info` output is parsed with `awk -F': +'`; keep that field separator when editing those lines.
- The odfeeder wait must remain conditional on `DO_SCAN` (it was intentionally removed from the no-scan path).
- User-facing output uses the existing emoji-prefixed style (`✔`, `⚠️`, `✅`, `❌`); keep new messages consistent with it.
- Keep `README.md`'s usage examples in sync with the actual prompt order and messages when changing the flow.
