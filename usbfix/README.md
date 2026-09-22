# usbfix — USB-link watchdog (re-enumerate a stalled device)

Born 2026-09-17 in the Biennale garden (six Pi 3B+ players, RastaOS 7.3, kernel 6.18, a Nowde
ESP32-S3 node on USB). Five times in one afternoon a slave's node stopped answering; the kernel
then logged `usb 1-1.2: urb status -32` (device 1-1.2 = the node, -32 = endpoint STALL) for **every**
transfer — about 7000 lines a second, for as long as nobody intervened. `snd-usbmidi` resubmits an
URB that came back -EPIPE immediately and forever; that is upstream behaviour to this day.

What the loop does to a 3B+: USB (`dwc_otg`) and the SDIO wifi both take their interrupts on CPU0.
The **hotspot goes blind** (the wifi firmware still answers authentication and association, the WPA
handshake never comes, hostapd logs nothing), systemd timers stall, the 102 MB tmpfs `/var/log`
fills within a minute (rsyslog writing the storm twice), journald drops millions of kernel messages
and rotates the whole persistent journal away in minutes. Symptom seen from outside: "the player's
hotspot hangs on association" — and for a Nowde slave, "it freewheels out of sync".

The cure that needs no visit: **de-authorize and re-authorize the USB device** (`/sys/bus/usb/
devices/<path>/authorized` 0 then 1). That is a port reset and a re-enumeration: the device keeps
running (a node's uptime continues), the host rebuilds its endpoint state, the storm stops, and the
application relinks (HPlayer2: "subscription gone — relinking", two stop/play cycles, relock).
Measured on W4, 2026-09-17: storm at 15:24:36, reset 15:24:38, link back 15:24:46, in sync a minute
later.

## Triggers (checked every minute)

| trigger | how | device reset |
|---|---|---|
| **storm** | ≥ `STORM_MIN` (100) `urb status` lines in the last 400 lines of the kernel ring buffer — read from `dmesg`, never from journald, which drops most of it | the one named in those lines |
| **journald dropping** | `systemd-journald` reported "Missed N kernel messages" ≥ `MISSED_MIN` (5) times in the last minute | the `PRODUCT` device (Nowde) if exactly one, else log only |
| **silent node** | a `PRODUCT` device exists, hplayer2 logged ≥ 60 `HELLO` lines in the previous 10 min and none in the last 90 s (a Nowde slave answers a keepalive every 2 s; a master's node never chats, so this cannot fire on a master) | the `PRODUCT` device |

One reset per `COOLDOWN` (300 s). Settings in `/etc/default/usbfix` (`PRODUCT`, `STORM_MIN`,
`MISSED_MIN`, `COOLDOWN`). Everything it does is one line in the journal: `journalctl -t usbfix`.

## rsyslog

`install.sh` also turns rsyslog's kernel intake off (`imklog` commented out, `kern.* stop` in
`/etc/rsyslog.d/00-kern-journal-only.conf`): kernel lines live in the journal (persistent with the
`blackbox` module), not in tmpfs files that a storm fills in a minute. `--no-rsyslog` to skip.

## Install

```sh
bash install.sh          # units linked + enabled, rsyslog hardened; effective at the next boot
bash install.sh --now    # ... and start the timer + restart rsyslog now
```

Prove the recovery path once on a healthy player (a few seconds without the device):

```sh
dev=$(for d in /sys/bus/usb/devices/*/product; do grep -l Nowde $d; done | head -1 | cut -d/ -f6)
echo 0 > /sys/bus/usb/devices/$dev/authorized; sleep 2; echo 1 > /sys/bus/usb/devices/$dev/authorized
journalctl -k --since -20s | tail; journalctl -u 'hplayer2@*' --since -20s | grep -iE 'link|playing'
```

## What it is not

Not prevention: the stall still happens (root cause under study — host `dwc_otg` state vs the node's
USB stack; see the Nowde repo, `docs/usb-in-stall-plan-2026-09-17.md`). With this watchdog a stall
costs a few seconds of link instead of the rest of the day. If a device is truly wedged (the storm
returns right after every reset), only power helps; a Pi 3B+ has no per-port USB power switching
without `uhubctl`, so that tier is not built. Pair it with `blackbox` to see the storms
(`urb=`, `kmiss=`, `usbfix=` fields) and what else happened in that minute.
