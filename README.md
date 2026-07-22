# Pi-tools

Modular toolkit for deploying Raspberry Pi and x86 mini-PC art installations.
Handles system bootstrap, read-only filesystem, networking, audio, display,
web management, and file sync — from fresh OS image to running system.

**Supported platforms:** Raspberry Pi OS (64-bit, Bookworm+) · Ubuntu Server (x86_64)

---

## Quick Start

### 1. Prepare the OS image

**Raspberry Pi:**
- Download [Raspberry Pi OS Lite (64-bit)](https://www.raspberrypi.com/software/operating-systems/)
- Flash with [Raspberry Pi Imager](https://www.raspberrypi.com/software/) — enable SSH, set user `pi`/`pi`
- **Important:** add a 3rd ext4 partition (for `/data`) using GParted or `fdisk`
- *(Optional)* Copy `pitools.example.txt` → `pitools.txt` onto the boot (FAT32) partition and edit it

**Ubuntu x86:**
- Download [Ubuntu Server](https://ubuntu.com/download/server) and install with OpenSSH enabled
- Create a 3rd ext4 partition for `/data`

### 2. Bootstrap & install

SSH into the machine, then run:

```bash
curl -fsSL https://raw.githubusercontent.com/Hemisphere-Project/Pi-tools/2026/setup.sh | sudo bash
```

Or manually:

```bash
sudo su root
apt update && apt install -y git
git clone -b 2026 https://github.com/Hemisphere-Project/Pi-tools.git /opt/Pi-tools
cd /opt/Pi-tools
./setup.sh
```

The installer will:
1. **Bootstrap** the system (packages, SSH, NetworkManager, Node.js, uv, etc.)
2. **Install core modules** (starter, extendfs, splash, datesync)
3. **Prompt for optional modules** (or read from `pitools.txt` config)

### 3. Re-run to add modules later

```bash
cd /opt/Pi-tools && ./setup.sh
```

Already-installed modules are detected and skipped. Only new/missing modules are offered.

---

## Configuration

Place `pitools.txt` on the **boot partition** for headless configuration:
- Raspberry Pi: `/boot/firmware/pitools.txt` (editable from macOS/Windows on the SD card)
- x86: `/boot/pitools.txt`
- USB override: place `pitools.txt` on a USB drive

See [pitools.example.txt](pitools.example.txt) for all options.

### Example

```ini
[system]
hostname = gallery-01
timezone = Europe/Paris

[network]
wifi_1 = GalleryWifi=secret123

[modules]
system = yes
network = yes
web = yes
audiohub = yes
xrun = no
```

---

## Modules

### Core (always installed)

| Module | Description |
|--------|-------------|
| **starter** | Reads `starter.txt` on boot and starts listed systemd services |
| **extendfs** | Auto-expands last partition when image is cloned to a new drive |
| **splash** | Boot splash screen (framebuffer) |
| **datesync** | One-shot HTTP date sync for systems without RTC |

### System (`system = yes`)

| Module | Description |
|--------|-------------|
| **rorw** | Read-only root filesystem with writable `/data` partition |
| **usbautomount** | Auto-mount USB drives to `/mnt/usbN`, symlink latest to `/data/usb` |

### Network (`network = yes`)

| Module | Description |
|--------|-------------|
| **network-tools** | Sync WiFi profiles from boot partition / USB to NetworkManager |
| **hostrename** | Change hostname + update hotspot SSIDs on the fly |

### Web (`web = ask`)

| Module | Description |
|--------|-------------|
| **webconf** | Browser-based system config UI (port 4038) |
| **filebrother** | Web file manager for `/data` (port 9000) |
| **3615-disco** | Real-time Zeroconf/mDNS service browser (port 80) |

### Standalone

| Module | Group key | Description |
|--------|-----------|-------------|
| **audiohub** | `audiohub` | HDMI/analog/USB audio routing (Pi only) |
| **xrun** | `xrun` | X11/Openbox display server with rotation support |
| **synczinc** | `synczinc` | Syncthing wrapper for `/data/sync` replication |
| **bluetooth** | `bluetooth` | Bluetooth UART controller attachment (Pi only) |
| **rtpmidi** | `rtpmidi` | RTP MIDI (CoreMIDI compatible) via raveloxmidi |

---

## Architecture

```
Boot partition (FAT32, read-only)
├── pitools.txt          ← installer config (editable from macOS/Windows)
├── starter.txt          ← runtime service list (enable/disable services)
├── wifi/                ← NetworkManager profiles
└── config.txt           ← Pi hardware config

Root filesystem (ext4, read-only when rorw enabled)
├── /opt/Pi-tools/       ← this repo
├── /usr/local/bin/      ← symlinks to module binaries
└── /etc/systemd/system/ ← symlinks to module services

Data partition (ext4, always writable)
├── /data/media/         ← media files
├── /data/sync/          ← syncthing folder
├── /data/usb            ← symlink to last mounted USB
└── /data/var/           ← persistent state
```

### Service flow

1. System boots → `starter.service` runs
2. Starter reads `starter.txt` → starts each uncommented service
3. Services run independently (webconf, setnet, audiohub, etc.)

---

## Development

The setup engine lives in `setup/` and reads `module.ini` from each module directory:

```
setup.sh              → bash entry point (ensures python3+git, runs installer)
setup/installer.py    → main orchestrator
setup/bootstrap.py    → system-level bootstrap (replaces old bootstrap scripts)
setup/detect.py       → platform detection (Pi vs x86)
setup/config.py       → pitools.txt parser
setup/utils.py        → shared utilities (symlink, apt, systemd helpers)
setup/ui.py           → terminal UI (colors, prompts)
```

Each module has a `module.ini` declaring its metadata, dependencies, and files:

```ini
[module]
name = mymodule
description = What it does
group = web
platforms = pi,x86

[deps]
apt = pkg1 pkg2

[files]
bins = mybinary
services = mymodule.service

[starter]
comment = Description for starter.txt
service = mymodule
```

## License

See [LICENSE](LICENSE).

