# audiohub

Always-on multi-output audio hub for dedicated player machines (absorbs the
legacy `audioselect`). The player application only ever plays the `snd-aloop`
loopback; every physical output is an independent `alsaloop` forwarder:

```
app --> pcm.hplayer (plug, pinned 8ch/48k) --> hw:Loopback
             hw:Loopback capture --> dsnoop "aloopcap"
                  |-- audiohub@jack --> jackout   (Headphones, downmix, always)
                  |-- audiohub@hdmi --> hdmiout   (b1, ch0/1, always)
                  `-- audiohub@usb  --> usbout<N>:CARD=<id>  (hotplug, straight)
```

**Channel policy**: jack is the only output that collapses (ch0/1 unity +
other channels folded at 0.5 — a bench headphone hears everything, stereo
media keeps its calibrated level). HDMI ch0/1 straight. USB is STRAIGHT 1:1 —
the wrapper picks `usbout2/4/6/8` from the card's playback width, so a 2ch
interface plays ch0/1, an 8ch interface plays all 8, and nothing is folded.

**Config — the contract with applications**: `/etc/audiohub.conf` (platform
defaults) overridden by `/data/audiohub.conf` (user/app-writable, survives a
read-only rootfs; later file wins). Its PRESENCE means "this platform runs
the hub" — HPlayer2/HPlayer3/third-party apps detect it, target
`alsa/hplayer`, and compensate `latency_us`; without it they must leave the
audio environment alone (laptop/dev case).

**Control CLI** (`audiohub`): `status` · `set latency_us=25000` · `apply` ·
`test [jack|hdmi|usb]` (plays marimba.wav on one physical output with its
forwarder paused around the test; no argument walks all present outputs).

- `latency_us` (default 30000) is the ONE forwarder target for every output —
  deterministic whatever is plugged; clamped at the 20 ms bcm2835 floor
  (VCHIQ consumes in ~10 ms quanta; bench player-000, 2026-07-21).
- USB hotplug needs no udev: the usb wrapper waits for a card and
  `Restart=always` re-enters the wait loop after an unplug.
- Why no dmix/multi: both are broken on bcm2835 + Buster alsa-lib 1.1.8
  (dmix stalls at any geometry; 12ch multi freezes) — see the asound header.

Install: via `setup.sh` (module group `audiohub`) or `sudo ./install.sh`
(idempotent; migrates old `hplayer-audio` installs and removes audioselect).
Smoke test without hardware: `./desktest.sh`.

Health monitoring / UI: HPlayer2's `audiohub` interface watches the units and
the USB card and shows per-output status chips in http2.
