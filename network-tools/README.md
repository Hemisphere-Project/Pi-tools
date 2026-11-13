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
- Desk proof of the rule: `bench/setnet-desk.sh`.

## eth0 is the way in

`eth0-dhcp` carries `autoconnect-retries=0` (NM 1.14's default gives up DHCP
after 4 tries, ~3 min: a card booted while the DHCP server was down stayed
unreachable until a power cycle) and `ipv6.method=link-local`, so a card is
reachable over `fe80::…%<laptop-iface>` with no DHCP at all. Never write
`ipv6.method=disabled` in a profile: NM < 1.20 (Buster's 1.14) rejects the value
and silently voids the whole profile — use `ignore`.

## Hotspot

The internal Wi-Fi is renamed **`wint`** and runs an AP (`wint-hotspot.nmconnection`,
`10.0.0.1/16`, dnsmasq serves DHCP). Set `hotspot = no` in `pitools.txt` to skip
it. On **x86** the installer strips the 5 GHz pin (Intel radios refuse AP on
5 GHz) so NM falls back to 2.4 GHz. The hotspot SSID follows the hostname — change
it with `hostrename <name>`.

## Sync-role profiles (`profiles/_disabled/`)

The four `eth0-sync-*` / `wlan0-sync-*` keyfiles are **templates for stamping a
sync card**, not defaults. The installer's profile copy skips subdirectories, so
`_disabled/` never reaches a card by itself — a card gets `eth0-dhcp` +
`wint-hotspot`, and you make it a sync card by hand-moving the AP or the STA pair
into `/boot/firmware/wifi/`.

- All four carry **`autoconnect-priority=10`**. A card stamped from the golden
  image still has its `eth0-dhcp` profile, which has no priority key (= `0`), and
  on an equal tie-break NM can pick that one instead — the card then sits on DHCP
  and never raises the static `10.1.0.1` the sync group is addressed on. `10`
  settles it while both profiles stay in `/boot/wifi`.
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
