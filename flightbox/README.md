# flightbox — raw ring-buffer partition for the post-mortem trail

Born 2026-09-22 after a fourth card corruption on the fleet (Thomas — "logging is a bonus that
must never compromise the running or the rebooting of the system"; a clean poweroff is impossible
by design, the venues cut the mains). Design: `notes/2026-09-22-flightbox-ring-buffer-log-partition.md`
in the hub. The successor to `blackbox`'s journald-in-RAM + 10-min export (that stopped the
journal itself from killing cards); this goes further and takes the filesystem out of the logging
path entirely for the export chunk.

## The partition

A fourth partition, ~512 MB, **no filesystem** — nothing to mount, nothing to fsck, no fstab line,
so a broken or absent p4 cannot touch the boot. `flightbox` never creates it: the live-migration
one-shot unit (pi-tools#t-049) shrinks `/data` and creates p4 on already-deployed cards; a fresh
image partitions it directly. Until that has run and the box has rebooted once, `flightbox status`
reports the device absent and every write call fails closed (see below) — safe, expected, no
degradation of anything that already worked.

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
- **3** — partition absent (p4 doesn't exist yet, or fewer than 4 partitions on this disk at all).

**`journal-export` and `blackbox` fall back to their own pre-flightbox `/data` write on any
non-zero exit** — flightbox never becomes a new single point of failure for the trail; it's
strictly additive until it works, then a straight replacement for where those two write.

## Usage

```
flightbox status              # device, size, scan state, disabled marker
flightbox scan                # boot-time tail-scan (also run manually after install --now)
flightbox write --tag TAG F   # append F's bytes (F=- for stdin) as one record
flightbox dump [N]            # print the last N records (default: all), oldest first
```

`FLIGHTBOX_DEVICE` overrides device resolution (default: the root disk's 4th partition, same
disk-detection as `extendfs`) — a loop device, or even a plain file, for bench testing without a
partitioned card; `dd oflag=direct` works against a regular file on ext4 same as a block device.
`FLIGHTBOX_RUN_DIR` overrides `/run` for the same reason. `FLIGHTBOX_MAX_PAYLOAD` /
`FLIGHTBOX_DD_TIMEOUT` tune the caps above.

## What this does not change

A card whose controller stops answering stalls every reader on it, `mpv` included — `flightbox`
buys a trail, not a cure; card quality and replacement of known-bad units remain the only answer
to that (same limit `blackbox` already documents).

## Scope

This module (pi-tools#t-048) is the writer/reader + boot-time scan + repointing
`journal-export`/`blackbox`. The live-migration unit that actually creates p4 on already-deployed
cards is pi-tools#t-049. Bench validation (migration + simulated power cut + `dump` reconstruction
past a torn record) is pi-tools#t-050. Fleet rollout order to `biennale-lyon-2026` is that
engagement's own task once this ships — pi-tools is a component with no client.
