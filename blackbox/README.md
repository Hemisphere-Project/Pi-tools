# blackbox — flight recorder for a player

Born 2026-09-17 (Biennale 2026): players went black every couple of hours and came back when a
phone joined their hotspot, and nothing could be read after the fact — the journal lived on tmpfs
(`/var/log` is a bind of `/tmp` on the rorw layout) and vanished at every reboot, so even the
power-cycle boots that mattered were gone. Two pieces, both under `/data/var/log`, both capped.

## 1. Persistent journal (`journal-persist.service` + `journald.conf.d/blackbox.conf`)

`/data/var/log/journal` is bound over `/var/log/journal` before `systemd-journal-flush`, and
journald runs with `Storage=persistent`. Budget: 200 MB max, 512 MB kept free on `/data`,
16 MB files, one month retention, compressed, synced once a minute (SD wear: negligible; a
crash loses at most a minute). Noisy units are rate-limited at 1000 messages per 30 s.

What it buys: `journalctl --list-boots`, `journalctl -b -1 -u hplayer2@biennale` (the previous
boot: the one the venue power-cycled), hostapd/NetworkManager/dnsmasq/hplayer2 history across
days, wallclock drift windows and zyre link events for a whole run.

## 2. State log (`blackbox.timer`, one line per minute)

`/data/var/log/blackbox.log`, self-rotated at 8 MB × 3 (32 MB ceiling, about two months):

```
2026-09-17 15:41:02 up=812m hp=active/0 media=01_CYCLE_Gauche_50s.mp4 pos=118.4 adv=y hw=mmal drop=1 disp=CEA31 dev=y pwr=1 thr=0x0 t=52.1 load=0.71 free=412M tmp=3% ap=0 sync= wlan0=10.1.0.1 drift=- ev=0
```

Fields: HPlayer2 active/restarts; mpv media, position and whether it ADVANCED over 1.2 s
(`adv=y`, `STALL`, `idle`, `noipc`), hardware decode, dropped frames; display mode, device seen
on the hotplug line, display power; throttling flags, temperature, load, free RAM, `/tmp` use;
stations on the hotspot; sync interface address and signal; last wallclock drift window; count of
stop/play/lock-out/traceback events in the last minute. `blackbox tail 30` prints the last lines
one field per row.

Reading a black-screen episode: find the minute `adv` left `y` (STALL = mpv frozen, idle = stopped,
noipc = mpv gone) and what `disp`/`dev`/`pwr`/`ev` did at that minute; then the journal of that minute.

## Install / cost

`install.sh` (Pi-tools installer, `script = yes`) links the units, drops the journald budget,
enables both; effective at the next boot, or at once with
`systemctl start journal-persist blackbox.timer && systemctl restart systemd-journald`.
CPU: ~0.3 s per minute (one python IPC read). Storage: ≤ 232 MB on `/data`, never below 512 MB free.
