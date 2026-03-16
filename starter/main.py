#!/usr/bin/env python3
"""Starter — read starter.txt and start listed systemd services."""

import os
import subprocess
import time

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
    svc = f"{name}.service"
    print(f"Starting {svc}...")
    t0 = time.monotonic()
    result = subprocess.run(
        ['systemctl', 'start', svc],
        capture_output=True, text=True
    )
    elapsed = time.monotonic() - t0
    if result.returncode != 0:
        print(f"  FAILED ({result.stderr.strip()})")
    else:
        print(f"  OK ({elapsed:.1f}s)")


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
