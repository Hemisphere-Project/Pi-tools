# network-tools — Wi-Fi profiles + network forwarding

Manages NetworkManager keyfiles from the boot partition (and USB sticks), the
hotspot AP, and optional uplink NAT. Everything is driven from files on the
**boot partition** so a machine can be reconfigured by popping the card into a
laptop — no shell needed.

## Adding a Wi-Fi network in the field

Drop a NetworkManager keyfile into the boot partition's `wifi/` folder (or onto a
USB stick under `wifi/`), then it is applied at boot — or run `setnet` now:

```ini
# /boot/firmware/wifi/gallery.nmconnection   (or a USB stick: wifi/gallery.nmconnection)
[connection]
id=gallery
type=wifi
autoconnect=true
[wifi]
ssid=GalleryWifi
mode=infrastructure
[wifi-security]
key-mgmt=wpa-psk
psk=secret123
[ipv4]
method=auto
[ipv6]
method=ignore
```

`setnet` syncs `USB wifi/ → boot wifi/ → NetworkManager` (fixing keyfile
permissions on the way), then reloads NM.

## setnet is AUTHORITATIVE — the NM store is exactly `/boot/wifi`

RastaOS-7.5 (decided 2026-11-13; it reverses the 2026-07-22 additive-only rule):

- After the sync, any entry of `/etc/NetworkManager/system-connections/` that
  `/boot/wifi` does not hold — a stale golden profile, a profile added with
  `nmcli` in the field, a stray directory such as `_anna74-removed` — is **moved**
  to `/etc/NetworkManager/setnet-pruned/` (never deleted). To keep a profile,
  put it in `/boot/wifi`. To drop one, remove it from `/boot/wifi`.
- **Empty-source guard kept**: a missing `/boot/wifi`, or one holding no
  `.nmconnection` file at all, prunes nothing — a damaged boot folder can never
  take eth0 away.
- A USB stick stays **additive**: an incoming profile that differs from the one
  in `/boot/wifi` wins, the old copy goes to `wifi/_legacy/`; a stick never
  deletes from `/boot/wifi`.
- Desk proof of the rule: `bench/setnet-desk.sh`; of the defaults around it
  (hotspot off, no PSK in the tree, webconf's SYNC switch): `bench/netdefaults-desk.sh`.

## eth0 is the way in

`eth0-dhcp` carries `autoconnect-retries=0` (NM 1.14's default gives up DHCP
after 4 tries, ~3 min: a card booted while the DHCP server was down stayed
unreachable until a power cycle) and `ipv6.method=link-local`, so a card is
reachable over `fe80::…%<laptop-iface>` with no DHCP at all. Never write
`ipv6.method=disabled` in a profile: NM < 1.20 (Buster's 1.14) rejects the value
and silently voids the whole profile — use `ignore`.

`autoconnect-retries=0` alone is not enough: with no DHCP answer, NM fails IPv4
within a minute, keeps eth0 up on link-local alone and never asks again — the
activation did not fail, so autoconnect never re-fires (bench-02, 2026-11-14).
So `eth0-dhcp` also sets `ipv4.dhcp-timeout=100000000` (~3 years): NM runs its
own timer on it and hands the same value to dhclient as its `timeout`, so
neither gives up and a DHCP server that comes back later is picked up by
dhclient's next DISCOVER, no reboot. Not `2147483647`, NM's documented
« infinity »: NM 1.14 passes it to dhclient too, whose `first_sending + timeout`
wraps a 32-bit `time_t` on armhf — its backoff interval went negative and it
died of SIGFPE 18 s after start (bench-02, 2026-11-14). `1e8` cannot wrap
before 2034-11.

## Hotspot — off by default

RastaOS-7.5 (decided 2026-11-13): a fresh card raises **no AP**; its first start
is configured over Ethernet (above). Set `hotspot = yes` (and your own
`hotspot_password`) in `pitools.txt` and the installer generates
`wint-hotspot.nmconnection` on the boot partition: the internal Wi-Fi, renamed
**`wint`**, runs an AP (`10.0.0.1/16`, dnsmasq serves DHCP). The hotspot SSID
follows the hostname — change it with `hostrename <name>`. On **x86** the
installer strips a 5 GHz pin from an older profile (Intel radios refuse AP on
5 GHz) so NM falls back to 2.4 GHz.

**No PSK lives in this tree.** The fleet hotspot template and the venue profiles
that carried real passwords left `profiles/` (they stay in git history; rotating
them is an owner call). A site's Wi-Fi profiles belong to its `/boot` role set,
kept with the site's secrets outside Pi-tools, dropped into the boot `wifi/` folder.

## Sync-role profiles (`profiles/_disabled/`)

The four `eth0-sync-*` / `wlan0-sync-*` keyfiles are **templates for stamping a
sync card**, not defaults. The installer's profile copy skips subdirectories, so
`_disabled/` never reaches a card by itself — a card gets `eth0-dhcp` (plus
`wint-hotspot` when `hotspot = yes`), and you make it a sync card by hand-moving
the AP or the STA pair into `/boot/firmware/wifi/`, or with webconf's SYNC panel,
which takes the template from the card's `wifi/_disabled/` else from this folder.

- All four carry **`autoconnect-priority=10`**. A card stamped from the golden
  image still has its `eth0-dhcp` profile, which has no priority key (= `0`), and
  on an equal tie-break NM can pick that one instead — the card then sits on DHCP
  and never raises the static `10.1.0.1` the sync group is addressed on. `10`
  settles it while both profiles stay in `/boot/wifi`.
- The two **STA** roles carry **`autoconnect-retries=0`**, like `eth0-dhcp`: a
  slave that boots before its master's DHCP server is up keeps asking instead of
  giving up after NM 1.14's 4 tries and waiting for a power cycle.
- `wlan0-sync-AP` / `-STA` are the only Wi-Fi profiles here with **no
  `interface-name=` pin**. That is deliberate and safe: `setnet` arbitrates the AP
  role per interface and falls back to the filename prefix, and it never hands an
  AP profile to NM at all (it renders hostapd and marks the interface unmanaged).
  So `10` here cannot outrank `wint-hotspot` (priority `9`) for the internal radio.

## Uplink NAT (optional)

`uplink-fwd@<iface>` (from `starter.txt`) NATs other interfaces out through
`<iface>` — e.g. share an `eth0` uplink to the hotspot. One-shot, re-applied at
boot.

## Notes

- Profiles are stored on FAT (`umask=177`), copied to ext4 and `chmod 600` for NM
  — FAT can't hold Unix perms, so the copy is what NM reads.
- `iface-off@` / the `_olides/` scripts are legacy and non-functional — ignore.
