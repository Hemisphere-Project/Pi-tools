# audiohub

Always-on multi-output audio hub for dedicated player machines (absorbs the
legacy `audioselect`). The player application only ever plays the `snd-aloop`
loopback; every physical output is an independent `alsaloop` forwarder:

```
app --> pcm.hplayer (plug, pinned 8ch/48k) --> hw:Loopback
             hw:Loopback capture --> dsnoop "aloopcap"
                  |-- audiohub@jack --> jackout   (Headphones, downmix, always)
                  |-- audiohub@hdmi --> hdmiout   (b1, ch0/1, always, softvol mute)
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
forwarder paused around the test; no argument walks all present outputs) ·
`mute|unmute [hdmi]` (see below).

**HDMI mute** (graph v2.1): HDMI is the one output that can emit *unwanted*
audio (display speakers nobody asked for), so `hdmiout` carries a softvol
stage — control `"Audiohub HDMI"`, anchored on the always-present Loopback
card. `audiohub mute hdmi` / `unmute hdmi` toggles it instantly: no unit
restart, no PCM close (no vchiq exposure), and while muted alsaloop keeps
streaming zeros, so the display keeps a live audio stream (no OSD popups)
and hw_ptr flow-watching stays valid. Persistence: `mute=hdmi` in
`/data/audiohub.conf`; the forwarder materializes the control (first open)
and restores the persisted state at every unit start, BEFORE any audio can
flow. At 0dB the softvol is a straight passthrough. Jack and USB have no
softvol on purpose: their graphs are the calibrated venue paths and stay
byte-identical to v2.

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

Health monitoring / UI: HPlayer2's `audiohub` interface watches the units,
the USB card, and per-sink hw_ptr flow, and shows per-output status chips in
http2; its HDMI chip drives `audiohub mute|unmute hdmi` and reflects the
`mute=` key from the merged conf.

## Known issue — parked 2026-07-21, revisit before the 02/09 install

**ESI GIGAPort HD+ (8ch, full-speed, sole altset 8ch/S16/44100): periodic
audio gaps through the forwarder**, unresolved. The trail, so nobody re-runs
it: gaps scale with tlatency (~250ms gaps at t=60ms, ~500ms at t=150ms).
Ruled out by ear + measurement: USB transport (direct speaker-test clean),
plug resampler quality (speexrate clean via speaker-test), alsaloop sync
mode (auto/none identical), SRC location (internal libsamplerate,
capture-side plug, write-side plug — all gap alike), device-side stalls
(hw_ptr advances continuously, zero XRUN: the gaps are IN the data), and
the dsnoop ring depth (16384 frames verified live — no change). jack/hdmi
reading the same dsnoop stay clean throughout.

Next lead: alsaloop's *own* capture window is derived from -t, so a deep
dsnoop ring can't help past the reader's window — first September test:
usb forwarder with a large -t (>=300000) despite the latency cost, or
replace alsaloop with a writer that decouples read/write buffering
(ffmpeg is broken on the 7.1 image: /usr/local lib mismatch). A
high-speed 48k-native 8ch interface would sidestep the whole class.

## Kernel hazard — never close both firmware PCMs at the same instant

Concurrent teardown of the two bcm2835 sinks (jack + hdmi closing together,
e.g. a simultaneous `systemctl restart` of all forwarders with SIGKILL-fast
stops) can race the VCHI service close and **oops the kernel**: signature is
`bcm2835-audio: failed to close VCHI service connection (status=-11)`
followed by a NULL deref in `snd_pcm_pre_stop` on the `vchiq-slot/0` thread
(6.18.38-v7+, bench 2026-07-21). The oops dies holding the substream lock —
every later open/status read on the card blocks forever, audio is dead until
reboot.

Mitigations shipped here: `audiohub apply` restarts units one at a time, and
`audiohub-fwd` staggers the hdmi kill by 2s (TERM trap and watchdog path
both), so the two firmware closes always serialize. Anything else driving
these units must respect the same rule: **sequential stops only**.
