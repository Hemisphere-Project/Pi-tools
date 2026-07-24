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

# grub: hidden-but-reachable menu, console on tty1
G=/etc/default/grub
sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' "$G"
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=2/' "$G"
grep -q '^GRUB_RECORDFAIL_TIMEOUT=' "$G" \
    && sed -i 's/^GRUB_RECORDFAIL_TIMEOUT=.*/GRUB_RECORDFAIL_TIMEOUT=2/' "$G" \
    || echo 'GRUB_RECORDFAIL_TIMEOUT=2' >> "$G"

# recordfail trap on ro rootfs: grub sets recordfail=1 at every boot and
# the userspace clear (grub-common) can never write on ro — so Ubuntu's
# "failed boot" logic showed the MENU (plus grub's Loading… lines) at
# EVERY boot. Variables set after 00_header win at menu time: re-hide.
# Rescue path unchanged — Esc during the 2s hidden window.
cat > /etc/grub.d/06_pitools_silent <<'EOF'
#!/bin/sh
cat <<'GRUBCFG'
# pitools: ro rootfs never clears recordfail — keep the menu hidden anyway
set timeout_style=hidden
set timeout=2
GRUBCFG
EOF
chmod +x /etc/grub.d/06_pitools_silent
# console on tty3, the Pi-fleet convention: boot residue and runtime
# console text land on an invisible VT instead of behind the video —
# any mpv gap then flashes BLACK, not systemd lines (mini-01,
# 2026-07-22). Debug stays reachable: Ctrl+Alt+F3 is kernel-level VT
# switching and works even in emergency mode (sulogin binds tty3).
sed -i '/^GRUB_CMDLINE_LINUX=/ s/console=ttyS[0-9]*\(,[0-9]*\)\?/console=tty3/; /^GRUB_CMDLINE_LINUX=/ s/console=tty1/console=tty3/' "$G"
grep -q '^GRUB_CMDLINE_LINUX=.*console=' "$G" \
    || sed -i 's/^GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="\1 console=tty3"/' "$G"
# silence systemd status lines (the 2024 images shipped =auto)
sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/rd.systemd.show_status=auto/rd.systemd.show_status=false/' "$G"
grep -q 'systemd.show_status=false' "$G" \
    || sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 systemd.show_status=false"/' "$G"

update-grub
update-initramfs -u

# park the display on blank VT1 after plymouth quits — plymouth exits to
# the kernel-console VT (tty3), which is exactly where the boot residue
# lands, so every mpv gap showed systemd lines instead of black
ln -sf "$(dirname "$(readlink -f "$0")")/pitools-vt1.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable -q pitools-vt1.service

echo "splash (x86/plymouth): silent boot + bare spinner + VT1 parking installed"
