# usb_clean_eject

A macOS shell script that removes Apple junk files from a USB drive and safely ejects it.

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
- Safely ejects the drive after cleaning
- Adds a `usb_eject` alias to `~/.zshrc` on first run

## Requirements

- macOS
- `bash` 3.2+ (pre-installed on macOS)
- `sudo` access (needed for protected system folders)

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

```
🔍  Scanning for mounted USB drives...

  Found USB drive(s):

  [1] /Volumes/SANDISK               14.9 GB
  [2] /Volumes/PortableSSD            1.0 TB

  Enter number of the drive to clean & eject (or q to quit): 1

  ✔  Selected: /Volumes/SANDISK

  ⚠️   Delete Apple dot files and eject this drive? [y/N] y
```

## License

MIT
