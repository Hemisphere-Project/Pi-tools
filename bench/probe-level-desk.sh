#!/usr/bin/env bash
# probe-level-desk — desk test of how probe-level and module-level reach a box
# and find a ledger (pi-tools#t-070).
#
#   bash bench/probe-level-desk.sh       # exit 0 green, 1 red, 2 could not run
#
# No player, no root. A stub `ssh` first on PATH records its argv and runs the
# program it is sent locally, as the box would. Both tools must pass
# fleet-lib.sh's host-key options (every player answers on 10.0.0.1 with its own
# key) and never `accept-new`. probe-level, run from a folder holding a planted
# `patch-ledger`, must not read it: the planted detect command touches a file.
#
# Not proven here: a real player, a real ssh, the jump.
#
# PROBE_LEVEL=<path> / MODULE_LEVEL=<path> run other copies (a mutation test);
# a copy is run from bench/, where it finds setup/module-manifest beside it.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 2
REPO=$(pwd)
PL=$(readlink -f "${PROBE_LEVEL:-bench/probe-level}")
ML=$(readlink -f "${MODULE_LEVEL:-bench/module-level}")
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; [ -n "${OUT:-}" ] && tail -6 <<<"$OUT" | sed "s/^/       > /"; }
OUT=""
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# the module-level copy must sit beside setup/module-manifest: a mutated copy
# goes into bench/ under a scratch name, removed on exit
if [ "$ML" != "$REPO/bench/module-level" ]; then
    cp "$ML" "$REPO/bench/.module-level-desk.$$"; ML="$REPO/bench/.module-level-desk.$$"
    trap 'rm -rf "$T" "$ML"' EXIT
fi

mkdir -p "$T/bin" "$T/home/.config/pitools" "$T/dl"
cat > "$T/bin/ssh" <<EOF
#!/bin/sh
printf '%s\n' "\$@" > "$T/ssh.argv"
exec sh -s
EOF
chmod +x "$T/bin/ssh"
printf 'P1 | there   | 7.4 | - | true\nP2 | missing | 7.4 | - | false\n' > "$T/ledger"
printf 'X1 | planted | 7.4 | - | touch %s/PLANTED_READ\n' "$T" > "$T/dl/patch-ledger"
argv_has() { grep -qxF -- "$1" "$T/ssh.argv"; }

echo "== 1. probe-level over ssh — fleet-lib.sh's host-key options"
rm -f "$T/ssh.argv"
OUT=$(PATH="$T/bin:$PATH" bash "$PL" -t root@10.0.0.1 -l "$T/ledger" 2>&1); RC=$?
check "the stub ssh was called" '[ -s "$T/ssh.argv" ]'
check "StrictHostKeyChecking=no" 'argv_has StrictHostKeyChecking=no'
check "UserKnownHostsFile=/dev/null" 'argv_has UserKnownHostsFile=/dev/null'
check "never accept-new" '! grep -q accept-new "$T/ssh.argv"'
check "the program ran: P2 missing, exit 1" '[ "$RC" = 1 ] && [[ "$OUT" == *"missing: P2"* ]]'

echo "== 2. module-level over ssh — the same options"
rm -f "$T/ssh.argv"
OUT=$(PATH="$T/bin:$PATH" PITOOLS_MODULE_MANIFEST="$T/none" bash "$ML" -t root@10.0.0.1 2>&1); RC=$?
check "the stub ssh was called" '[ -s "$T/ssh.argv" ]'
check "StrictHostKeyChecking=no" 'argv_has StrictHostKeyChecking=no'
check "UserKnownHostsFile=/dev/null" 'argv_has UserKnownHostsFile=/dev/null'
check "never accept-new" '! grep -q accept-new "$T/ssh.argv"'

echo "== 3. probe-level from a folder holding a planted patch-ledger"
printf 'H1 | home | 7.4 | - | true\n' > "$T/home/.config/pitools/patch-ledger"
OUT=$(cd "$T/dl" && HOME="$T/home" bash "$PL" --here 2>&1); RC=$?
check "reads ~/.config/pitools/patch-ledger instead" '[[ "$OUT" == *"ledger : $T/home/.config/pitools/patch-ledger"* ]] && [ "$RC" = 0 ]'
check "the planted detect command never ran" '[ ! -e "$T/PLANTED_READ" ]'
rm -f "$T/home/.config/pitools/patch-ledger"
OUT=$(cd "$T/dl" && HOME="$T/home" bash "$PL" --here 2>&1); RC=$?
check "no other ledger: refuses (exit 2), the planted one still unread" '[ "$RC" = 2 ] && [[ "$OUT" == *"no ledger found"* ]] && [ ! -e "$T/PLANTED_READ" ]'
OUT=$(cd "$T/dl" && HOME="$T/home" bash "$PL" --here -l ./patch-ledger 2>&1); RC=$?
check "-l ./patch-ledger still reads it when asked by name" '[[ "$OUT" == *"ledger : ./patch-ledger"* ]] && [ -e "$T/PLANTED_READ" ]'

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
