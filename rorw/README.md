# rorw — read-only root filesystem

Makes the root (and boot) filesystem **read-only**, with a writable `/data`
partition for everything that must persist. This protects the SD/eMMC from
corruption on the hard power-cuts these unattended installations get.

## Layout (written to `/etc/fstab` at install)

| Mount | Mode | Notes |
|-------|------|-------|
| `/` (root) | **ro** | remounted rw only when needed (see below) |
| boot (`/boot/firmware`, `/boot/efi` or `/boot`) | **ro** | FAT, `umask=177` |
| `/data` (3rd partition) | **rw** | `nofail` — a missing/corrupt `/data` boots degraded, never to an emergency shell |
| `/tmp`, `/var/{log,lock,spool,tmp}` | tmpfs | volatile |
| `/var/lib/{NetworkManager,dnsmasq}`, `/root/.cache`, snapd | bind from `/data/var/*` | persistent state, `nofail` |

**Prerequisite:** the 3-partition layout must exist *before* install — rorw does
**not** repartition. `1=boot(vfat) 2=root(ext4) 3=data(ext4)` on `mmcblk0` (Pi),
`sda` or `nvme0n1` (x86).

## Switching read-write (reference-counted)

`rw` and `ro` are **reference-counted** (a flock'd counter in `/run`), so
concurrent users — a service, the logout hook, `setnet`, an admin shell — can't
remount read-only under each other's writes.

```bash
rw          # remount read-write (first caller actually remounts; others just bump the count)
# ...edit files...
ro          # drop your hold; remounts read-only only when the LAST holder releases
ro -f       # FORCE: reset the count to 0 and lock now (recover a leaked count)
```

The count lives on tmpfs, so it resets to 0 (= read-only) at every boot. In a
script, prefer the wrapper:

```bash
source /usr/local/lib/pitools/with_rw.sh
with_rw "sed -i 's/foo/bar/' /etc/thing && sync"   # rw ... run ... ro, safely
```

## Recovery

- **Stuck read-only / need to edit by hand:** `rw`, edit, `ro`. If `rw` won't
  take (something holds a write lock), `fuser -vm /` shows who.
- **Emergency (rorw tooling gone / `/data` broken):** remount by hand —
  `mount -o remount,rw /` — fix, then `mount -o remount,ro /` (or just reboot;
  root comes back read-only from fstab).
- **Time:** the clock is a `fake-clock` floor persisted to `/data`, nudged
  forward by `datesync` (HTTP) — no RTC needed.

Note: `/data` is the only writable partition and IS fsck-checked (`passno 2`);
nothing else survives a reboot except tmpfs + the `/data` binds.
