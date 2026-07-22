"""Shared utilities for Pi-tools installer."""

import os
import subprocess
import configparser


PITOOLS_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run(cmd, check=True, capture=False, cwd=None):
    """Run a shell command."""
    kwargs = {'cwd': cwd}
    if isinstance(cmd, str):
        kwargs['shell'] = True
    if capture:
        kwargs['capture_output'] = True
        kwargs['text'] = True
    return subprocess.run(cmd, check=check, **kwargs)


def apt_install(*packages):
    """Install packages via apt, non-interactively. Skips unavailable packages."""
    pkgs = [p for p in packages if p]
    if not pkgs:
        return
    # apt-get (stable CLI) + keep existing config files on conflict, so a
    # dpkg config prompt never stalls an unattended install.
    run(['apt-get', 'install', '-y',
         '-o', 'Dpkg::Options::=--force-confold',
         '-o', 'Dpkg::Options::=--force-confdef'] + pkgs, check=False)


def link_bin(src, name=None):
    """Create symlink in /usr/local/bin/."""
    if name is None:
        name = os.path.basename(src)
    dest = f'/usr/local/bin/{name}'
    os.makedirs('/usr/local/bin', exist_ok=True)
    if os.path.lexists(dest):
        os.remove(dest)
    os.symlink(os.path.abspath(src), dest)


def install_service(src):
    """Symlink service/timer file to systemd."""
    name = os.path.basename(src)
    dest = f'/etc/systemd/system/{name}'
    if os.path.lexists(dest):
        os.remove(dest)
    os.symlink(os.path.abspath(src), dest)


def install_udev_rule(src):
    """Symlink udev rule to /etc/udev/rules.d/."""
    name = os.path.basename(src)
    dest = f'/etc/udev/rules.d/{name}'
    if os.path.lexists(dest):
        os.remove(dest)
    os.symlink(os.path.abspath(src), dest)


def daemon_reload():
    """Reload systemd daemon."""
    run('systemctl daemon-reload')


def udev_reload():
    """Reload udev rules."""
    run('udevadm control --reload-rules && udevadm trigger')


def enable_service(name):
    """Enable a systemd service."""
    run(['systemctl', 'enable', name], check=False)


def disable_service(name):
    """Disable a systemd service."""
    run(['systemctl', 'disable', name], check=False)


def mask_service(name):
    """Mask a systemd service."""
    run(['systemctl', 'mask', name], check=False)


def npm_install(path):
    """Run npm install in a directory."""
    run('npm install', cwd=path)


def find_boot_dir():
    """Find the boot partition directory."""
    if os.path.isdir('/boot/firmware'):
        return '/boot/firmware'
    return '/boot'


def starter_txt_path():
    """Return starter.txt path on boot partition."""
    return os.path.join(find_boot_dir(), 'starter.txt')


def append_starter(entries):
    """Append entries to starter.txt, de-duplicated by their service name.

    Compares each candidate to the existing lines with leading '#'/whitespace
    stripped, so an entry the user has UN-commented (e.g. `setnet`) is not
    re-appended in its commented form (`# setnet`) on the next install — the old
    substring check re-added it and left both lines.
    """
    path = starter_txt_path()
    existing_lines = []
    if os.path.isfile(path):
        with open(path) as f:
            existing_lines = f.read().splitlines()

    def norm(s):
        return s.lstrip('#').strip()

    seen = {norm(l) for l in existing_lines if norm(l)}

    to_add = []
    for line in entries.strip().split('\n'):
        n = norm(line)
        if n and n not in seen:
            to_add.append(line)
            seen.add(n)  # also de-dup within this same batch

    if to_add:
        with open(path, 'a') as f:
            f.write('\n'.join(to_add) + '\n')


def is_module_installed(module_dir):
    """True only if EVERY declared bin/service/timer symlink exists.

    Stricter than "the first declared symlink is present": adding a new service
    to a module.ini now makes the module read as not-fully-installed, so a
    re-run re-applies it (module installs are idempotent). Modules with no
    [files] entries (e.g. script-only) return False and are re-run each time.
    """
    ini_path = os.path.join(module_dir, 'module.ini')
    if not os.path.isfile(ini_path):
        return False

    cfg = configparser.ConfigParser()
    cfg.read(ini_path)

    checked_any = False

    if cfg.has_option('files', 'bins'):
        for b in cfg.get('files', 'bins').split():
            checked_any = True
            if not os.path.lexists(f'/usr/local/bin/{b}'):
                return False

    for key in ('services', 'timers'):
        if cfg.has_option('files', key):
            for s in cfg.get('files', key).split():
                checked_any = True
                if not os.path.lexists(f'/etc/systemd/system/{s}'):
                    return False

    return checked_any
