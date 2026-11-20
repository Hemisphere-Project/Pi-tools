#!/usr/bin/env bash
# capture-desk.sh — image/rastaos-capture from a keyboard: a fixture card behind a stub ssh (no card,
# no root).
#
#   bash bench/capture-desk.sh
#
# `pull`: the stub ssh runs the remote scripts here, with findmnt/sfdisk/blkid/e2image/fsfreeze stubbed
# around fixture partitions — refusals before any read (/ or /boot rw, rw count, /data not p3), the
# pieces byte-for-byte, SHA256SUMS, /data frozen for its read only and thawed even when the read dies.
# `build -n`: the checks (SHA256SUMS present, covering, matching; a p3 in the table) and the image's
# table (p3 at --data-mib, no p4, no last-lba, the card's disk id). The root half — loop mount, seal,
# fsck, flightbox-p4 --check — is not run here: seal is bake-desk.sh's, the rest burn-batch's.
set -uo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd); CAP=$HERE/image/rastaos-capture
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0 fail=0
ok()  { pass=$((pass+1)); echo "  ok   $*"; }
bad() { fail=$((fail+1)); echo "  FAIL $*"; }
chk() { local what=$1; shift; if "$@"; then ok "$what"; else bad "$what"; fi; }

# the card: three partitions as files, and the table the card's sfdisk prints (a p4 from a --flightbox burn)
C=$T/card; S=$T/state; X=$T/stubs; mkdir -p "$C" "$S" "$X"
DEV=$C/mmcblk0
head -c 3145728 /dev/urandom > "${DEV}p1"; head -c 5242880 /dev/urandom > "${DEV}p2"; head -c 4194304 /dev/urandom > "${DEV}p3"
cat > "$S/table" <<EOF
label: dos
label-id: 0x3c1d2e9f
device: $DEV
unit: sectors
sector-size: 512

${DEV}p1 : start=        8192, size=      524288, type=c
${DEV}p2 : start=      532480, size=    10485760, type=83
${DEV}p3 : start=    11018240, size=    50331648, type=83
${DEV}p4 : start=    61349888, size=     1048576, type=da
EOF
reset_card() { echo ro,relatime > "$S/root"; echo ro,relatime > "$S/boot"; echo "${DEV}p3" > "$S/data"; echo 0 > "$S/rw.count"; rm -f "$S/e2fail" "$S/freeze.log" "$S/e2image.log"; }

# the stub ssh: options and host dropped, the remote script run HERE with the card's tools stubbed and
# its rw counter pointed at the fixture
cat > "$X/ssh" <<EOF
#!/usr/bin/env bash
while [ \$# -gt 0 ]; do case \$1 in -o) shift 2 ;; -*) shift ;; *) break ;; esac; done
shift    # the host
sed 's#/run/pitools-rw.count#$S/rw.count#g' | PATH=$X/card:\$PATH bash -c "\$*"
EOF
mkdir -p "$X/card"
cat > "$X/card/findmnt" <<EOF
#!/usr/bin/env bash
case "\$*" in
  '-no OPTIONS /') cat "$S/root" ;; '-no OPTIONS /boot') cat "$S/boot" ;; '-no SOURCE /data') cat "$S/data" ;; *) exit 1 ;;
