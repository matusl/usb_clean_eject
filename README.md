# usb_clean_eject

A macOS shell script that removes Apple junk files from a USB drive and safely ejects it.

## Features

- Auto-detects all mounted external USB drives
- Auto-selects the drive if only one is plugged in; numbered picker otherwise
- Optionally removes Apple dot files (no password needed):
  - `.DS_Store` — Finder folder metadata
  - `._*` — AppleDouble resource forks
  - Root-owned system folders (`.Spotlight-V100`, `.Trashes`, `.fseventsd`) are left in place
- Handles Time Machine volumes — stops the backup automatically if it's blocking eject
- Safely ejects the drive; if something still has files open, shows which apps and asks before force-ejecting
- Adds a `usb_eject` alias to `~/.zshrc` on first run

## Requirements

- macOS
- `bash` 3.2+ (pre-installed on macOS)

## Installation

```bash
# 1. Clone the repo
git clone https://github.com/matusl/usb_clean_eject.git
cd usb_clean_eject

# 2. Make the script executable
chmod +x usb_clean_eject.sh

# 3. Run it once — this also adds the usb_eject alias to ~/.zshrc
./usb_clean_eject.sh

# 4. Reload your shell
source ~/.zshrc
```

After that, just run:

```bash
usb_eject
```

## Usage

**Single drive plugged in — auto-selected:**

```
🔍  Scanning for mounted USB drives...

  Auto-selected:  /Volumes/SANDISK                14.9 GB

  ✔  Selected: /Volumes/SANDISK

  🗑️   Delete Apple dot files before ejecting? [y/N] y

🗑️   Removing Apple dot files from /Volumes/SANDISK ...
✅  Apple dot files removed.

⏏️   Ejecting /Volumes/SANDISK ...
✅  USB stick ejected safely. You can unplug it now.
```

**Multiple drives — numbered picker:**

```
🔍  Scanning for mounted USB drives...

  Found USB drive(s):

  [1] /Volumes/SANDISK               14.9 GB
  [2] /Volumes/PortableSSD            1.0 TB

  Enter number of the drive to clean & eject (or q to quit): 1

  ✔  Selected: /Volumes/SANDISK

  🗑️   Delete Apple dot files before ejecting? [y/N] n
  ⏏️   Skip cleaning and just eject? [y/N] y

⏏️   Ejecting /Volumes/SANDISK ...
✅  USB stick ejected safely. You can unplug it now.
```

## License

MIT
