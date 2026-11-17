#!/bin/bash
# Desk test for blackbox/journal-export v4 and blackbox's v3d guards (pi-tools#t-053) — no Pi, no card.
#   bash bench/journal-export-desk.sh
# A (any user): journal-export against a stub journalctl that SELECTS entries the way systemd 241 does
#   (RastaOS 7.3; journalctl.c at v241: the seek block, then the show loop that stops at n_shown ==
#   arg_lines — so after a cursor `-n N` keeps the OLDEST N), with the real `diag` and the real
#   `flightbox` on a plain-file ring.
# B (root, or `sudo -n`): blackbox's /tmp guard, its `run=` field and `run-cap`, on real tmpfs mounts in
#   a private mount namespace — the host's /tmp and /run are never seen. No root: SKIP, said so.
# What a green does NOT prove: anything about systemd 241 itself (the stub is a reading of its source),
# about a card, or about a boot. One real card boot is the bench's (hardware-gate).
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
check() { if eval "$2"; then echo "  PASS $1"; pass=$((pass+1)); else echo "  FAIL $1"; fail=$((fail+1)); fi; }

# ---- B, run as root inside `unshare -m --propagation private` (see the bottom of this file) ----
if [ "${1:-}" = --ns ]; then
	mount -t tmpfs -o size=8M tmpfs /mnt && mount -t tmpfs -o size=64M tmpfs /tmp && mount -t tmpfs -o size=64M tmpfs /run \
		|| { echo "  FAIL could not mount the private tmpfs set"; exit 1; }
	B=/mnt; mkdir -p "$B/bin"
	printf '#!/bin/sh\necho "$*" >> %s/logger.txt\n' "$B" > "$B/bin/logger"
	printf '#!/bin/sh\nexit 0\n' > "$B/bin/journalctl"                      # the host's journal is not this test's
	chmod +x "$B/bin/"*; : > "$B/logger.txt"
	export PATH="$B/bin:$PATH" DIAG_STATE=$B/diag-armed BLACKBOX_LOG=/run/blackbox.log BLACKBOX_ARCHIVE=$B/archive
	BB="$HERE/blackbox/blackbox"
	echo "== B1. /tmp under 90 %: a 21 MB file is left alone; the line carries tmp= and run="
	head -c 21M /dev/zero > /tmp/big1
	bash "$BB" 2>/dev/null
	check "21 MB file at 33 % untouched" '[ "$(stat -c %s /tmp/big1)" = 22020096 ]'
	check "one line with tmp=33% run=N%" 'tail -n 1 /run/blackbox.log | grep -qE " tmp=33% run=[0-9]+% "'
	check "no tmp-guard line" '! grep -q tmp-guard "$B/logger.txt"'
	echo "== B2. /tmp past 90 %: every file over 20 MB truncated, smaller ones kept, each one logged"
	head -c 37M /dev/zero > /tmp/big2; head -c 1M /dev/zero > /tmp/small
	bash "$BB" 2>/dev/null
	check "both big files emptied" '[ "$(stat -c %s /tmp/big1)" = 0 ] && [ "$(stat -c %s /tmp/big2)" = 0 ]'
	check "the 1 MB file kept" '[ "$(stat -c %s /tmp/small)" = 1048576 ]'
	check "two tmp-guard lines naming file and size" '[ "$(grep -c "tmp-guard: /tmp at 9[0-9]%, truncated /tmp/big[12] ([0-9]* bytes)" "$B/logger.txt")" = 2 ]'
	check "the line reads the relieved /tmp" 'tail -n 1 /run/blackbox.log | grep -q " tmp=2% "'
	echo "== B3. run-cap: a 300 MB /run comes down to 160 MB"
	mount -t tmpfs -o size=300M tmpfs /run
	bash "$BB" run-cap; rc=$?
	check "exit 0" '[ "$rc" = 0 ]'
	check "/run is 160 MB" '[ "$(df -Pk /run | awk "NR==2{print \$2}")" = 163840 ]'
	check "logged 300 -> 160" 'grep -q "run-cap: /run 300 MB -> 160 MB" "$B/logger.txt"'
	echo "== B4. run-cap shrinks only: a 100 MB /run stays 100 MB"
	mount -t tmpfs -o size=100M tmpfs /run; n0=$(grep -c run-cap "$B/logger.txt")
	bash "$BB" run-cap
	check "/run still 100 MB" '[ "$(df -Pk /run | awk "NR==2{print \$2}")" = 102400 ]'
	check "nothing logged" '[ "$(grep -c run-cap "$B/logger.txt")" = "$n0" ]'
	echo "== B5. run-cap under what /run holds: refused by the kernel, logged, exit 0 (a boot goes on)"
	mount -t tmpfs -o size=300M tmpfs /run; head -c 20M /dev/zero > /run/fill
	BLACKBOX_RUN_CAP_MB=8 bash "$BB" run-cap; rc=$?
	check "exit 0" '[ "$rc" = 0 ]'
	check "/run unchanged at 300 MB" '[ "$(df -Pk /run | awk "NR==2{print \$2}")" = 307200 ]'
	check "logged the refusal with what it holds" 'grep -q "run-cap: could not cap /run at 8 MB (holds 20 MB)" "$B/logger.txt"'
	[ "$fail" -eq 0 ]; exit $?
