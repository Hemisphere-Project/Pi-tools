# flightbox — raw ring-buffer partition for the post-mortem trail

Born 2026-09-22 after a fourth card corruption on the fleet (Thomas — "logging is a bonus that
must never compromise the running or the rebooting of the system"; a clean poweroff is impossible
by design, the venues cut the mains). Design: `notes/2026-09-22-flightbox-ring-buffer-log-partition.md`
in the hub. The successor to `blackbox`'s journald-in-RAM + 10-min export (that stopped the
journal itself from killing cards); this goes further and takes the filesystem out of the logging
path entirely for the export chunk.

## The partition

A fourth partition, ~512 MB, **no filesystem** — nothing to mount, nothing to fsck, no fstab line,
so a broken or absent p4 cannot touch the boot. `flightbox` never creates it: the golden image
lays it out at the reflash. Cards already in service are **not repartitioned** (Thomas 2026-09-27:
a live `/data` shrink is the one operation where a power cut costs the films — pi-tools#t-049 is
dropped for the fleet); they use file mode, below. p4 wins wherever it exists.

## File mode — live cards (pi-tools#t-051)

Where there is no p4, the ring lives in **`/data/.flightbox`**, a file reserved once:

```
flightbox reserve [MB]      # default 512 — supervised, power ON, once per card
```

- **Reserved once.** 512 MB plus one allocation unit, zeros written in one sequential pass
  (`dd oflag=direct conv=fsync`) over blocks `fallocate`d in one request — never `fallocate`
  alone: unwritten extents would turn every first write into an extent-tree update. Written to
  `.flightbox.tmp` and renamed into place only once the zeros are on the card, so a cut
  mid-reserve leaves a `.tmp` the next `reserve` deletes. Refuses when `/data` is not a mounted
  filesystem, when it would leave under 2 GB free, or when this box already has p4. Idempotent:
  an existing usable file is reported, never rewritten; `rm /data/.flightbox` is the whole undo.
- **Every later write is an in-place overwrite** of blocks already allocated and written — no
  allocation, no size change, no directory update. What remains is the inode's mtime/ctime, and
  `flightbox-lazytime.service` remounts `/data` with `lazytime` (only on a card that carries the
  file) so those stay in RAM: in operation, logging writes no filesystem metadata at all.
- **Whole allocation units only.** A torn rewrite of a unit spoils what is in that unit, so the
  writer uses only the card's units the file owns *outright*: `flightbox` reads the file's extents
  (the FIEMAP ioctl `filefrag` is built on), keeps the written ones, joins the physically
  contiguous runs, and trims each run inwards to whole units on the card's own grid (the unit is
  the card's `preferred_erase_size`, else 4 MB; `FLIGHTBOX_UNIT` overrides). A record never
  straddles two runs. The one unit of slack covers a single run; ext4 usually splits 512 MB at a
  backup-superblock group or two, so the window can land a few units under 512 MB —
  `reserve` and `status` print what it got. Caveat kept in the contract: page-mapped controllers
  garbage-collect across units, so confinement raises the odds, it cannot guarantee them.
- **Nothing is written unless diagnostics are armed.** flightbox writes only when a caller asks;
  its callers (journal-export's timer, blackbox's anomaly dump) run only under `diag armed`.

Exposure is the same card and the same controller as p4 — an FTL damaging neighbours on a cut does
not respect partition boundaries either. What file mode gives up is independence from ext4: it
leans on `data-repair` for the filesystem it lives in, and on `.flightbox` being ignored by
everything else (HPlayer2 lists `/data/media` only). A file that is missing, under 64 MB, or whose
window cannot be placed reads as **absent**, exactly like a missing p4.

## Record format (ratified, byte for byte)

```
[magic 4B][seq 8B][timestamp 8B][len 4B][crc32 4B][payload]     — all big-endian
```

Appended sequentially with `dd oflag=direct`, zero-padded up to the next 512-byte boundary (the
O_DIRECT alignment SD/mmc/USB logical blocks need — it also means a scanner that fails to parse a
record only ever has to resync at 512 B steps, never byte by byte). When the tail reaches the end
of the partition it wraps to offset 0 and starts overwriting the oldest records — that's the ring.

