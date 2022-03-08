#!/usr/bin/env python

from pydbus import SystemBus
from shutil import copyfile
import os
import filecmp

bus = SystemBus()
systemd = bus.get(".systemd1")

# for unit in systemd.ListUnits():
#     print(unit)

engageRW = False

# Sync from /data/sync
SRCFILE = "/data/sync/starter.txt"
DESTFILE = "/boot/starter.txt"
if os.path.exists(SRCFILE) and not filecmp.cmp(SRCFILE, DESTFILE, shallow=False):
    if not engageRW:
        engageRW = True
        os.system('rw')
    copyfile(SRCFILE, DESTFILE)
    print("[starter] Syncing from "+SRCFILE)

# Sync from USB
SRCFILE = "/data/usb/starter.txt"
DESTFILE = "/boot/starter.txt"
if os.path.exists(SRCFILE) and not filecmp.cmp(SRCFILE, DESTFILE, shallow=False):
    if not engageRW:
        engageRW = True
        os.system('rw')
    copyfile(SRCFILE, DESTFILE)
    print("[starter] Syncing from "+SRCFILE)

# Dirty
if engageRW:
    # RO
    os.system('ro')
    engageRW = False



services = []
with open("/boot/starter.txt") as f:
    for line in f.readlines():
        elements = line.strip().split('#')
        if len(elements) > 0: 
            serv = elements[0].strip()
            if len(serv) > 0:
                services.append(serv.replace('@ ', '@'))

if len(services) == 0:
    print("No service found in /boot/starter.txt")

for s in services:
    s = s.rstrip()
    print ("Starting service "+s)
    systemd.StartUnit(s+".service", "fail")