fi

# ---- A ----
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/fbbin" "$T/data" "$T/run"
export JOURNAL_EXPORT_DATA=$T/data JOURNAL_EXPORT_RUN_DIR=$T/run DIAG_STATE=$T/data/var/diag-armed \
	BLACKBOX_LOG=$T/run/blackbox.log BLACKBOX_ARCHIVE=$T/data/var/log/blackbox.log JDB=$T/journal.tsv LOGGER_OUT=$T/logger.txt
OUT=$T/data/var/log/journal-export; TODAY=$(date +%F); F=$OUT/$TODAY.log; CUR=$T/run/journal-export.cursor; DAY=$T/run/journal-export.day
JE="$HERE/blackbox/journal-export"
ln -s "$HERE/blackbox/diag" "$T/bin/diag"
ln -s "$HERE/flightbox/flightbox" "$T/fbbin/flightbox"
printf '#!/bin/sh\necho "$*" >> "$LOGGER_OUT"\n' > "$T/bin/logger"
cat > "$T/bin/journalctl" <<'STUB'
#!/bin/bash
# journalctl stub: systemd 241's entry SELECTION over $JDB ("<seq>\t<short-iso text>", `\n` = a
# continuation line); cursor "s=<seq>". After a cursor: forward, the first N. -n alone: the last N.
after=""; n=-1; cur=0; fmt=short-iso; since=""; other=""
while [ $# -gt 0 ]; do case $1 in
	--after-cursor=*) after=${1#*=} ;;
	-n) n=$2; shift ;;
	--show-cursor) cur=1 ;;
	-o) fmt=$2; shift ;;
	--since) since=$2; shift ;;
	--no-pager|-q) ;;
	*) other=1 ;;
esac; shift; done
[ -n "$other" ] && exit 0
touch "$JDB"
if [ -n "$after" ]; then
	case $after in s=[0-9]*) ;; *) echo "Failed to seek to cursor: Invalid argument" >&2; exit 1 ;; esac
	sel=$(awk -F'\t' -v a="${after#s=}" -v n="$n" '$1 > a+0 && (n < 0 || c++ < n)' "$JDB")
