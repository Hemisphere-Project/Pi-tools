# Pi-tools — Security Review (deferred items)

_Created 2026-07-22. Companion to `AUDIT-2026.md`._

**Disposition: ACKNOWLEDGED — NOT remediating now (owner decision, 2026-07-22).**
Rationale on file: Pi-tools machines run in **low-exposure** settings (isolated venue LANs,
short-lived installs), so the practical risk is low. This document is the standing register
of the known exposures so the decision is deliberate and revisitable — **no code changes are
implied by this file.** Nothing here prints secret values; each item points at `file:line`
so the value can be found (note: committed secrets are also recoverable from git history).

Revisit triggers (when "low exposure" stops holding): a machine placed on an untrusted or
internet-reachable network; the hotspot opened to the public with the default PSK; the repo
made fully public / widely forked; or any deployment handling data that matters if leaked.

---

## Register

### 1. Committed Wi-Fi PSKs (network profiles)

WPA-PSK values are committed in NetworkManager keyfiles (and in history). These are real
venue/hotspot passwords, not placeholders.

| File | Identity | PSK at | Note |
|------|----------|--------|------|
| `network-tools/profiles/wint-hotspot.nmconnection` | ssid `rasta-00` (hotspot) | L21 | Default fleet hotspot PSK; also drives the AP an operator reaches the box through. |
| `network-tools/profiles/_disabled/wlan0-hotspot.nmconnection` | ssid `rasta-00` (hotspot) | L19 | Pre-rename twin of the above. |
| `network-tools/profiles/_disabled/wint-bohlen.nmconnection` | ssid `kxkm-wifi` | L13 | Venue WPA credential. |
| `network-tools/profiles/_disabled/wint-hmsphr.nmconnection` | ssid `interweb` | L12 | Venue WPA credential. |
| `network-tools/profiles/_disabled/wint-interweb.nmconnection` | ssid `interweb` | L13 | Venue WPA credential (duplicate `id=interweb` with the row above). |

_Exposure:_ anyone who can read the repo learns the venue and hotspot passwords; every
deployment that ships these files carries the same hotspot PSK.
_If/when remediated:_ rotate the venue passwords out-of-band; replace committed `psk=` with a
placeholder and inject the real value device-locally at install (the installer already does
this for the generated hotspot via `setup_wifi_from_config`). A `psk=` purge also needs a
history rewrite to be complete — a separate, heavier decision.

### 2. Shared syncthing admin API key + open GUI

| Item | Location |
|------|----------|
| Committed shared API key | `synczinc/key` (read by `peer.sh:33`, `master.py:23`) |
| GUI bound to all interfaces | `peer.sh:58` (`-gui-address=0.0.0.0:8384`), `master.py:102,171` |
| `insecureAdminAccess=True` | `master.py:104,173` |

_Exposure:_ the same API key ships on every deployment; combined with the `0.0.0.0` GUI and
`insecureAdminAccess`, anyone on the LAN who has read the repo has full REST admin of a
root-run syncthing (add a folder anywhere writable, exfiltrate/overwrite `/data/sync`).
Device **certs are still per-machine** (identity is not shared) — it's the REST auth that the
shared key defeats.
_If/when remediated:_ generate the API key per-install (store under `/data/var/`), bind the
GUI to localhost (or the tailscale/hotspot interface only), drop `insecureAdminAccess`.

### 3. filebrother — unauthenticated root file server over `/data`

| Item | Location |
|------|----------|
| `--auth.method=noauth`, bound `0.0.0.0`, serving `/data` as root | `filebrother/filebrother.js:30` |
| Hardcoded user credential `root` / `rootpirootpi` | `filebrother/filebrother.js:31` (meaningless under noauth, but a committed credential) |

_Exposure:_ on the hotspot/venue LAN, anyone can read, delete, replace, or upload files
across all of `/data` (media + persistent state) with no login. The committed
`rootpirootpi` string is a secret in the tree regardless.
_If/when remediated:_ enable filebrowser auth (a first-run admin credential) or bind to a
trusted interface only; remove the hardcoded `users add` line.

### 4. webconf — unauthenticated control plane + PSK disclosure

| Item | Location |
|------|----------|
| No auth on any action (rewrite network config, change hotspot PSK, reboot) | `webconf/webconf.js:35-72` |
| Hotspot PSK pushed to every client on connect (plaintext) | `webconf/settings/01-wifi.js:14` → `settings` emit |
| Hostname written verbatim into `starter.txt` (executed as service directives) → stored command injection via a newline | `webconf/settings/00-name.js:14` |

_Exposure:_ any client that can open port 4038 (e.g. over the open hotspot) can reboot or
reconfigure the box and is handed the admin Wi-Fi password; a crafted hostname can plant a
boot-time command. Note: this panel currently **crash-loops on Bookworm Pi** (see
`AUDIT-2026.md`, webconf C-finding), so the control plane isn't reachable there today — but
that's a bug, not a mitigation.
_If/when remediated:_ a shared-secret/PIN gate before mutating actions; never send secret
values to clients (send a masked placeholder, write only on non-empty change); validate the
hostname charset and reject newlines server-side.

### 5. Default credentials (fleet-wide, by design)

| Item | Location | Default |
|------|----------|---------|
| Root password | `setup/config.py:11`, `setup/bootstrap.py:128` | `rootpi` |
| Hotspot password | `setup/config.py:16` | `raspberry` |

_Exposure:_ known-by-default SSH root login + AP password across the fleet unless overridden
in `pitools.txt`. This is an intentional convenience default; the exposure is only real when
a deployment doesn't override it.
_If/when remediated:_ force/prompt a password change on first boot, or document per-deploy
override as mandatory.

### 6. Stored XSS from mDNS in the discovery UIs

| Item | Location |
|------|----------|
| mDNS `host`/`name`/`ip` injected via jQuery `.html()` | `3615-disco/www/script.js` (79, 96, 126); `webconf/www/disco/script.js` (63, 96) |

_Exposure:_ a device on the LAN advertising a service whose host/name contains markup gets
script execution in the operator's browser when they open the discovery page. Low severity
under the low-exposure model; listed for completeness.
_If/when remediated:_ render with `.text()`; never concatenate mDNS strings into `.html()`.

### 7. Open DNS forwarder

| Item | Location |
|------|----------|
| dnsmasq enabled wildcard-bound on every machine | `setup/bootstrap.py:224`, hook `installer.py:189-195` (no `bind-dynamic`/`local-service`) |

_Exposure:_ the resolver answers on the venue uplink too, not just the hotspot subnet — an
open forwarder usable for amplification if the uplink is hostile.
_If/when remediated:_ scope dnsmasq to `interface=wint` + `bind-dynamic`, or `local-service`.

---

## Not secrets, but adjacent (tracked in AUDIT-2026.md, not here)

- SSH: `PermitRootLogin yes` + `PasswordAuthentication yes` + `UsePAM no` (`bootstrap.py:99-101`)
  — intentional for field access; noted so it's a conscious posture.
- These items are **register-only**. Functional/robustness fixes that happen to touch the same
  files (e.g. webconf's boot-dir bug, dnsmasq's `bind-dynamic`) are sequenced in the main plan
  on their own merits, independent of this deferral.
