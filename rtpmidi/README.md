# rtpmidi — RTP-MIDI (AppleMIDI) bridge

⚠️ **Experimental / manual — not auto-installed** (default `no`; enable
explicitly in `pitools.txt`).

Bridges network RTP-MIDI (CoreMIDI / AppleMIDI compatible) to an ALSA rawmidi
port via `raveloxmidi`.

**Known limitation before you enable it:** the committed `raveloxmidi` binary is
32-bit ARM (armhf) — it runs on Buster/armv but **not** on 64-bit Pi OS or x86.
For those, build raveloxmidi from source (github.com/ravelox/pimidi) or use a
maintained alternative (`rtpmidid`, which ships arm64/amd64 debs). The launcher
also assumes the virmidi card lands at `hw:1` — pin it with
`modprobe snd_virmidi index=…` if other sound cards are present.

Ports: 5004–5006/udp. Pair from macOS Audio MIDI Setup → Network. Route the
virmidi port to your app with `aconnect -l` / `aconnect`.
