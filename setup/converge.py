#!/usr/bin/env python3
"""converge — re-apply THIS box's installed Pi-tools modules after its checkout moved.

    python3 setup/converge.py [--plan] [--platform pi|x86] [--manifest PATH]

Called by setup/rastaos-update once it has checked out a tag (pi-tools#t-057). It never installs
a module the box did not have — adding one is setup.sh's job — and never one this platform cannot
run: module.ini `platforms` decides, so an N100 kmini on NastaOS skips the RPi-only modules.

Which modules the box has:
  * every module named in the module receipts (/etc/pi-tools-modules.txt, pi-tools#t-047), and
  * every standard module with at least one of its declared bins/units present on the box.
A script module (install.sh) that left no receipt is invisible to both, so it is reported
`unrecorded` — never guessed, never run.

What each one gets:
  * script module, rerun-safe -> its install.sh runs again: it copies or configures, and no
                                 symlink carries the new tag there. Only when its module.ini says
                                 `[install] rerun = yes` — a claim that running it twice leaves
                                 the box as running it once did.
  * script module, not marked -> `held`, NOT run. rorw/install.sh is why: its cmdline.txt sed
                                 and its fstab/.bashrc appends stack on every pass (13/11), and an
                                 updater that re-runs it on each tag would break the boot line.
  * standard, fully linked    -> nothing: its bins and units are symlinks into the checkout, so
                                 the new code is already live; one daemon-reload covers units
  * standard, partly linked   -> the standard install: the tag declares a file the box lacks

--plan prints one line per module and changes nothing. Exit 0 applied (or nothing to do),
1 a module failed, 2 usage. PITOOLS_ROOT prefixes every box path it READS (tests, a card in a
reader); applying always targets the running box.
"""
import argparse
import configparser
import os
import sys

SETUP_DIR = os.path.dirname(os.path.abspath(__file__))
PITOOLS_DIR = os.path.dirname(SETUP_DIR)
sys.path.insert(0, PITOOLS_DIR)

ROOT = os.environ.get('PITOOLS_ROOT', '')


def box(path):
    return ROOT + path if ROOT else path


def modules():
    """Every module dir in the checkout: name -> parsed module.ini."""
    out = {}
    for name in sorted(os.listdir(PITOOLS_DIR)):
        ini_path = os.path.join(PITOOLS_DIR, name, 'module.ini')
        if os.path.isfile(ini_path):
            ini = configparser.ConfigParser()
            ini.read(ini_path)
            out[name] = ini
    return out


def recorded(manifest):
    """Module names in the receipts file; empty when the box has none (pre-#t-047)."""
    try:
        with open(manifest) as f:
            return {ln.split()[0] for ln in f if ln.strip() and not ln.startswith('#')}
    except OSError:
        return set()


def declared(ini):
    """The box paths a standard install lays down for this module."""
    paths = []
    if ini.has_option('files', 'bins'):
        paths += [f'/usr/local/bin/{b}' for b in ini.get('files', 'bins').split()]
    for key in ('services', 'timers'):
        if ini.has_option('files', key):
            paths += [f'/etc/systemd/system/{s}' for s in ini.get('files', key).split()]
    return paths


def on_platform(ini, platform):
    platforms = [p.strip() for p in ini.get('module', 'platforms', fallback='pi,x86').split(',')]
    return platform in platforms


def plan(platform, manifest):
    """[(module, action, why)] — action: script | held | install | linked | skip | unrecorded."""
    have = recorded(manifest)
    rows = []
    for name, ini in modules().items():
        script = ini.getboolean('install', 'script', fallback=False)
        paths = declared(ini)
        present = [p for p in paths if os.path.lexists(box(p))]
        if name not in have and not present:
            if script:
                rows.append((name, 'unrecorded', 'script module, no receipt — not run'))
            continue                                  # not on this box: setup.sh's job
        if not on_platform(ini, platform):
            rows.append((name, 'skip', f'not for {platform}'))
        elif script and ini.getboolean('install', 'rerun', fallback=False):
            rows.append((name, 'script', 'install.sh again'))
        elif script:
            rows.append((name, 'held', 'install.sh not marked rerun-safe — not run'))
        elif len(present) == len(paths) and paths:
            rows.append((name, 'linked', 'symlinks already carry the new code'))
        else:
            rows.append((name, 'install', f'{len(paths) - len(present)} declared file(s) missing'))
    return rows


def main():
    ap = argparse.ArgumentParser(description='Re-apply the installed modules after a checkout move.')
    ap.add_argument('--plan', action='store_true', help='print the plan, change nothing')
    ap.add_argument('--platform', choices=('pi', 'x86'), help='override detection')
    ap.add_argument('--manifest', default=os.environ.get('PITOOLS_MODULE_MANIFEST',
                                                         box('/etc/pi-tools-modules.txt')))
    a = ap.parse_args()

    platform = a.platform
    platinfo = None
    if not platform or not a.plan:
        from setup import detect
        platinfo = detect.detect()
        detected = 'pi' if platinfo['is_pi'] else 'x86' if platinfo['is_x86'] else None
        if a.platform and detected and a.platform != detected:
            print(f'converge: --platform {a.platform} but this box is {detected}', file=sys.stderr)
            return 2
        platform = platform or detected
        if not platform:
            print(f"converge: unknown platform ({platinfo['arch']}) — nothing applied", file=sys.stderr)
            return 2

    rows = plan(platform, a.manifest)
    for name, action, why in rows:
        print(f'{action:<10} {name:<18} {why}')
    if a.plan:
        return 0

    os.environ['DEBIAN_FRONTEND'] = 'noninteractive'
    from setup import installer, config, detect, utils
    cfg = config.load(detect.find_config(platinfo))
    failed = []
    for name, action, _ in rows:
        if action in ('script', 'install') and not installer.install_module(name, platinfo, cfg):
            failed.append(name)
    utils.daemon_reload()
    if failed:
        print(f"converge: failed: {' '.join(failed)}", file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
