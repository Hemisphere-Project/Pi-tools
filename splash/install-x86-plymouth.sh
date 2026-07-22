#!/bin/bash
# splash, x86 flavor — silent production boot with a bare plymouth spinner.
#
# The Pi flavor of this module paints a PNG on the framebuffer (fbi); x86
# players (biennale N100 minis) have no fbdev, so the boot cosmetics come
# from grub + kernel cmdline + plymouth instead. Target (Thomas,
# 2026-07-22): fully silent boot, plymouth's round spinner ONLY — no BGRT
# (vendor) logo, no distro watermark, no console text — while keeping
# debug reachable: Esc/Shift during grub's hidden 2s window opens the
# menu, a failed boot shows it 5s (recordfail), the console lives on tty1
# (emergency prompts are visible on HDMI, not a phantom serial port), and
# Ctrl+Alt+F2 spawns a login getty in a normal boot.
#
# Idempotent: safe to re-run. Bench-validated on mini-06 (2026-07-22),
# including the two traps found there:
#  - Ubuntu's initramfs plymouth hook hard-requires the theme's
#    watermark.png → we divert the packaged one away and install a 1x1
#    transparent PNG at its path (survives package upgrades).
#  - the 2024 images carry default.plymouth as a stale REGULAR FILE
#    (bgrt copy) instead of the alternatives symlink → rewire it.

set -e

export DEBIAN_FRONTEND=noninteractive
apt-get install -y plymouth plymouth-theme-spinner >/dev/null

THEME_DIR=/usr/share/plymouth/themes
WM="$THEME_DIR/spinner/watermark.png"

# neutralize the distro watermark: divert the packaged file, put a
# transparent pixel at its path (the initramfs hook insists it exists)
if ! dpkg-divert --list | grep -q "$WM"; then
    dpkg-divert --add --rename --divert "$WM.disabled" "$WM"
fi
python3 - "$WM" <<'PYGEN'
import struct, sys, zlib
def chunk(t, d):
    c = struct.pack(">I", len(d)) + t + d
    return c + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
ihdr = struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0)
raw = zlib.compress(b"\x00\x00\x00\x00\x00")
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", raw) + chunk(b"IEND", b"")
open(sys.argv[1], "wb").write(png)
PYGEN

# theme = spinner via BOTH mechanisms (alternatives + plymouthd.conf);
# replace the stale regular default.plymouth if the old image left one
update-alternatives --install "$THEME_DIR/default.plymouth" default.plymouth \
    "$THEME_DIR/spinner/spinner.plymouth" 150 2>/dev/null || true
update-alternatives --set default.plymouth "$THEME_DIR/spinner/spinner.plymouth"
if [ -e "$THEME_DIR/default.plymouth" ] && [ ! -L "$THEME_DIR/default.plymouth" ]; then
    rm "$THEME_DIR/default.plymouth"
    ln -s /etc/alternatives/default.plymouth "$THEME_DIR/default.plymouth"
fi
mkdir -p /etc/plymouth
printf '[Daemon]\nTheme=spinner\n' > /etc/plymouth/plymouthd.conf

# grub: hidden-but-reachable menu, visible recordfail, console on tty1
G=/etc/default/grub
sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' "$G"
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=2/' "$G"
grep -q '^GRUB_RECORDFAIL_TIMEOUT=' "$G" \
    && sed -i 's/^GRUB_RECORDFAIL_TIMEOUT=.*/GRUB_RECORDFAIL_TIMEOUT=5/' "$G" \
    || echo 'GRUB_RECORDFAIL_TIMEOUT=5' >> "$G"
sed -i '/^GRUB_CMDLINE_LINUX=/ s/console=ttyS[0-9]*\(,[0-9]*\)\?/console=tty1/' "$G"
grep -q '^GRUB_CMDLINE_LINUX=.*console=' "$G" \
    || sed -i 's/^GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="\1 console=tty1"/' "$G"
# silence systemd status lines (the 2024 images shipped =auto)
sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/rd.systemd.show_status=auto/rd.systemd.show_status=false/' "$G"
grep -q 'systemd.show_status=false' "$G" \
    || sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 systemd.show_status=false"/' "$G"

update-grub
update-initramfs -u

echo "splash (x86/plymouth): silent boot + bare spinner installed"
