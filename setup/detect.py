"""Platform detection for Pi-tools."""

import os
import platform


def detect():
    """Detect platform. Returns dict with platform info."""
    info = {
        'arch': platform.machine(),
        'is_pi': False,
        'is_x86': False,
        'pi_model': None,
        'boot_dir': '/boot',
    }

    # Detect Raspberry Pi
    model_file = '/proc/device-tree/model'
    if os.path.isfile(model_file):
        with open(model_file) as f:
            model = f.read().strip('\x00')
        if 'Raspberry Pi' in model:
            info['is_pi'] = True
            for ver in (5, 4, 3, 2):
                if f'Pi {ver}' in model:
                    info['pi_model'] = ver
                    break

    # x86/x86_64
    if info['arch'] in ('x86_64', 'i686', 'i386'):
        info['is_x86'] = True

    # Boot directory (modern Pi OS uses /boot/firmware)
    if os.path.isdir('/boot/firmware'):
        info['boot_dir'] = '/boot/firmware'

    return info


def find_config(platinfo):
    """Find pitools.txt config file. Boot partition first, then USB."""
    paths = [
        os.path.join(platinfo['boot_dir'], 'pitools.txt'),
        '/boot/pitools.txt',
        '/data/usb/pitools.txt',
    ]
    for p in paths:
        if os.path.isfile(p):
            return p
    return None