`seq` is a global counter that never resets, wrap or no wrap, so **the record with the highest
`seq` anywhere on the partition is always the most recently written one** — both the boot-time
tail-scan and `dump` lean on exactly that property instead of reasoning about ring geometry.

The ratified format has no type field, so `write --tag TAG` prepends one text line to the
*payload* (`#flightbox:TAG\n`) — layered on top of the wire format, not a change to it. `dump`
strips it back off.

## Boot-time tail-scan

`flightbox-scan.service` (oneshot, boot) walks the whole partition once, validates every record by
magic+crc, and writes the next `(offset, seq)` to `/run/flightbox.state`. Nothing survives a
reboot on disk except the ring itself — there is no separate index to get out of sync with it, so
a mains cut can't strand `flightbox`'s own bookkeeping the way it could strand a real filesystem.
`write` self-heals by scanning on the spot if called before the boot unit has (or after a manual
install without a reboot yet).

## Failure handling — self-disable, never stall

Every `write` is wrapped in `timeout` (`FLIGHTBOX_DD_TIMEOUT`, default 10 s) so a wedged card
cannot hang the caller. Exit codes a caller branches on:

- **0** — written.
- **1** — a genuine I/O error (`dd` failed or timed out) — `/run/flightbox.disabled` is written and
  every later call this boot short-circuits without touching the device again. Clears itself at
  the next reboot (tmpfs), same as the state file — the next boot's scan starts clean.
- **2** — payload rejected (bigger than `FLIGHTBOX_MAX_PAYLOAD`, default 8 MB) — not an I/O fault,
  no marker, just this one write is skipped.
- **3** — ring absent: no p4 and no usable `/data/.flightbox` (never reserved, under 64 MB, or a
  window that could not be placed — e.g. a file left with unwritten extents).

**`journal-export` and `blackbox` fall back to their own pre-flightbox `/data` write on any
non-zero exit** — flightbox never becomes a new single point of failure for the trail; it's
strictly additive until it works, then a straight replacement for where those two write.

## Usage

```
flightbox status              # mode (p4/file/none), device, size, window, scan state, disabled marker
flightbox scan                # boot-time tail-scan (also run manually after install --now)
flightbox write --tag TAG F   # append F's bytes (F=- for stdin) as one record
flightbox dump [N]            # print the last N records (default: all), oldest first
flightbox reserve [MB]        # file mode: create /data/.flightbox (default 512 MB) — supervised, once
```

`FLIGHTBOX_DEVICE` overrides device resolution (default: the root disk's 4th partition, same
disk-detection as `extendfs`) — a loop device, or even a plain file, for bench testing without a
partitioned card; `dd oflag=direct` works against a regular file on ext4 same as a block device.
`FLIGHTBOX_RUN_DIR` overrides `/run` for the same reason. An override is used whole; to exercise
file mode itself (window and all), point `FLIGHTBOX_FILE` at a file on a mounted ext4 instead.
`FLIGHTBOX_MAX_PAYLOAD` / `FLIGHTBOX_DD_TIMEOUT` tune the caps above; `FLIGHTBOX_UNIT` forces the
allocation unit.

## What this does not change

A card whose controller stops answering stalls every reader on it, `mpv` included — `flightbox`
buys a trail, not a cure; card quality and replacement of known-bad units remain the only answer
to that (same limit `blackbox` already documents).

## Scope

This module (pi-tools#t-048) is the writer/reader + boot-time scan + repointing
`journal-export`/`blackbox`; file mode, `reserve` and the lazytime remount are pi-tools#t-051
(the live repartition it replaces, pi-tools#t-049, is dropped). Bench validation (power cut
mid-record in file mode and p4 mode, `dump` reconstruction past a torn record, boot with the file
missing / truncated / corrupt) is pi-tools#t-050. Fleet rollout order to `biennale-lyon-2026` is that
engagement's own task once this ships — pi-tools is a component with no client.