elif [ -n "$since" ] || [ "$n" -lt 0 ]; then sel=$(cat "$JDB")
else sel=$(tail -n "$n" "$JDB"); fi
[ -s "$JDB" ] && [ "$n" != 0 ] && echo "-- Logs begin at Mon 2026-10-05 00:00:00 CEST, end at Tue 2026-10-06 00:00:00 CEST. --"
printf '%s\n' "$sel" | awk -F'\t' -v f="$fmt" 'NF { t = $2; if (f == "cat") sub(/^[^ ]+ [^ ]+ [^ ]+ /, "", t); gsub(/\\n/, "\n", t); print t }'
last=$(printf '%s\n' "$sel" | awk -F'\t' 'NF { s = $1 } END { print s }')
[ "$cur" = 1 ] && [ -n "$last" ] && echo "-- cursor: s=$last"
exit 0
STUB
chmod +x "$T/bin/logger" "$T/bin/journalctl"
P0=$PATH
je()   { PATH="$T/bin:$P0" bash "$JE" "$@"; }                 # no flightbox: the /data fallback
jefb() { PATH="$T/fbbin:$T/bin:$P0" bash "$JE" "$@"; }
SEQ=0
add() { local i; for i in $(seq "$1"); do SEQ=$((SEQ+1)); printf '%d\t2026-10-06T00:00:00+0200 W1 hplayer2[42]: entry %d%s\n' "$SEQ" "$SEQ" "${2:-}" >> "$JDB"; done; }
ents() { grep -c ' entry [0-9]' "$1" 2>/dev/null; }

check "precondition: no flightbox on this PATH" '! PATH="$T/bin:$P0" command -v flightbox >/dev/null'

echo "== A1. disarmed: nothing reaches the card — hourly, --now, bb-only"
add 20; echo "bb line1" > "$BLACKBOX_LOG"
je; je --now mpv; je bb-only
check "no file under /data" '[ -z "$(find "$T/data" -type f)" ]'
check "no cursor taken" '[ ! -e "$CUR" ]'

echo "== A2. armed: the hourly run archives blackbox and exports the journal; one armed hour consumed"
PATH="$T/bin:$P0" diag arm 336 >/dev/null; add 1 '\n    a continuation line'
je
check "diag counted one hour down (336 -> 335)" '[ "$(cat "$DIAG_STATE")" = 335 ]'
check "archive = the live line, byte for byte" 'cmp -s "$BLACKBOX_LOG" "$BLACKBOX_ARCHIVE"'
check "21 entries exported, continuation kept" '[ "$(ents "$F")" = 21 ] && grep -q "^    a continuation line" "$F"'
check "journalctl header not exported" '! grep -q "Logs begin" "$F"'
check "cursor in /run = the newest entry" '[ "$(cat "$CUR")" = "s=21" ]'
check "day count = bytes written" '[ "$(cut -d" " -f2 "$DAY")" = "$(stat -c %s "$F")" ]'

echo "== A3. the next run: only what is new"
add 4; echo "bb line2" >> "$BLACKBOX_LOG"
je
check "25 entries, none twice" '[ "$(ents "$F")" = 25 ] && [ -z "$(grep -o " entry [0-9]*" "$F" | sort | uniq -d)" ]'
check "bb line2 archived once" '[ "$(grep -c "bb line2" "$BLACKBOX_ARCHIVE")" = 1 ]'

echo "== A4. an EMPTY offset file (blackbox's rotation) restarts the archive at 0 — v3b froze W3 25->28/09"
mv "$BLACKBOX_LOG" "$BLACKBOX_LOG.1"; echo "bb line3 after rotation" > "$BLACKBOX_LOG"; : > "$T/run/blackbox.exported"
je
check "the new file's line archived" 'grep -q "bb line3" "$BLACKBOX_ARCHIVE"'
check "offset = the new live size" '[ "$(cat "$T/run/blackbox.exported")" = "$(stat -c %s "$BLACKBOX_LOG")" ]'

echo "== A5. the day cap counts what v4 wrote, not an inherited file (W1/W2/W4 capped at install, 29/09)"
rm -f "$DAY"; truncate -s 60M "$F"; add 3
je
check "exported despite a 60 MB file of today (cap 24 MB)" 'tail -n 3 "$F" | grep -q "entry $SEQ$"'
check "no cap marker" '! grep -aq "daily cap" "$F"'

