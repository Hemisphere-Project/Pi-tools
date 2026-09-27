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

## The boot partition's dirty flag

A FAT volume carries a "dirty" flag: the kernel sets it on a read-write mount
and clears it on the way back down. When a card arrives with that flag already
set, every boot logs

```
FAT-fs (mmcblk0p1): Volume was not properly unmounted. Some data may be corrupt. Please run fsck.
```

**That warning does not mean something is still dirtying the card.** Measured on
a loop-mounted FAT32 image (2026-09-20):

| volume mounted | `remount,ro` | `remount,rw` | clean `umount` |
|---|---|---|---|
| **clean** | clears the flag ✓ | sets it | clears it ✓ |
| **dirty** | leaves it set | leaves it set | **leaves it set** |

So a clean card stays clean through any number of `rw`/`ro` cycles — but once a
card is dirty, *nothing in the mount path ever clears it again*, not even a
clean unmount. The warning latches and repeats forever with no writer at fault.

The only way out is `fsck` on the **unmounted** volume, so `ro` does exactly
that, once per boot (`/run/pitools-boot-sealed`), the first time it takes the
boot partition read-only: unmount → `fsck.fat -a` → mount back read-only. One
success is enough — the card then arrives clean and the ordinary `remount,ro`
keeps it that way.

It is best-effort by design. A busy boot partition, a non-vfat `/boot`, or a
missing `fsck.fat` each fall back to the plain `remount,ro` this script has
always done, and say so; the next boot tries again. `dosfstools` is declared in
`module.ini`, but note that an **installed** box only picks up this script via
`git pull` — if `fsck.fat` is absent there, install it by hand.
