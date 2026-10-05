# extendfs

Extend last partition to FS size after clone

## A clone's first boot reboots on its own

On a new drive (drive-id in `/data/var/drive-id` does not match) extendfs goes
`rw`, grows the last partition and its filesystem, resets the clone's identity
(machine-id, Tailscale state, SSH host keys), records the drive-id, then reseals
the root with `ro`. Two cases end in an automatic reboot:

- **stage 1** — the kernel cannot reload the table of a mounted partition: the
  progress goes to `drive-id-stage1` and the box reboots to finish the resize.
- **the reseal fails** — something started alongside extendfs pins the root
  (`RO Failed after 5 attempts`, `mount point is busy`). The drive-id is already
  recorded, so the next boot exits at "drive-id is valid" without going `rw`, and
  root comes up read-only from fstab.

The reseal reboot only happens when it is sure to be the last one: the run
succeeded and recorded the drive-id, it was started by `extendfs.service` (never
from a shell — `extendfs -f` by hand just tells you to reboot), and it never
fires twice in a row (`drive-id-sealreboot`, cleared by the next valid boot).
Otherwise root stays `rw`, the unit fails, and `ro-assert` keeps retrying.