echo "== A6. near the cap a run is clipped to what is left; at the cap: one marker, then silence"
echo "$TODAY $((24*1048576 - 300))" > "$DAY"; s0=$(stat -c %s "$F"); add 50
je
grow=$(( $(stat -c %s "$F") - s0 ))
check "grew by at most 300 B + the marker ($grow B)" '[ "$grow" -le 420 ] && [ "$grow" -gt 0 ]'
check "the newest entry kept" 'tail -n 1 "$F" | grep -q "entry $SEQ$"'
add 5; je; s1=$(stat -c %s "$F"); add 5; je
check "one daily-cap marker" '[ "$(grep -ac "daily cap 24 MB reached" "$F")" = 1 ]'
check "then nothing" '[ "$(stat -c %s "$F")" = "$s1" ]'
check "the cursor kept walking" '[ "$(cat "$CUR")" = "s=$SEQ" ]'

echo "== A7. a storm — LINES_CAP or more waiting: the NEWEST kept (on 241, -n after a cursor keeps the oldest)"
rm -f "$DAY"; s0=$SEQ; add 250
JOURNAL_EXPORT_LINES=100 je
check "the newest entry exported" 'grep -q "entry $SEQ$" "$F"'
check "the oldest of the 250 not" '! grep -q "entry $((s0+1))$" "$F"'
check "exactly the newest 100" '[ "$(grep -ao " entry [0-9]*" "$F" | awk "\$2 > $s0" | wc -l)" = 100 ]'
check "a marker says older ones were skipped" 'grep -aq "the newest 100 kept, older ones skipped" "$F"'
check "cursor = the newest" '[ "$(cat "$CUR")" = "s=$SEQ" ]'

echo "== A8. run cap: the newest bytes, from a whole line"
s0=$(stat -c %s "$F"); add 40
JOURNAL_EXPORT_RUN_BYTES=500 je
check "grew by at most 500 B + the marker" '[ $(( $(stat -c %s "$F") - s0 )) -le 620 ]'
check "a marker, then whole lines only" 'tail -c +$((s0+1)) "$F" | grep -aq "byte cap (run or day): the newest 500 bytes kept" && ! tail -c +$((s0+1)) "$F" | grep -av -e "^-- journal-export" -e "^2026-10-06T00:00:00+0200 W1" | grep -aq .'
check "the newest entry kept" 'grep -q "entry $SEQ$" "$F"'

echo "== A9. a cursor journalctl refuses: the newest entries, not silence until the next reboot"
echo "garbage" > "$CUR"; add 3
je
check "the 3 new entries exported" 'tail -n 3 "$F" | grep -q "entry $SEQ$"'
check "cursor valid again" '[ "$(cat "$CUR")" = "s=$SEQ" ]'

echo "== A10. prune: by age, then by size, oldest first — never today's file"
head -c 1M /dev/zero > "$OUT/2026-01-01.log"; touch -d '30 days ago' "$OUT/2026-01-01.log"
head -c 2M /dev/zero > "$OUT/2026-10-03.log"; touch -d '3 days ago' "$OUT/2026-10-03.log"
head -c 2M /dev/zero >> "$F"; echo >> "$F"                 # real blocks: A5's 60 MB are sparse
add 1
JOURNAL_EXPORT_MAX_MB=1 je
check "the 30-day-old file pruned" '[ ! -e "$OUT/2026-01-01.log" ]'
check "over MAX_MB: the older file pruned" '[ ! -e "$OUT/2026-10-03.log" ]'
check "today's file kept though alone over MAX_MB" '[ -s "$F" ]'
touch -d '30 days ago' "$F"                                # a fake clock that jumped: nothing new this hour
je
check "today's file kept though its mtime reads 30 days old" '[ -s "$F" ]'

