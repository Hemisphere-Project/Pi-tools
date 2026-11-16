#!/usr/bin/env bash
# burn-content-desk — desk test of burn-batch's CONTENT column on plain image
# files: no root, no card (pi-tools#t-061). `burn-batch --content` runs the very
# reads the plan runs on a card as root — sfdisk, `blkid -p` at each offset,
# the ext superblock through debugfs, the FAT counted — so this proves what a
# card shows in the plan, and that a card not of the image's layout is flagged.
# The space in use is checked against fsck.fat's own count on real files.
#
#   bash bench/burn-content-desk.sh        # exit 0 = every check green
#
# Not proven here: a real card in a reader (the plan's /dev path), and the
# mounted-card reading (lsblk FSUSED) — the latter is the -n fallback's source
# too, exercised below on this host's own disks when one is unreadable.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 2
TOOL=bench/burn-batch
for c in sfdisk blkid debugfs mkfs.vfat mkfs.ext4 fsck.fat python3; do
    command -v "$c" >/dev/null || { echo "no $c"; exit 2; }
done
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
plain() { sed 's/\x1b\[[0-9;]*m//g'; }          # the CONTENT cell, colour stripped
yellow() { grep -qF $'\033[1;33m'"$1"; }         # that cell was flagged

# fat_file <img> <partition byte offset> <clusters> — one real file of N
# clusters: a chain in every FAT and an entry in the root directory, so
# fsck.fat can count it independently (it counts what files reach).
fat_file() {
    python3 -I - "$@" <<'EOF'
import struct, sys
img, off, n = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
with open(img, 'r+b') as f:
    f.seek(off); bs = f.read(48)
    bps, spc, rsv, nfat, roots, tot16, _m, fsz16 = struct.unpack_from('<HBHBHHBH', bs, 11)
    fsz32, = struct.unpack_from('<I', bs, 36); rootclus, = struct.unpack_from('<I', bs, 44)
    fat32 = fsz16 == 0; fsz = fsz32 if fat32 else fsz16; w = 4 if fat32 else 2
    first = 3                                   # 2 is FAT32's root directory
    pack = (lambda v: struct.pack('<I', v)) if fat32 else (lambda v: struct.pack('<H', v))
    chain = b''.join(pack(c + 1) for c in range(first, first + n - 1)) + pack(0x0FFFFFFF if fat32 else 0xFFFF)
    for k in range(nfat):
        f.seek(off + (rsv + k * fsz) * bps + first * w); f.write(chain)
    rootsec = (roots * 32 + bps - 1) // bps
    if fat32:
        rootdir = off + (rsv + nfat * fsz + rootsec + (rootclus - 2) * spc) * bps
    else:
        rootdir = off + (rsv + nfat * fsz) * bps
    f.seek(rootdir)
    while f.read(1) not in (b'\x00', b''):      # first free entry: keep the volume label's
        f.seek(31, 1)
    f.seek(-1, 1)
    f.write(b'TRACK01 MP3' + b'\x20' + bytes(8) + struct.pack('<H', first >> 16) + bytes(4)
            + struct.pack('<HI', first & 0xFFFF, n * spc * bps))
EOF
}
# fsck_clusters <img> <partition byte offset> <bytes> -> "files used/total" per fsck.fat
fsck_clusters() {
    dd if="$1" of="$T/part" bs=1M iflag=skip_bytes,count_bytes skip="$2" count="$3" status=none
    fsck.fat -n "$T/part" 2>/dev/null | sed -n 's/.*: \([0-9]*\) files\?, \([0-9]*\)\/[0-9]* clusters$/\1 \2/p'
}
table() { sfdisk -q "$1" >/dev/null; }

