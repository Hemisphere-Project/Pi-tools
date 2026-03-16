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
        'hotspot': 'yes',
    },
    'modules': {
        'system': 'yes',
        'network': 'yes',
        'web': 'ask',
        'audioselect': 'ask',
        'xrun': 'no',
        'synczinc': 'no',
        'bluetooth': 'no',
        'rtpmidi': 'no',
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

    return cfg


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
