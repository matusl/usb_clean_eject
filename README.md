# usb_clean_eject

A macOS shell script that removes Apple junk files from a USB drive, optionally scans it with ESET Endpoint Security, and safely ejects it.

## Branches

| Branch | Description |
|---|---|
| `main` | Clean & eject only |
| `feature/eset-scan` | Adds optional ESET virus scan before ejecting |

## Features

- Auto-detects all mounted external USB drives
- Interactive numbered picker — no need to type volume paths
- Removes all Apple dot files:
  - `.DS_Store` — Finder folder metadata
  - `._*` — AppleDouble resource forks
  - `.Spotlight-V100` — Spotlight index
  - `.Trashes` — macOS Trash folder
  - `.fseventsd` — File system events log
- Disables Spotlight indexing before deletion to release daemon locks
- **Optional ESET Endpoint Security scan** (if installed):
  - Uses `@Smart scan` profile to match ESET app behavior
  - Runs in background with live progress display
  - Waits for ESET to fully release the volume before ejecting
  - Prompts to confirm eject if threats are found
- Safely ejects the drive after cleaning
- Adds a `usb_eject` alias to `~/.zshrc` on first run

## Requirements

- macOS
- `bash` 3.2+ (pre-installed on macOS)
- `sudo` access (needed for protected system folders)
- ESET Endpoint Security (optional, for virus scanning)

## Installation

```bash
# 1. Clone the repo
git clone https://github.com/matusl/usb_clean_eject.git
cd usb_clean_eject

# 2. For ESET scan support, switch to the feature branch
git checkout feature/eset-scan

# 3. Make the script executable
chmod +x usb_clean_eject.sh

# 4. Run it once — this also adds the usb_eject alias to ~/.zshrc
./usb_clean_eject.sh

# 5. Reload your shell
source ~/.zshrc
```

After that, just run:

```bash
usb_eject
```

## Usage

```
🔍  Scanning for mounted USB drives...

  Found USB drive(s):

  [1] /Volumes/MLI 128GB             123.0 GB
  [2] /Volumes/PortableSSD             1.0 TB

  Enter number of the drive to clean & eject (or q to quit): 1

  ✔  Selected: /Volumes/MLI 128GB

  🛡️   Run ESET virus scan before ejecting? [y/N] y
  ⚠️   Delete Apple dot files and eject this drive? [y/N] y

⏸️   Suspending Spotlight on /Volumes/MLI 128GB ...
  ✔  Spotlight disabled.

🗑️   Removing Apple dot files from /Volumes/MLI 128GB ...

✅  Apple dot files removed.

🛡️   Starting ESET scan of /Volumes/MLI 128GB ...
  Session: 10

  ⏳   73%  files: 31430 / 42917  threats: 0

✅  ESET scan complete — no threats found.

⏳  Waiting for ESET to release the volume...
  ✔  Released after 3s.

⏏️   Ejecting /Volumes/MLI 128GB ...
✅  USB stick ejected safely. You can unplug it now.
```

## License

MIT