# ── the golden: a RastaOS-shaped image, boot (FAT16) / rootfs / data ─────────
G=$T/golden.img; truncate -s 72M "$G"
printf 'label: dos\nstart=8192,size=32768,type=c\nstart=40960,size=65536,type=83\nstart=106496,size=32768,type=83\n' | table "$G"
mkfs.vfat -F 16 -s 1 -n boot --offset=8192 "$G" 16384 >/dev/null 2>&1
mkdir -p "$T/root"; head -c 3145728 /dev/urandom > "$T/root/blob"
mkfs.ext4 -q -F -L rootfs -d "$T/root" -E offset=$((40960*512)) "$G" 32M
mkfs.ext4 -q -F -L data -E offset=$((106496*512)) "$G" 16M
fat_file "$G" $((8192*512)) 5                    # 5 × 512 B = 2.5K in use

# ── the cards ────────────────────────────────────────────────────────────────
# somebody's music: one FAT32, no label, volume id 5B78-FD87, 114 MiB in use
M=$T/music.img; truncate -s 420M "$M"; printf 'label: dos\nstart=8192,type=c\n' | table "$M"
MS=$(sfdisk -d "$M" | sed -n 's/.*size= *\([0-9]*\).*/\1/p')
mkfs.vfat -F 32 -s 8 -i 5B78FD87 --offset=8192 "$M" $((MS/2)) >/dev/null
fat_file "$M" $((8192*512)) 29183                # + the root dir's cluster = 29184 × 4K = 114 MiB

# a fresh card from the shop: FAT32 with 512 B clusters, 6 clusters of file + the root dir
F=$T/fresh.img; truncate -s 48M "$F"; printf 'label: dos\nstart=8192,type=c\n' | table "$F"
FS=$(sfdisk -d "$F" | sed -n 's/.*size= *\([0-9]*\).*/\1/p')
mkfs.vfat -F 32 -s 1 -i 1234ABCD --offset=8192 "$F" $((FS/2)) >/dev/null
fat_file "$F" $((8192*512)) 6                    # 7 × 512 B = 3.5K

# a card of another RastaOS version, flightbox p4 already at its tail: other
# UUIDs, same layout — it must NOT be flagged
C=$T/card70.img; truncate -s 96M "$C"
printf 'label: dos\nstart=8192,size=32768,type=c\nstart=40960,size=65536,type=83\nstart=106496,size=32768,type=83\nstart=139264,size=8192,type=da\n' | table "$C"
mkfs.vfat -F 16 -s 1 -n boot --offset=8192 "$C" 16384 >/dev/null 2>&1
mkfs.ext4 -q -F -L rootfs -E offset=$((40960*512)) "$C" 32M
mkfs.ext4 -q -F -L data -E offset=$((106496*512)) "$C" 16M

B=$T/blank.img; truncate -s 8M "$B"                                   # zeros
P=$T/floppy.img; truncate -s 8M "$P"; mkfs.vfat -n CAMERA "$P" >/dev/null   # no table: whole-disk FAT12
L=$T/linux.img; truncate -s 40M "$L"; printf 'label: dos\nstart=8192,type=83\n' | table "$L"
mkfs.ext4 -q -F -U 0b5e55ed-0000-4000-8000-000000000061 -E offset=$((8192*512)) "$L" 32M   # no label

sums() { md5sum "$G" "$M" "$F" "$C" "$B" "$P" "$L"; }
before=$(sums)

# ── the checks ───────────────────────────────────────────────────────────────
out=$(bash "$TOOL" --content "$G" "$M" "$F" "$C" "$B" "$P" "$L" 2>&1); rc=$?
txt=$(plain <<<"$out")
line() { grep -F "$1:" <<<"$txt" | sed 's/.*:  //'; }
img=$(grep '^  image:' <<<"$txt" | sed 's/.*:  //')

check "--content runs (rc 0)" '[ $rc -eq 0 ]'
check "golden reads: vfat boot · ext4 rootfs · ext4 data" \
      '[[ "$img" =~ ^"vfat boot 2.5K · ext4 rootfs 3."[0-9]"M · ext4 data "[0-9.]+K$ ]]'
check "music card reads exactly as anna's did: vfat 5B78-FD87 114M" '[ "$(line "$M")" = "vfat 5B78-FD87 114M" ]'
check "fresh card: volume id and 3.5K" '[ "$(line "$F")" = "vfat 1234-ABCD 3.5K" ]'
check "other-version card with p4: its layout, raw p4 last" \
      '[[ "$(line "$C")" =~ ^"vfat boot 0 · ext4 rootfs "[0-9.]+K" · ext4 data "[0-9.]+K" · raw"$ ]]'
