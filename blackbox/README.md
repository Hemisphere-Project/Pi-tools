# blackbox — flight recorder for a player

Born 2026-09-17 (Biennale 2026): wall players went black every couple of hours and came back when
a phone joined their hotspot; garden players lost sync one evening and their hotspots went stale —
and nothing could be read after the fact. The journal lived on tmpfs (`/var/log` is a bind of
`/tmp` on the rorw layout) and vanished at every reboot, so even the power-cycle boots that
mattered were gone. Two pieces, both under `/data/var/log`, both capped.

## 1. Persistent journal (`journal-persist.service` + `journald.conf.d/blackbox.conf`)

`/data/var/log/journal` is bound over `/var/log/journal` before `systemd-journal-flush`, and
journald runs with `Storage=persistent`. Budget: 500 MB max, 1 GB kept free on `/data`, 16 MB
files, one month retention, compressed, synced once a minute (SD wear: negligible; a crash loses
at most a minute). Noisy units are rate-limited at 1000 messages per 30 s. Sizing: a quiet
master writes ~2 MB/day, a Nowde slave with its servo lines ~15–20 MB/day, so 500 MB is the
month for a slave.

What it buys: `journalctl --list-boots`, `journalctl -b -1 -u hplayer2@biennale` (the previous
boot: the one the venue power-cycled), hostapd/NetworkManager/dnsmasq/kernel/hplayer2 history
across days, wallclock drift windows and zyre link events for a whole run.

## 2. State log (`blackbox.timer`, one line per minute)

`/data/var/log/blackbox.log`, self-rotated at 8 MB × 3 (32 MB ceiling, about six weeks). Every
field is `key=value`, so one `grep` answers "what did X do at 19:31":

```
2026-09-17 13:49:22 up=1096m hp=active/0 media=01_We_are_the_Weaversfinal_0 pos=221.4 adv=y hw=None drop=None sched=off,1011111,11:00-18:00 vol=50 node=master slaves=5 locked=5 coarse=0 age=1083ms rx=00099C:2,98A91C:2,996CD4:2,99B52C:2,99E008:2 hello=0 msync=0 cc=0 servo=0 jump=0 link=0 rtc=-1s usb=0.00dB jack=2.94dB ap=1 hostapd=active ps=on assoc=0 conn=0 apst=0 apfix=0 kwifi=0 kusb=0 disp=HDMIDMT82 dev=n pwr=1 thr=0x0 t=42.9 load=0.34 free=595M tmp=2% sync=- drift=- ev=0
```

| group | fields | meaning |
|---|---|---|
| player | `hp=active/N` `media` `pos` `adv` `hw` `drop` | HPlayer2 active/restarts; mpv's file, position, and whether it ADVANCED over 1.2 s (`y` / `STALL` frozen / `idle` stopped / `noipc` mpv gone); hw decode, dropped frames |
| schedule | `sched=on|off,days,open-close` `vol` | what the profile's cfg says the player should be doing |
| **nowde** | `node=…` | **asked from the node itself** over MIDI (`nowde-probe.py`, HPlayer2's own 1 s query, no side effect): a master answers `node=master slaves=N locked=N coarse=N age=<oldest slave heard, ms> rx=<mac6>:<quality>,…`; a slave answers `node=slave sq=0|1|2 up=<node uptime> boot=<reset reason> lr=0|1 v=…`; `node=dead` = nothing in 3 s, the USB/MIDI link is gone or the node hung (what a freewheel looks like from the Pi); `node=none` = no node here |
| nowde/HPlayer2 | `hello` `msync` `cc` `servo` `jump` `link` | this minute in HPlayer2's log: HELLOs heard (a slave gets one per keepalive — 0 for minutes = it hears nothing), MEDIA_SYNC state changes (master), CC#100 receptions (slave), servo corrections `timedelay=` and JUMPs (slave outside its ±25 ms dead zone), link warnings |
| clock | `rtc=±Ns` | RTC minus system clock; `none` = no RTC; a dead cell shows as a wild delta after a power cut |
| sound | `usb=<dB>` `jack=<dB>` | USB card level (a reboot used to lose it) and the jack |
| hotspot | `ap` `hostapd` `ps` `assoc` `conn` `apst` `apfix` `kwifi` | stations now, hostapd active, power save on the AP interface, and this minute: association attempts, completed connects, AP-ENABLED events, apfix restarts, kernel wifi-driver lines. **A stale AP reads `ap=0` for hours, then `assoc>0 conn=0` while someone tries to join** — or nothing at all in hostapd while the laptop sees the SSID, which means frames never reached it (firmware-level hang) |
| usb | `kusb` | USB bus events this minute (node re-enumeration, sound card, dongles) |
| display | `disp` `dev` `pwr` | mode, device on the hotplug line, display power (video walls) |
| system | `thr` `t` `load` `free` `tmp` | throttling flags, temperature, load, free RAM, `/tmp` use (= `/var/log` on rorw) |
| zyre | `sync` `drift` | sync interface address and signal; last wallclock drift window (video walls) |
| events | `ev` | stop/play/lock-out/crash/traceback/empty-playlist lines this minute |

`blackbox tail 30` prints the last lines; `blackbox last` prints the last line one field per row.

Reading a **black-screen** episode: find the minute `adv` left `y` and what `disp`/`dev`/`pwr`/`ev`
did; then the journal of that minute. Reading a **desync**: on the master, `slaves`/`locked` and
`age` (who fell out of the table and when); on a slave, `sq` (2 → 1/0) and `hello` (12 → 0 =
node silent) at the same minute as `servo`/`jump`. Reading a **stale hotspot**: `ap` stayed 0 and
`assoc`/`conn` show the failed joins; put it next to `node`/`sq` of the same minute to see whether
the wifi hang and the sync loss are one event or two.

## Install / cost

`install.sh` (Pi-tools installer, `script = yes`) links the units, drops the journald budget,
enables both; effective at the next boot, or at once with
`systemctl start journal-persist && journalctl --flush && systemctl start blackbox.timer`
(no journald restart needed: with the bind in place `--flush` moves the runtime journal to
`/var/log/journal` and journald keeps writing there; the conf.d budget applies at the next boot).
CPU: ~4 s per minute at nice 10 on a Pi 3B+ (three `journalctl --since -60s` reads, one mpv IPC
read, one node probe of 0.8 s). Storage: ≤ 532 MB on `/data`, never below 1 GB free.
