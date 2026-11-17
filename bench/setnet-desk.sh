#!/usr/bin/env bash
# setnet-desk — desk proof of setnet's authoritative store (pi-tools#t-055).
# Runs the real `network-tools/setnet` prune_store() against temp dirs: no NM,
# no root, no card. Proves the RULE, not the boot — the boot is the bench card.
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
python3 -I - "$here/network-tools/setnet" <<'PY'
import importlib.machinery, importlib.util, os, sys, tempfile
loader = importlib.machinery.SourceFileLoader('setnet', sys.argv[1])
spec = importlib.util.spec_from_loader('setnet', loader)
m = importlib.util.module_from_spec(spec); loader.exec_module(m)
m.rw_on = lambda: None; m.rw_off = lambda: None
m.syslog.syslog = lambda *a: None
ok = fail = 0
def check(name, cond):
    global ok, fail
    print(('PASS ' if cond else 'FAIL ') + name); ok += cond; fail += (not cond)
def tree(**files):
    d = tempfile.mkdtemp()
    for n, c in files.items():
        if c is None: os.makedirs(os.path.join(d, n))
        else: open(os.path.join(d, n), 'w').write(c)
    return d
E = '.nmconnection'
# A. the 7.4 bench store: a stale profile, a field nmcli profile, the _anna74-removed dir
boot = tree(**{'eth0-dhcp'+E: 'a', 'wint-hotspot'+E: 'b'})
store = tree(**{'eth0-dhcp'+E: 'a', 'wint-hotspot'+E: 'b', 'wlan0-sync-AP'+E: 'c',
                'Wired connection 1': 'd', '_anna74-removed': None})
os.makedirs(os.path.join(store, '_anna74-removed', 'x')); pr = tempfile.mkdtemp() + '/pruned'
check('A moved something', m.prune_store(boot, store, E, pr))
check('A store == boot', sorted(os.listdir(store)) == sorted(os.listdir(boot)))
check('A pruned kept, not deleted', sorted(os.listdir(pr)) == ['Wired connection 1', '_anna74-removed', 'wlan0-sync-AP'+E])
check('A dir moved whole', os.path.isdir(os.path.join(pr, '_anna74-removed', 'x')))
# B. second run: nothing to do
check('B idempotent', m.prune_store(boot, store, E, pr) is False)
# C. a re-pruned name replaces the older archived copy
open(os.path.join(store, 'wlan0-sync-AP'+E), 'w').write('new')
m.prune_store(boot, store, E, pr)
check('C replaces archive', open(os.path.join(pr, 'wlan0-sync-AP'+E)).read() == 'new')
# D. guards: empty boot folder, missing boot folder, boot folder of subdirs only
for label, b in (('D empty /boot/wifi', tree()), ('D missing /boot/wifi', '/nonexistent/wifi'),
                 ('D only _disabled/', tree(_disabled=None))):
    s = tree(**{'eth0-dhcp'+E: 'a'})
    check(label + ' prunes nothing', m.prune_store(b, s, E, pr) is False and os.listdir(s) == ['eth0-dhcp'+E])
# E. a same-name DIRECTORY in the store is not a profile: pruned
boot = tree(**{'eth0-dhcp'+E: 'a'}); store = tree(**{'eth0-dhcp'+E: None})
m.prune_store(boot, store, E, pr)
check('E dir with a profile name pruned', os.listdir(store) == [])
# F. the shipped eth0-dhcp profile: retries=0, IPv6 link-local, no `disabled` (void on NM < 1.20)
p = m.parse_profile(os.path.join(os.path.dirname(sys.argv[1]), 'profiles', 'eth0-dhcp'+E))
check('F eth0-dhcp autoconnect-retries=0', p.get('connection.autoconnect-retries') == '0')
check('F eth0-dhcp ipv6 link-local', p.get('ipv6.method') == 'link-local')
# G. DHCP never gives up: one timeout on the profile, NM's timer AND dhclient's (NM 1.14
#    hands its dhcp-timeout to dhclient), long enough never to fire, and not wrapping
#    dhclient's 32-bit time_t first_sending + timeout (2147483647 did: SIGFPE, bench-02)
import inspect
t = p.get('ipv4.dhcp-timeout') or ''
check('G eth0-dhcp ipv4.dhcp-timeout set', t.isdigit())
T = int(t) if t.isdigit() else 0
check('G timeout >= 1 year', T >= 365 * 86400)
check('G timeout cannot wrap time_t before 2034', 2019686400 + T < 2**31)  # 2034-01-01
check('G one source: setnet writes no dhclient config', 'dhclient-eth0' not in inspect.getsource(m))
print(f'\n{ok} passed, {fail} failed'); sys.exit(1 if fail else 0)
PY