check "blank card: said so" '[ "$(line "$B")" = "no partition, no filesystem" ]'
check "whole-disk FAT (no table): label, FAT12 used skipped" '[ "$(line "$P")" = "vfat CAMERA" ]'
check "unlabelled ext4: volume id cut to 8" '[[ "$(line "$L")" =~ ^"ext4 0b5e55ed… "[0-9.]+K$ ]]'

check "music card flagged (not the image's layout)" 'yellow "vfat 5B78-FD87 114M" <<<"$out"'
check "fresh, blank, whole-disk, unlabelled flagged" \
      'yellow "vfat 1234-ABCD" <<<"$out" && yellow "no partition" <<<"$out" && yellow "vfat CAMERA" <<<"$out" && yellow "ext4 0b5e55ed" <<<"$out"'
check "other-version card with p4 NOT flagged" '! yellow "vfat boot 0" <<<"$out"'
check "the note counts 5 of 6" 'grep -q "5 of 6 hold another layout than this image" <<<"$txt"'

# the space in use, against fsck.fat (which counts what real files reach)
# (fsck.fat counts the volume label's entry as a file: "boot" makes it 2)
check "fsck.fat agrees: golden boot, label + 1 file, 5 clusters (FAT16)" '[ "$(fsck_clusters "$G" $((8192*512)) $((32768*512)))" = "2 5" ]'
check "fsck.fat agrees: music, 1 file, 29184 clusters (FAT32, root dir incl.)" '[ "$(fsck_clusters "$M" $((8192*512)) $((MS*512)))" = "1 29184" ]'
check "fsck.fat agrees: fresh, 1 file, 7 clusters" '[ "$(fsck_clusters "$F" $((8192*512)) $((FS*512)))" = "1 7" ]'

check "read-only: no image changed" '[ "$(sums)" = "$before" ]'

# the plan: CONTENT is printed before the -n exit AND before the confirmation,
# outside it — -y skips only the confirmation, never the table
hdr=$(grep -n 'DEVICE SERIAL PORT SIZE CONTENT' "$TOOL" | cut -d: -f1)
dry=$(grep -n '^if \[ "\$DRY" = 1 \]; then' "$TOOL" | cut -d: -f1)
yes=$(grep -n '^if \[ "\$YES" != 1 \]; then' "$TOOL" | cut -d: -f1)
check "plan prints CONTENT before the dry-run exit and the -y-skippable confirmation" \
      '[ -n "$hdr" ] && [ -n "$dry" ] && [ -n "$yes" ] && [ "$hdr" -lt "$dry" ] && [ "$hdr" -lt "$yes" ]'
check "the plan reads every card's content, whatever -y says" \
      'sed -n "${hdr},${dry}p" "$TOOL" | grep -q "content_cell" && ! sed -n "${hdr},${dry}p" "$TOOL" | grep -q "YES"'

# the -n fallback (a /dev node this user cannot read): udev's view, no error
U=""; for d in /sys/block/*; do d=${d##*/}; case "$d" in loop*|ram*|sr*|zram*) continue ;; esac
    [ -b "/dev/$d" ] && [ ! -r "/dev/$d" ] && { U=$d; break; }; done
if [ -n "$U" ]; then
    uout=$(bash "$TOOL" --content "$G" "/dev/$U" 2>&1 | plain); urc=$?
    want=$(lsblk -nro FSTYPE "/dev/$U" | grep -m1 .)
    check "unreadable /dev/$U: read from udev (${want:-no fs})" \
          '[ $urc -eq 0 ] && grep -q "/dev/$U:  " <<<"$uout" && { [ -z "$want" ] || grep -q "/dev/$U:  .*$want" <<<"$uout"; }'
else
    echo "  skip udev fallback (every disk here is readable — run as a plain user)"
fi

echo "burn-batch content desk: $PASS ok, $FAIL failed"
[ "$FAIL" -eq 0 ]