esac
EOF
cat > "$X/card/sfdisk" <<EOF
#!/usr/bin/env bash
[ "\$*" = "-d $DEV" ] && cat "$S/table"
EOF
cat > "$X/card/blkid" <<EOF
#!/usr/bin/env bash
echo '${DEV}p1: LABEL_FATBOOT="boot" TYPE="vfat" PARTUUID="3c1d2e9f-01"'
echo '${DEV}p2: LABEL="rootfs" TYPE="ext4" PARTUUID="3c1d2e9f-02"'
EOF
cat > "$X/card/e2image" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$S/e2image.log"
dev=\${@: -2:1}
case \$dev in *p3) [ -e "$S/e2fail" ] && { head -c 1000 "\$dev"; exit 1; } ;; esac
cat "\$dev"
EOF
cat > "$X/card/fsfreeze" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$S/freeze.log"
EOF
chmod 755 "$X/ssh" "$X/card"/*
export PATH=$X:$PATH

# ---------------------------------------------------------------- pull: refusals
refused() { # refused <what> <state file> <value>
  reset_card; echo "$3" > "$S/$2"; rm -rf "$T/st"
  "$CAP" pull bench-01 "$T/st" --dev "$DEV" > "$T/out" 2>&1; local rc=$?
  chk "pull refuses $1 (exit 1)" [ "$rc" = 1 ]
  chk "  …says why" grep -q "$4" "$T/out"
  chk "  …and reads nothing, freezes nothing" sh -c "[ ! -e '$T/st/p1.raw.gz' ] && [ ! -e '$S/freeze.log' ] && [ ! -e '$S/e2image.log' ]"
}
refused "a read-write /" root rw,relatime "/ is not read-only"
refused "a read-write /boot" boot rw,relatime "/boot is not read-only"
refused "an open rw (count 1)" rw.count 1 "rw count is 1"
refused "a /data that is not p3" data /dev/sda1 "/data is '/dev/sda1'"
chk "pull with one argument is usage (exit 2)" sh -c "'$CAP' pull bench-01 >/dev/null 2>&1; [ \$? = 2 ]"
chk "an unknown verb is usage (exit 2)" sh -c "'$CAP' grab >/dev/null 2>&1; [ \$? = 2 ]"

# ---------------------------------------------------------------- pull: the read
reset_card; ST=$T/stage
echo "pull"; "$CAP" pull bench-01 "$ST" --dev "$DEV" > "$T/pull.log" 2>&1; rcp=$?; sed 's/^/    /' "$T/pull.log"
chk "pull exits 0" [ "$rcp" = 0 ]
for p in p1 p2 p3; do chk "$p.raw.gz = the card's $p" sh -c "gzip -dc '$ST/$p.raw.gz' | cmp -s - '${DEV}$p'"; done
chk "table.sfdisk = the card's sfdisk -d" cmp -s "$ST/table.sfdisk" "$S/table"
chk "table.txt = the table + blkid" sh -c "grep -q 'label-id: 0x3c1d2e9f' '$ST/table.txt' && grep -q 'PARTUUID=\"3c1d2e9f-02\"' '$ST/table.txt'"
chk "SHA256SUMS covers the five pieces and checks" sh -c "cd '$ST' && [ \$(wc -l < SHA256SUMS) = 5 ] && sha256sum -c --quiet SHA256SUMS"
chk "p2 read with -ra (read-only mount), p3 with -fra" sh -c "grep -qx -- '-ra ${DEV}p2 -' '$S/e2image.log' && grep -qx -- '-fra ${DEV}p3 -' '$S/e2image.log'"
chk "/data frozen once, before its read" [ "$(grep -c -- '^-f /data$' "$S/freeze.log")" = 1 ]
chk "  …and thawed after it" [ "$(tail -1 "$S/freeze.log")" = "-u /data" ]

# a read that dies mid-way: /data is thawed all the same, and the stage carries no SHA256SUMS
reset_card; touch "$S/e2fail"
"$CAP" pull bench-01 "$T/st2" --dev "$DEV" > "$T/out" 2>&1; rc=$?
chk "a failed /data read fails the pull (exit 1)" [ "$rc" = 1 ]
chk "  …thaws /data" sh -c "[ \"\$(head -1 '$S/freeze.log')\" = '-f /data' ] && [ \"\$(tail -1 '$S/freeze.log')\" = '-u /data' ]"
chk "  …the remote script's own trap thaws it, before the belt-and-braces one" [ "$(grep -c -- '^-u /data$' "$S/freeze.log")" = 2 ]
chk "  …and leaves no SHA256SUMS" [ ! -e "$T/st2/SHA256SUMS" ]

# ---------------------------------------------------------------- build -n
echo "build -n"; "$CAP" build -n "$ST" > "$T/plan.log" 2>&1; rcn=$?; sed 's/^/    /' "$T/plan.log"
chk "build -n exits 0, no root" [ "$rcn" = 0 ]
chk "  …p3 at 256 MiB (524288 sectors), same start" grep -qE "p3 : start= +11018240, size= 524288, type=83" "$T/plan.log"
chk "  …no p4 in the image" sh -c "! grep -q 'p4 :' '$T/plan.log'"
chk "  …and says the card's p4 is left out" grep -q "p4+ left out" "$T/plan.log"
chk "  …the card's disk id kept (PARTUUIDs)" grep -q 'label-id: 0x3c1d2e9f' "$T/plan.log"
chk "  …p1 and p2 as on the card" sh -c "grep -qE 'p1 : start= +8192, size= +524288' '$T/plan.log' && grep -qE 'p2 : start= +532480, size= +10485760' '$T/plan.log'"
chk "  …image size = p3's end" grep -q "$(( (11018240 + 524288) * 512 )) B" "$T/plan.log"
chk "  …writes nothing" sh -c "[ ! -e '$ST/RastaOS-7.5.img' ] && [ ! -e '$ST/table.image.sfdisk' ]"
"$CAP" build -n --data-mib 512 "$ST" > "$T/plan2.log" 2>&1
chk "--data-mib 512 → 1048576 sectors" grep -qE "p3 : start= +11018240, size= 1048576," "$T/plan2.log"
chk "--data-mib not a number is usage (exit 2)" sh -c "'$CAP' build -n --data-mib 1g '$ST' >/dev/null 2>&1; [ \$? = 2 ]"
chk "--keys naming no file is usage (exit 2)" sh -c "'$CAP' build -n --keys '$T/nokeys' '$ST' >/dev/null 2>&1; [ \$? = 2 ]"
if [ "$(id -u)" != 0 ]; then
  chk "build without -n and without root refuses (exit 2)" sh -c "'$CAP' build '$ST' >/dev/null 2>&1; [ \$? = 2 ]"
  chk "  …and writes nothing" [ ! -e "$ST/RastaOS-7.5.img" ]
fi

# a short copy, a missing sum, a table with no p3: refused before any write
cp -a "$ST" "$T/bad"; printf x >> "$T/bad/p2.raw.gz"
"$CAP" build -n "$T/bad" > "$T/out" 2>&1; rc=$?
chk "build refuses a piece that does not match its sum (exit 1)" sh -c "[ $rc = 1 ] && grep -q 'do not match SHA256SUMS' '$T/out'"
rm -rf "$T/bad"; cp -a "$ST" "$T/bad"; sed -i '/p3\.raw\.gz/d' "$T/bad/SHA256SUMS"
"$CAP" build -n "$T/bad" > "$T/out" 2>&1; rc=$?
chk "build refuses a SHA256SUMS that skips p3 (exit 1)" sh -c "[ $rc = 1 ] && grep -q 'does not cover p3.raw.gz' '$T/out'"
rm "$T/bad/SHA256SUMS"
chk "build refuses a stage with no SHA256SUMS (exit 1)" sh -c "'$CAP' build -n '$T/bad' >/dev/null 2>&1; [ \$? = 1 ]"
rm -rf "$T/bad"; cp -a "$ST" "$T/bad"; sed -i '/p3 :/d' "$T/bad/table.sfdisk"; (cd "$T/bad" && sha256sum table.txt table.sfdisk p1.raw.gz p2.raw.gz p3.raw.gz > SHA256SUMS)
"$CAP" build -n "$T/bad" > "$T/out" 2>&1; rc=$?
chk "build refuses a table with no p3 (exit 1)" sh -c "[ $rc = 1 ] && grep -q 'names no p3' '$T/out'"

echo "capture-desk: $pass ok, $fail failed"
[ "$fail" = 0 ]
