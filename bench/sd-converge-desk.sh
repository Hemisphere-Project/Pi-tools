#!/usr/bin/env bash
# sd-converge-desk — desk test of sd-converge's read side (pi-tools#t-070): a
# dry run, and a card already at its target, leave the card's checkouts as
# they were — .git/index byte-identical, same mtime, no file owned by root.
#
#   bash bench/sd-converge-desk.sh       # exit 0 green, 1 red, 2 could not run
#
# No device, no mount: `--apply-to` on a throwaway card tree whose /opt/Pi-tools
# and /opt/HPlayer2 are clones of two throwaway source repos (the tool converges
# from the Pi-tools checkout it lives in, so it is copied into that source). A
# tracked file's mtime is touched on the card first: a plain `git status` then
# refreshes the index and writes it back — as root, a root-owned index on the
# card. Nothing on the card may be newer than a mark taken before the run. Run as root, the card tree is given to uid 65534 first and must hold no
# root-owned file after; unprivileged, or on a git that refuses a repo another
# user owns (buster's 2.20 backport — the rig's players), that check is skipped
# and says so: the index checks still run.
#
# Not proven here: a real card mount, the carousel, the eject.
#
# SD_CONVERGE=<path> runs another copy of the tool (a mutation test).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 2
TOOL=$(readlink -f "${SD_CONVERGE:-bench/sd-converge}")
[ -f "$TOOL" ] || { echo "no tool at $TOOL"; exit 2; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; [ -n "${OUT:-}" ] && tail -6 <<<"$OUT" | sed "s/^/       > /"; }
OUT=""
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
ROOT=0; [ "$(id -u)" = 0 ] && ROOT=1

G() { git -c user.name=desk -c user.email=desk@localhost "$@"; }
mk_src() {    # mk_src <dir> — a repo on branch main (git 2.20 has no init -b)
    G init -q "$1" && G -C "$1" symbolic-ref HEAD refs/heads/main
}
commit() { G -C "$1" add -A && G -C "$1" commit -q -m "$2"; }

PT=$T/src/Pi-tools; HP=$T/src/HPlayer2; CARD=$T/card
mk_src "$PT"; mkdir -p "$PT/bench" "$PT/audiohub"
cp "$TOOL" "$PT/bench/sd-converge"
printf '# audiohub-graph-v2.1 pi3\n' > "$PT/audiohub/asound.conf-pi3"
echo one > "$PT/README"; commit "$PT" one
mk_src "$HP"; echo one > "$HP/README"; commit "$HP" one
mkdir -p "$CARD/etc" "$CARD/opt"
echo player-desk > "$CARD/etc/hostname"
cp "$PT/audiohub/asound.conf-pi3" "$CARD/etc/asound.conf"
G clone -q "$PT" "$CARD/opt/Pi-tools" && G clone -q "$HP" "$CARD/opt/HPlayer2" || exit 2
echo two > "$PT/NEWS"; commit "$PT" two          # the bench is one commit ahead
echo two > "$HP/NEWS"; commit "$HP" two
TARGET_PT=$(git -C "$PT" rev-parse --short HEAD); TARGET_HP=$(git -C "$HP" rev-parse --short HEAD)
OWNCHK=0; WHY="needs root (sudo bash $0)"
if [ "$ROOT" = 1 ]; then                     # the card's user, not root
    chown -R 65534:65534 "$CARD"
    if git -c safe.directory='*' -C "$CARD/opt/Pi-tools" rev-parse --git-dir >/dev/null 2>&1; then
        OWNCHK=1
    else    # a git < 2.36 carrying the CVE-2022-24765 backport (buster's 2.20.1+deb10u*)
        chown -R 0:0 "$CARD"                 # refuses it under any safe.directory
        WHY="this git refuses a repo another user owns, even under safe.directory='*' — run it on the bench laptop"
    fi
fi

run() { OUT=$(SDCONVERGE_HPLAYER2_SRC="$HP" SDCONVERGE_LOG="$T/log.csv" \
              bash "$PT/bench/sd-converge" "$@" --apply-to "$CARD" 2>&1); RC=$?; }
stale() {     # a tracked file's stat moves, its content does not
    touch -d '2026-01-01 00:00' "$CARD/opt/Pi-tools/README" "$CARD/opt/HPlayer2/README"
}
idx() { local r; for r in Pi-tools HPlayer2; do
            sha256sum < "$CARD/opt/$r/.git/index"; stat -c %y "$CARD/opt/$r/.git/index"
        done; }
head_of() { git -C "$CARD/opt/$1" rev-parse --short HEAD; }
mark()    { touch "$T/mark"; }            # then: nothing on the card newer than it
untouched() { check "$1: nothing on the card written (find -newer)" '[ -z "$(find "$CARD" -newer "$T/mark" | head -1)" ]'; }
no_root_file() {
    if [ "$OWNCHK" = 1 ]; then
        check "$1: no file owned by root on the card" '[ -z "$(find "$CARD" -uid 0 | head -1)" ]'
    else
        echo "  skip $1: no file owned by root — $WHY"
    fi
}

echo "== 1. --dry-run on a card one commit behind, a tracked file's mtime touched"
stale; I0=$(idx); H0=$(head_of Pi-tools)
sleep 1                                     # a rewrite would now read a later second
cp -a "$CARD/opt/Pi-tools" "$T/copy"
B=$(sha256sum < "$T/copy/.git/index"); git -C "$T/copy" status --porcelain >/dev/null 2>&1
check "precondition: a plain git status rewrites this index (on a copy)" '[ "$(sha256sum < "$T/copy/.git/index")" != "$B" ]'
mark; run --dry-run
check "exit 0" '[ "$RC" = 0 ]'
check "names both fast-forwards" '[[ "$OUT" == *"Pi-tools: WOULD fast-forward main"*"$TARGET_PT"* ]] && [[ "$OUT" == *"HPlayer2: WOULD fast-forward main"*"$TARGET_HP"* ]]'
check "both .git/index byte-identical, same mtime" '[ "$(idx)" = "$I0" ]'
check "HEAD not moved" '[ "$(head_of Pi-tools)" = "$H0" ]'
untouched "dry run"
no_root_file "dry run"

echo "== 2. a real pass converges the card (the write path, unchanged)"
run
check "exit 0" '[ "$RC" = 0 ]'
check "both checkouts at the bench's commit" '[ "$(head_of Pi-tools)" = "$TARGET_PT" ] && [ "$(head_of HPlayer2)" = "$TARGET_HP" ]'
no_root_file "after the fast-forward"

echo "== 3. a card already at its target, a tracked file's mtime touched"
stale; I0=$(idx)
sleep 1
mark; run
check "exit 0" '[ "$RC" = 0 ]'
check "says already at, both" '[[ "$OUT" == *"Pi-tools: already at $TARGET_PT"* ]] && [[ "$OUT" == *"HPlayer2: already at $TARGET_HP"* ]]'
check "both .git/index byte-identical, same mtime" '[ "$(idx)" = "$I0" ]'
untouched "already at"
no_root_file "already at"
run --dry-run
check "and a dry run there: index still as it was" '[ "$RC" = 0 ] && [ "$(idx)" = "$I0" ]'

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
