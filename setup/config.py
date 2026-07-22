"""Configuration parser for Pi-tools."""

import configparser
import os


DEFAULTS = {
    'system': {
        'hostname': '',
        'timezone': '',
        'password': 'rootpi',
    },
    'network': {
        'wifi_country': 'FR',
        'hotspot': 'yes',
        'hotspot_password': 'raspberry',
    },
    'modules': {
        'system': 'yes',
        'network': 'yes',
        'web': 'ask',
        'audiohub': 'ask',
        'xrun': 'no',
        'synczinc': 'no',
        'bluetooth': 'no',
        'rtpmidi': 'no',
        'tailscale': 'ask',
    },
    'display': {
        'resolution': '1920x1080@30',
        'rotation': '0',
    },
}


def load(path=None):
    """Load config from file, merged with defaults."""
    cfg = configparser.ConfigParser()

    # Set defaults
    for section, values in DEFAULTS.items():
        if not cfg.has_section(section):
            cfg.add_section(section)
        for key, val in values.items():
            cfg.set(section, key, val)

    # Load file if exists
    if path and os.path.isfile(path):
        cfg.read(path)
        _apply_legacy_aliases(cfg, path)

    return cfg


# Legacy module-key aliases: {canonical: [old names]}. An old key present in the
# config file is honored for the new group, unless the new key is set explicitly.
_MODULE_ALIASES = {'audiohub': ['audioselect']}


def _apply_legacy_aliases(cfg, path):
    """Honor renamed module keys in older pitools.txt files."""
    raw = configparser.ConfigParser()
    raw.read(path)
    if not raw.has_section('modules'):
        return
    for canonical, olds in _MODULE_ALIASES.items():
        if raw.has_option('modules', canonical):
            continue  # explicit new key wins over any alias
        for old in olds:
            if raw.has_option('modules', old):
                cfg.set('modules', canonical, raw.get('modules', old))
                break


def get_wifi_networks(cfg):
    """Extract WiFi networks from config. Format: wifi_N=SSID=password"""
    networks = []
    if not cfg.has_section('network'):
        return networks
    for key, value in cfg.items('network'):
        if key.startswith('wifi_'):
            parts = value.split('=', 1)
            if len(parts) == 2:
                networks.append({'ssid': parts[0], 'password': parts[1]})
    return networks
