#!/usr/bin/env bash
# netdefaults-desk — desk proof of the RastaOS-7.5 network defaults (pi-tools#t-055)
# that live outside setnet (setnet's own rule: bench/setnet-desk.sh). Runs the
# real installer and webconf code against temp dirs: no NM, no root, no card.
#
#   G  installer: hotspot off by default; `hotspot = yes` still generates it;
#      no generated profile carries ipv6 method=disabled (void on NM < 1.20)
#   H  the shipped profiles: no PSK value, sync STA roles never give up DHCP
#   I  webconf SYNC switch: templates from the card's wifi/_disabled/ else the
#      checkout; a switch that cannot find its templates touches nothing, so
#      /boot/wifi never ends up without an eth0 profile
#
# Proves the RULES, not the boot — the boot is the bench card.
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
red=0

echo "── installer + shipped profiles"
python3 -I - "$here" <<'PY' || red=1
import configparser, glob, os, sys, tempfile
root = sys.argv[1]; sys.path.insert(0, root)
from setup import config, installer, utils
installer.ui.success = installer.ui.warn = lambda *a, **k: None
ok = fail = 0
def check(name, cond):
    global ok, fail
    print(('PASS ' if cond else 'FAIL ') + name); ok += bool(cond); fail += (not cond)
def run(pitools_txt):
    boot = tempfile.mkdtemp(); utils.find_boot_dir = lambda: boot
    cfg_file = os.path.join(boot, 'pitools.txt'); open(cfg_file, 'w').write(pitools_txt)
    installer.setup_wifi_from_config(config.load(cfg_file), {'is_x86': False})
    w = os.path.join(boot, 'wifi')
    return {f: open(os.path.join(w, f)).read() for f in os.listdir(w)}
# G. defaults, then an explicit yes
check('G default hotspot = no', config.load(None).get('network', 'hotspot') == 'no')
check('G default writes no AP profile', run('') == {})
made = run('[system]\nhostname = rasta-07\n[network]\nhotspot = yes\nhotspot_password = 12345678\nwifi_1 = Gallery=abcdefgh\n')
check('G hotspot = yes generates wint-hotspot', 'wint-hotspot.nmconnection' in made)
check('G ... with its SSID and password', 'ssid=rasta-07\n' in made.get('wint-hotspot.nmconnection', '')
      and 'psk=12345678\n' in made.get('wint-hotspot.nmconnection', ''))
check('G client profile generated', 'Gallery.nmconnection' in made)
check('G no generated ipv6 method=disabled', made and all('method=disabled' not in t for t in made.values()))
# H. the shipped tree
prof = glob.glob(os.path.join(root, 'network-tools', 'profiles', '**', '*.nmconnection'), recursive=True)
def ini(p):
    c = configparser.ConfigParser(interpolation=None); c.read(p); return c
check('H profiles found', len(prof) >= 5)
check('H no shipped profile carries a psk', not [p for p in prof if ini(p).get('wifi-security', 'psk', fallback='')])
check('H no shipped ipv6 method=disabled', not [p for p in prof if ini(p).get('ipv6', 'method', fallback='') == 'disabled'])
for role in ('eth0-dhcp', '_disabled/eth0-sync-STA', '_disabled/wlan0-sync-STA'):
    p = os.path.join(root, 'network-tools', 'profiles', role + '.nmconnection')
    check(f'H {role} autoconnect-retries=0', ini(p).get('connection', 'autoconnect-retries', fallback='') == '0')
print(f'{ok} passed, {fail} failed'); sys.exit(1 if fail else 0)
PY

