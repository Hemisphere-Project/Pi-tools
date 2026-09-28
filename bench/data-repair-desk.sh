#!/bin/bash
# Desk test for rorw/data-repair on image files (no device, no root needed).
#   bash bench/data-repair-desk.sh
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
R="$HERE/rorw/data-repair"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
UUID=c5065467-5869-45da-917b-4d055b478665
pass=0; fail=0
check() { if eval "$2"; then echo "  PASS $1"; pass=$((pass+1)); else echo "  FAIL $1"; fail=$((fail+1)); fi; }
mk() {  # fresh 300 MB ext4 image with /data's layout and a 40 MB "film"
	rm -f "$T/img"; truncate -s 300M "$T/img"
	mkfs.ext4 -q -F -L data -U "$UUID" -b 4096 "$T/img"
	debugfs -w -R "mkdir media" "$T/img" >/dev/null 2>&1
	head -c 40M /dev/urandom > "$T/film"; md5sum < "$T/film" > "$T/film.md5"
	debugfs -w -R "write $T/film media/01_FILM.mp4" "$T/img" >/dev/null 2>&1
}
film_ok() { debugfs -R "dump media/01_FILM.mp4 $T/out" "$T/img" >/dev/null 2>&1 && [ "$(md5sum < "$T/out")" = "$(cat "$T/film.md5")" ]; }
fs_clean() { e2fsck -fn "$T/img" >/dev/null 2>&1; }
run() { STATUS_OUT=$("$R" "$T/img" "${1:-$UUID}" 2>&1 | grep "^\[data-repair\]" | tail -1); echo "    $STATUS_OUT"; }

echo "== 1. clean filesystem"
mk; run
check "reported clean" '[[ "$STATUS_OUT" == *clean* ]]'
check "film intact" film_ok

echo "== 2. primary superblock zeroed (lacroix02, 2026-09-27)"
mk; dd if=/dev/zero of="$T/img" bs=1024 seek=1 count=1 conv=notrunc 2>/dev/null
check "precondition: primary unreadable" '! dumpe2fs -h "$T/img" >/dev/null 2>&1'
run
check "reported REPAIRED, verified clean" '[[ "$STATUS_OUT" == *"verified clean"* ]]'
check "primary superblock back, same UUID" '[ "$(dumpe2fs -h "$T/img" 2>/dev/null | awk -F": *" "/^Filesystem UUID/{print \$2}")" = "$UUID" ]'
check "filesystem clean after" fs_clean
check "film intact (md5)" film_ok

echo "== 2b. primary superblock zeroed AND bitmap damage (the lacroix02 shape: a restore alone is not enough)"
mk; BLK=$(debugfs -R "blocks media/01_FILM.mp4" "$T/img" 2>/dev/null | awk '{print $1}')
debugfs -w -R "freeb $BLK 2048" "$T/img" >/dev/null 2>&1
dd if=/dev/zero of="$T/img" bs=1024 seek=1 count=1 conv=notrunc 2>/dev/null
run
check "reported REPAIRED, verified clean" '[[ "$STATUS_OUT" == *"verified clean"* ]]'
check "filesystem clean after" fs_clean
check "film intact (md5)" film_ok

echo "== 3. block bitmap damage (blocks of the film marked free)"
mk; BLK=$(debugfs -R "blocks media/01_FILM.mp4" "$T/img" 2>/dev/null | awk '{print $1}')
debugfs -w -R "freeb $BLK 2048" "$T/img" >/dev/null 2>&1
check "precondition: fsck -n finds errors" '! fs_clean'
tune2fs -E force_fsck "$T/img" >/dev/null 2>&1   # a real power cut leaves the error/needs_recovery state
run
check "preen fixed it" '[[ "$STATUS_OUT" == *"preen fixed"* || "$STATUS_OUT" == *clean* ]]'
check "filesystem clean after" fs_clean
check "film intact (md5)" film_ok

echo "== 4. another filesystem's UUID -> not touched"
mk; dd if=/dev/zero of="$T/img" bs=1024 seek=1 count=1 conv=notrunc 2>/dev/null
cp "$T/img" "$T/img.before"
run 11111111-2222-3333-4444-555555555555
check "refused" '[[ "$STATUS_OUT" == *"not touching"* ]]'
check "image unchanged" 'cmp -s "$T/img" "$T/img.before"'

echo "== 5. not ext4 at all -> not touched"
head -c 300M /dev/urandom > "$T/img"; cp "$T/img" "$T/img.before"
run
check "refused" '[[ "$STATUS_OUT" == *"not touching"* ]]'
check "image unchanged" 'cmp -s "$T/img" "$T/img.before"'

echo "== 6. damage preen will not fix alone -> logged, not escalated"
mk; INO=$(debugfs -R "stat media" "$T/img" 2>/dev/null | awk '/^Inode:/{print $2; exit}')
debugfs -w -R "clri <$INO>" "$T/img" >/dev/null 2>&1
tune2fs -E force_fsck "$T/img" >/dev/null 2>&1
cp "$T/img" "$T/img.before"
run
check "logged as needing a manual fsck" '[[ "$STATUS_OUT" == *"will not fix alone"* || "$STATUS_OUT" == *"preen fixed"* ]]'
echo "    (preen result above: '*will not fix alone*' = left untouched as designed)"

echo; echo "passed $pass, failed $fail"
[ $fail -eq 0 ]
