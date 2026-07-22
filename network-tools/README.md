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
method=disabled
```

`setnet` syncs `USB wifi/ → boot wifi/ → NetworkManager` (fixing keyfile
permissions on the way), then reloads NM.

## setnet is ADDITIVE — it never deletes

- A profile you add in the field (or via `nmcli`) is **never removed** by setnet.
- If an incoming profile (from a USB stick) differs from one already in the boot
  `wifi/`, the **incoming wins** and the old copy is archived to
  `wifi/_legacy/` — nothing is silently lost.
- An empty `wifi/` source is a **no-op** (it can't wipe your profiles). It was a
  brick risk before: a stray empty `wifi/` on a USB stick used to delete
  everything, including the hotspot.

## Hotspot

The internal Wi-Fi is renamed **`wint`** and runs an AP (`wint-hotspot.nmconnection`,
`10.0.0.1/16`, dnsmasq serves DHCP). Set `hotspot = no` in `pitools.txt` to skip
it. On **x86** the installer strips the 5 GHz pin (Intel radios refuse AP on
5 GHz) so NM falls back to 2.4 GHz. The hotspot SSID follows the hostname — change
it with `hostrename <name>`.

## Uplink NAT (optional)

`uplink-fwd@<iface>` (from `starter.txt`) NATs other interfaces out through
`<iface>` — e.g. share an `eth0` uplink to the hotspot. One-shot, re-applied at
boot.

## Notes

- Profiles are stored on FAT (`umask=177`), copied to ext4 and `chmod 600` for NM
  — FAT can't hold Unix perms, so the copy is what NM reads.
- `iface-off@` / the `_olides/` scripts are legacy and non-functional — ignore.
