# apfix — stale-hotspot guard (opt-in)

The maintenance hotspot (`hostapd@wint` on the Pi's Broadcom radio) can go stale: it beacons, a
laptop associates, and the handshake never completes. Seen on cold boots and after about 2 h in
operation (Biennale 2026, W2/W4/W5/068). Only a hostapd restart clears it.

`apfix` restarts `hostapd@wint` **only when no station is associated**, so a connected maintenance
laptop is never kicked. `apfix.timer` runs it 90 s after boot (the known cure for a stale first
start), then every 20 min. Each restart logs `apfix: no station on wint: hostapd@wint restarted`
(journal tag `apfix`; blackbox counts them in its `apfix=` field).

**Off by default.** RastaOS 7.5 ships the hotspot off and sets up over Ethernet (rastaos decision
13/11/2026), so a guard for it is opt-in: `apfix = yes` in `[modules]` of pitools.txt, or
`apfix/install.sh --now` by hand. It does nothing useful on a box with no `wint` hotspot.

Until 7.5 it lived as a field copy in Runbooks (`biennale-deploy/pitools/apfix`, installed by
`apfix-deploy` and `patch-golden`); a 7.4 card carries that copy in `/usr/local/sbin`.
`install.sh` overwrites it with this one (same script), so a field card converges.

Not to confuse with `linkwatch`, which watches the **sync** link (`wlan0`/`eth0` sync AP and
dongle slaves), never `wint`.
