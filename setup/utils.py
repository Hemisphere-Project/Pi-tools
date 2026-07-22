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
    """Append entries to starter.txt if not already present."""
    path = starter_txt_path()
    existing = ''
    if os.path.isfile(path):
        with open(path) as f:
            existing = f.read()

    to_add = []
    for line in entries.strip().split('\n'):
        if line.strip() and line.strip() not in existing:
            to_add.append(line)

    if to_add:
        with open(path, 'a') as f:
            f.write('\n'.join(to_add) + '\n')


def is_module_installed(module_dir):
    """Check if a module is already installed by verifying its primary symlinks exist."""
    ini_path = os.path.join(module_dir, 'module.ini')
    if not os.path.isfile(ini_path):
        return False

    cfg = configparser.ConfigParser()
    cfg.read(ini_path)

    # Check bins
    if cfg.has_option('files', 'bins'):
        bins = cfg.get('files', 'bins').split()
        for b in bins:
            if not os.path.lexists(f'/usr/local/bin/{b}'):
                return False
        if bins:
            return True

    # Check services (for modules without bins)
    if cfg.has_option('files', 'services'):
        services = cfg.get('files', 'services').split()
        for s in services:
            if not os.path.lexists(f'/etc/systemd/system/{s}'):
                return False
        if services:
            return True

    return False
