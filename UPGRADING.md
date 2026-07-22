# Upgrading a running device (Pi-tools 2026-2)

How to roll the Phase 0/1 improvements onto an **already-deployed** machine. Most
of it is a `git pull` (modules are symlinked from `/opt/Pi-tools`), but some
changes need a service restart, and **one class — rorw's fstab boot-safety — is
NOT applied by a pull** and needs the complementary step in §3.

> On a rorw box the root filesystem is read-only, so wrap everything in `rw` … `ro`.
> A fresh **golden-image build runs `setup.sh` and bakes all of this in** — the
> steps here are only for upgrading machines in the field without a reflash.

---

## 1. Standard deploy (all devices)

```bash
rw                                                    # rorw boxes only
git -C /opt/Pi-tools fetch
git -C /opt/Pi-tools checkout 2026-2                  # first time only
git -C /opt/Pi-tools pull --ff-only
systemctl daemon-reload                               # pick up changed unit files

# restart ONLY the services this device actually runs:
command -v audiohub >/dev/null && audiohub apply      # sequential restart; applies KillMode=mixed
systemctl is-enabled webconf 2>/dev/null   && systemctl restart webconf
systemctl is-active  synczinc@peer 2>/dev/null && systemctl restart synczinc@peer
systemctl is-active  synczinc@master 2>/dev/null && systemctl restart synczinc@master
setnet                                                # optional: re-apply wifi profiles now

ro                                                    # rorw boxes only
```

## 2. What each change needs to go live

| Change (commit) | Activation |
|---|---|
| **setnet** additive-only (`b02cb89`) | `git pull` — live on next run; run `setnet` to apply now |
| **hostrename** boot-dir (`89cef86`) | `git pull` — live on next `hostrename` call |
| **extendfs** identity-reset (`775ea56`) | `git pull` + `daemon-reload` — runs at next boot (oneshot) |
| **webconf** Bookworm fix (`89cef86`) | `git pull` + `systemctl restart webconf` |
| **audiohub** stop-safety (`2043626`) | `git pull` + `daemon-reload` + `audiohub apply` |
| **synczinc** rework (`6db3d98`) | `git pull` + `daemon-reload` + restart `synczinc@…` |
| installer / config / `setup.sh` / bootstraps (`812d13e`, `a3d1e7a`, …) | **no live effect** — only future installs / the golden image |
| ⚠️ **rorw fstab boot-safety** (`4d67909`) | **NOT applied by pull — see §3** |

## 3. rorw complementary fix (IMPORTANT — apply on already-installed rorw boxes)

A running rorw device already has its `/etc/fstab` from a *previous* install; a
`git pull` updates `rorw/install.sh` but never re-runs it. Apply the boot-safety
(the `nofail` that stops a corrupt/absent `/data` from dropping the box into an
emergency shell, plus the x86 GRUB-recordfail fix) **in place** — idempotent, safe
to re-run:

```bash
rw                                                    # rorw boxes only

# 3a. Add nofail (+ device-timeout) to /data and every /data-sourced bind.
sed -i -E '/[[:space:]]\/data[[:space:]]/{/nofail/!s/(defaults)([[:space:]])/\1,nofail,x-systemd.device-timeout=10s\2/}' /etc/fstab
sed -i -E '/^\/data\//{/bind/{/nofail/!s/(bind)/\1,nofail/}}' /etc/fstab
systemctl daemon-reload

# 3b. x86 only: neutralize GRUB recordfail (headless boxes hang at the menu after
#     an unclean boot otherwise). No-op on Raspberry Pi (no /etc/default/grub).
if [ -f /etc/default/grub ]; then
  if grep -q '^GRUB_RECORDFAIL_TIMEOUT=' /etc/default/grub; then
    sed -i 's/^GRUB_RECORDFAIL_TIMEOUT=.*/GRUB_RECORDFAIL_TIMEOUT=2/' /etc/default/grub
  else
    echo 'GRUB_RECORDFAIL_TIMEOUT=2' >> /etc/default/grub
  fi
  update-grub
fi

ro                                                    # rorw boxes only
```

The `nofail` change takes full effect on the **next reboot** (it governs how
`/data` mounts at boot). Verify with `findmnt /data` and `grep /data /etc/fstab`.

**snapd (Ubuntu only):** the seed fix (`cp` snapd's content before binding
`/data/var/snapd` over it) can't be safely retrofitted in place — a box already
running the old empty bind has already lost the seeded snaps. If a deployed Ubuntu
box uses snapd, **reflash from the new image** rather than patching. Pi boxes are
unaffected (no snapd). NVMe-partition detection (`p3`) is likewise install-time
only — a device that already booted is fine.

## 4. Golden image

Nothing special: the next image build runs `sudo ./setup.sh`, which applies every
Phase 0/1 change (install path, unattended-first, boot-safety, additive Wi-Fi,
audiohub/synczinc/extendfs fixes) from scratch. Use this path for the rorw fstab
and snapd changes — no in-place patching needed on a freshly imaged card.

## 5. Post-deploy verification

- audiohub: `systemctl status 'audiohub@*'` all active; **needs a reboot-torture
  bench-test on player-000 before 02/09** (the KillMode fix is intent-aligned but
  not yet hardware-validated — see the hub inbox note / `hplayer2#t-031`).
- Wi-Fi: `setnet` prints "additive" behavior; a stray empty `wifi/` no longer wipes
  profiles; check `/boot/firmware/wifi/_legacy/` after any conflicting update.
- rorw: `findmnt /data` shows `nofail`; a test unclean boot still reaches multi-user.