echo
echo "── webconf SYNC switch"
node - "$here" <<'JS' || red=1
const fs = require('fs'), os = require('os'), path = require('path');
const root = process.argv[2];
let ok = 0, fail = 0;
function check(name, cond) { console.log((cond ? 'PASS ' : 'FAIL ') + name); cond ? ok++ : fail++; }
// A throwaway checkout: the real 03-sync.js, a utils.js whose bootPath points at
// a temp boot partition, and the profiles folder (all of it, or `keep` only).
function card(bootWifi, keep) {
    const t = fs.mkdtempSync(path.join(os.tmpdir(), 'ndesk-'));
    fs.mkdirSync(path.join(t, 'webconf', 'settings'), { recursive: true });
    fs.copyFileSync(path.join(root, 'webconf', 'settings', '03-sync.js'), path.join(t, 'webconf', 'settings', '03-sync.js'));
    fs.writeFileSync(path.join(t, 'webconf', 'utils.js'),
        `const real = require(${JSON.stringify(path.join(root, 'webconf', 'utils.js'))});\n` +
        `module.exports = Object.assign({}, real, { bootPath: (...p) => require('path').join(${JSON.stringify(path.join(t, 'boot'))}, ...p) });\n`);
    const src = path.join(root, 'network-tools', 'profiles'), dst = path.join(t, 'network-tools', 'profiles');
    fs.cpSync(src, dst, { recursive: true,
        filter: (s) => !keep || fs.statSync(s).isDirectory() || keep.includes(path.relative(src, s)) });
    const w = path.join(t, 'boot', 'wifi');
    fs.mkdirSync(w, { recursive: true });
    for (const [n, c] of Object.entries(bootWifi)) {
        fs.mkdirSync(path.dirname(path.join(w, n)), { recursive: true });
        fs.writeFileSync(path.join(w, n), c);
    }
    return { s: require(path.join(t, 'webconf', 'settings', '03-sync.js')), w };
}
function ls(w) { return fs.readdirSync(w).filter(f => f.endsWith('.nmconnection')).sort().join(' '); }
function sw(c, iface, mode) {
    if (iface !== undefined) c.s.elements.synciface.apply(String(iface));
    c.s.elements.syncmode.apply(String(mode));
}
const E = '.nmconnection';
const quiet = console.error; console.error = () => {};
// I1. an installer-made card (no wifi/_disabled/) becomes an eth0 sync slave
let c = card({ ['eth0-dhcp' + E]: 'old' });
sw(c, 0, 1);
check('I1 installer card -> eth0 slave', ls(c.w) === 'eth0-sync-STA' + E);
// I2. ... and back to plain DHCP: the checkout's eth0-dhcp, not nothing
sw(c, 0, 0);
check('I2 back to eth0-dhcp', ls(c.w) === 'eth0-dhcp' + E
      && fs.readFileSync(path.join(c.w, 'eth0-dhcp' + E), 'utf8').includes('autoconnect-retries=0'));
// I3. wlan0 master keeps eth0 as the way in
c = card({ ['eth0-dhcp' + E]: 'old' });
sw(c, 1, 2);
check('I3 wlan0 master + eth0-dhcp', ls(c.w) === `eth0-dhcp${E} wlan0-sync-AP${E}`);
// I4. the card's own _disabled/ copy wins over the checkout's
c = card({ ['eth0-dhcp' + E]: 'old', ['_disabled/eth0-sync-AP' + E]: 'mine' });
sw(c, 0, 2);
check('I4 card template wins', fs.readFileSync(path.join(c.w, 'eth0-sync-AP' + E), 'utf8') === 'mine');
// I5. no SYNC interface given: nothing touched (it used to rm every eth0/wlan0 profile)
c = card({ ['eth0-dhcp' + E]: 'old' });
sw(c, undefined, 1);
check('I5 no interface -> untouched', ls(c.w) === 'eth0-dhcp' + E);
// I6. a template found nowhere: nothing touched (it used to leave /boot/wifi with no eth0 profile)
c = card({ ['eth0-dhcp' + E]: 'old' }, ['eth0-dhcp' + E]);
sw(c, 0, 1);
check('I6 missing template -> untouched', ls(c.w) === 'eth0-dhcp' + E
      && fs.readFileSync(path.join(c.w, 'eth0-dhcp' + E), 'utf8') === 'old');
console.error = quiet;
console.log(`${ok} passed, ${fail} failed`); process.exit(fail ? 1 : 0);
JS

echo
[ "$red" -eq 0 ] && echo "netdefaults-desk: green" || echo "netdefaults-desk: RED"
exit "$red"
