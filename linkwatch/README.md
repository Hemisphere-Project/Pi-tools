# linkwatch — sync-link watchdog for the dongle (and eth0) sync groups

Born 2026-09-18 at the Biennale from three losses nothing recovered by itself. One tick every
30 s (`linkwatch.timer`), role from the `/boot/wifi/<if>-sync-{STA,AP}` markers, solo players exit
at once. Everything it does is one journal line: `journalctl -t linkwatch`.

| role | condition (consecutive 30 s ticks) | action | seen |
|---|---|---|---|
| slave | interface has an address, the master (gateway) answers no ping for `FAIL_TICKS` (2) | `wlan0`: unload + reload `rtl8xxxu`, re-activate the STA profile; `eth0`: link down/up | KOUAGOU 03, 15/09: associated at -40 dBm, DHCP fine, ARP/ping/TCP dead both ways on two boards; the reload cured it instantly, a re-association did not |
| slave | no address at all for `NOADDR_TICKS` (10 = 5 min) | same | a dongle that never re-associates after the AP dropped it |
| master | a station is associated and holds a lease but answers no ping for `FAIL_TICKS` | `hostapd_cli deauthenticate <mac>` + ARP flush; the slave re-associates with a fresh session | KOUAGOU 03, 15/09: stale session after a board swap, phantom station, zyre never linked |
| master | no station for `NOSTA_TICKS` (20 = 10 min) after having had some this boot | `systemctl restart hostapd@<if>`; still none 10 min later → driver reload | the sync AP wedged with hostapd alive |

One action per `COOLDOWN` (300 s) per target. Settings in `/etc/default/linkwatch`
(`FAIL_TICKS NOADDR_TICKS NOSTA_TICKS COOLDOWN DRYRUN`); `DRYRUN=1` logs what it would do.

What it does not do: touch the maintenance hotspot (`wint`, that is apfix), touch HPlayer2 (the
wallclock rides through a driver reload: the address usually comes back identical; if not, zyre
rebuilds on the address change), or act on a solo player.

Companion in HPlayer2 (biennale): the wallclock slave asks zyre to rebuild its node when the
master's clock is heard for 60 s without a zyre peer (a master rebooted or swapped under running
slaves: the link is back, discovery never happens — LACROIX 15/09).