echo "== A11. --now while armed: reason + blackbox lines + the newest journal bytes, capped; counts no hour"
h0=$(cat "$DIAG_STATE"); add 100
JOURNAL_EXPORT_DUMP_BYTES=2000 je --now mpv >/dev/null
D=$(ls "$OUT"/dumps/*-mpv.log 2>/dev/null)
check "one dump named for its reason" '[ "$(ls "$OUT"/dumps | wc -l)" = 1 ] && [ -n "$D" ]'
check "at most 2000 B" '[ "$(stat -c %s "$D")" -le 2000 ]'
check "opens with the reason and the blackbox lines" 'head -n 3 "$D" | grep -q "### anomaly: mpv" && grep -q "bb line3" "$D"'
check "ends with the newest entry" 'tail -n 1 "$D" | grep -q "entry $SEQ$"'
check "no armed hour consumed (--peek)" '[ "$(cat "$DIAG_STATE")" = "$h0" ]'

echo "== A12. flightbox: the same runs become ring records; nothing new in /data's trail"
export FLIGHTBOX_DEVICE=$T/ring FLIGHTBOX_RUN_DIR=$T/fbrun; mkdir -p "$T/fbrun"; truncate -s 8M "$T/ring"
rm -f "$DAY"; s0=$(stat -c %s "$F"); a0=$(stat -c %s "$BLACKBOX_ARCHIVE"); add 5; echo "bb line4" >> "$BLACKBOX_LOG"
jefb
FBD=$("$HERE/flightbox/flightbox" dump 2>/dev/null)
check "today's file and the archive untouched" '[ "$(stat -c %s "$F")" = "$s0" ] && [ "$(stat -c %s "$BLACKBOX_ARCHIVE")" = "$a0" ]'
check "a journal record ending with the newest entry" 'printf "%s\n" "$FBD" | grep -q "tag=journal" && printf "%s\n" "$FBD" | grep -q "entry $SEQ$"'
check "a blackbox record with bb line4" 'printf "%s\n" "$FBD" | grep -q "tag=blackbox" && printf "%s\n" "$FBD" | grep -q "bb line4"'
check "the day count counts ring bytes too" '[ "$(cut -d" " -f2 "$DAY")" -gt 0 ]'
jefb --now restart >/dev/null
check "--now: an anomaly record, no new dump file" '"$HERE/flightbox/flightbox" dump 2>/dev/null | grep -q "### anomaly: restart" && [ "$(ls "$OUT"/dumps | wc -l)" = 1 ]'
add 2; FLIGHTBOX_DEVICE=$T/no-such-dir/ring jefb
check "ring unavailable: back to /data, nothing lost" 'tail -n 2 "$F" | grep -q "entry $SEQ$"'

echo "== A13. nothing written anywhere (no ring, /data refusing): the cursor stays, the next run catches up"
c0=$(cat "$CUR"); add 3; touch "$T/notadir"
JOURNAL_EXPORT_DIR=$T/notadir/je je
check "cursor unchanged" '[ "$(cat "$CUR")" = "$c0" ]'
je
check "the 3 entries reach /data on the next run" 'tail -n 3 "$F" | grep -q "entry $SEQ$" && [ "$(cat "$CUR")" = "s=$SEQ" ]'

echo "== A14. status: one line — where, what today, diag"
check "status names today's count, the cap and diag" 'je status | grep -q "written $TODAY [0-9]* *(cap 24 MB).*flightbox: none" && je status | grep -q "diag: armed"'

echo "== B. blackbox v3d guards (root in a private mount namespace)"
if [ "$(id -u)" = 0 ]; then RB=(unshare -m --propagation private bash "$HERE/bench/journal-export-desk.sh" --ns)
elif sudo -n true 2>/dev/null; then RB=(sudo -n unshare -m --propagation private bash "$HERE/bench/journal-export-desk.sh" --ns)
else RB=(); fi
if [ ${#RB[@]} -gt 0 ]; then
	OB=$("${RB[@]}" 2>&1); echo "$OB"
	pass=$((pass + $(printf '%s\n' "$OB" | grep -c '^  PASS'))); fail=$((fail + $(printf '%s\n' "$OB" | grep -c '^  FAIL')))
else
	echo "  SKIP — needs root or sudo -n (a private /tmp and /run); part A ran"
fi

echo; echo "journal-export-desk: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
