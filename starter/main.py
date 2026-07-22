#!/usr/bin/env python3
"""Starter — read starter.txt and start listed systemd services."""

import os
import subprocess

CONFIG_PATHS = [
    '/boot/firmware/starter.txt',
    '/boot/starter.txt',
]


def find_config():
    for p in CONFIG_PATHS:
        if os.path.isfile(p):
            return p
    return None


def parse_services(config_path):
    services = []
    with open(config_path) as f:
        for line in f:
            # Lines starting with # are comments; uncommented lines are services
            line = line.strip().split('#')[0].strip()
            if line:
                services.append(line.replace('@ ', '@'))
    return services


def start_service(name):
    # Honor an explicit unit type (foo.timer / foo.target); default to .service.
    unit = name if '.' in name else f"{name}.service"
    print(f"Starting {unit}...")
    # --no-block: starter is a boot oneshot that multi-user.target waits on, so a
    # slow or long-running unit must not stall boot — and a listed unit that itself
    # orders After=multi-user.target would otherwise deadlock. Fire-and-forget;
    # systemd supervises each unit from there.
    result = subprocess.run(
        ['systemctl', 'start', '--no-block', unit],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"  FAILED ({result.stderr.strip()})")
    else:
        print(f"  queued")


def main():
    config = find_config()
    if not config:
        print("[starter] No starter.txt found")
        return

    print(f"[starter] Reading {config}")
    services = parse_services(config)

    if not services:
        print("[starter] No services to start")
        return

    for s in services:
        start_service(s)

    print(f"[starter] Done — {len(services)} service(s) processed")


if __name__ == '__main__':
    main()
