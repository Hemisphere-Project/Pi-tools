# hplayer-audio

Always-on multi-output audio hub for HPlayer2 players (replaces `audioselect`
on those machines). The player only ever plays the `snd-aloop` loopback; every
physical output is an independent `alsaloop` forwarder:

```
mpv --> pcm.hplayer (plug, pinned 8ch/48k) --> hw:Loopback
             hw:Loopback capture --> dsnoop "aloopcap"
                  |-- hplayer-audio@jack --> jackout  (Headphones, always)
                  |-- hplayer-audio@hdmi --> hdmiout  (b1, always)
                  `-- hplayer-audio@usb  --> usbout2/8:CARD=<id>  (hotplug)
```

- `/etc/hplayer-audio.conf` is the **contract with HPlayer2**: its presence
  says "this platform runs the hub" (HPlayer2 then targets `alsa/hplayer` and
  compensates the latency); without it HPlayer2 stays on default ALSA and
  never touches audio config (laptop/dev case).
- `latency_us` (default 30000) is the ONE forwarder target for every output —
  deterministic whatever is plugged. The wrapper clamps at the 20 ms bcm2835
  floor (VCHIQ consumes in ~10 ms quanta; bench player-000, 2026-07-21).
- USB hotplug needs no udev: the usb wrapper waits for a card, picks
  `usbout8`/`usbout2` by playback width, and `Restart=always` re-enters the
  wait loop when an unplug kills the alsaloop.
- Why no dmix/multi: both are broken on the bcm2835 + Buster alsa-lib 1.1.8
  combo (dmix stalls at any geometry; 12ch multi freezes) — see the asound
  file header.

Install: via `setup.sh` (module group `hplayer-audio`) or directly
`sudo ./install.sh`. Smoke test without hardware: `./desktest.sh`.

Health monitoring / UI: the HPlayer2 `audiohub` interface watches these units
and the USB card and shows per-output status chips in http2.
