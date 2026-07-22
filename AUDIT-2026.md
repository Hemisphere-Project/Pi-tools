# Pi-tools — Ecosystem Audit & Improvement Plan (branch `2026`)

_Audit 2026-07-21, refined 2026-07-22. Scope: global + per-component install procedures
(Raspberry Pi OS **and** Ubuntu Server x86_64), logic, performance, robustness, bugs, UX.
Method: full read of the setup engine + every module, six parallel deep-dives._

> Severity: **C** critical (broken / data loss / security) · **H** major (silent
> misbehavior / broken feature / consent) · **M** minor · **N** nit. File:line points at the
> working tree on `2026`. **Status = plan only — no code changes yet; work starts later.**

---

## Decisions & refinements locked (2026-07-22)

| Topic | Decision |
|-------|----------|
| **Install source** | Point the README one-liner + `setup.sh` self-clone at **`2026`** (the branch that actually contains the engine). No `main` merge for now. |
| **Secrets** | **Do not remediate now** — low-exposure deployments, risk accepted. Tracked in **`SECURITY-REVIEW.md`** as a standing register. filebrother's unauth file server + its hardcoded credential are **added to that register**, not fixed. |
| **Biennale (02/09)** | Show Pi is **Buster**, where audiohub is tested working. So the audiohub **aarch64/Bookworm** gap is **important but NOT deadline-blocking** — it's a strategic track, not a Phase-0 fire. |
| **rtpmidi** | **Keep the module, disable auto-install.** Arch/link fixes deferred to whenever it's deliberately enabled. |
| **synczinc `/data/sync` wipe** | **Intentional** (a clone should start clean). Not a bug — but the *trigger* needs refining so it can't nuke a master or fire on benign SD-reader swaps (discussion below). |
| **Install model** | **Unattended-first.** A fresh install runs to completion with **no prompts** — `pitools.txt` + defaults drive every choice; apt/pip/uv run non-interactively. A prompt appears *only* on an unexpected error/problem. Optional `ask` groups resolve to **skip** in unattended mode (set them in `pitools.txt` to install). |
| **Python deps** | Adopt **uv** (already installed at bootstrap) instead of system `pip3` — robust under PEP-668. synczinc is the first consumer. |
| **Wi-Fi profiles (setnet)** | **Additive-only: never delete** existing profiles (in `/boot/wifi` *or* NM). Don't overwrite a locally-modified `/boot/wifi` profile; divert the incoming copy to `/boot/wifi/_legacy` instead. Supersedes the Phase-0 empty-source guard (kept as a harmless subset). |

### ⚠️ Governing guardrail for the overhaul

**Verify intended usage and behaviour before fixing.** This audit reads code and configs; it
does **not** yet assume it knows every design intent. The `/data/sync` wipe is the cautionary
example — it read as a critical bug but is deliberate. Therefore **every phase below opens
with an intent-confirmation step** (read the module README + the design trail in the
`hplayer2` hub notes + git history for the relevant commits, and confirm with Thomas where
the intent is load-bearing) **before any change is written.** Findings tagged _[intent?]_
are ones where a fix depends on confirming what the module is *supposed* to do.

### 🤖 Design principle: unattended-first, prompt-free

Pi-tools installs are **autonomous and unattended**. A fresh system must install
**start to finish with no user prompt** — module selection comes from `pitools.txt`
(and defaults), and every sub-operation (apt, pip/uv, npm) runs non-interactively.
The *only* time the installer may stop for a human is an **unexpected error/problem**.
This makes several "consent" framings moot: the fix is always *deterministic
non-interactive behaviour*, never "ask the operator". Concretely across the plan:
`DEBIAN_FRONTEND=noninteractive` + `-y` (+ dpkg conflict options) on every apt call;
**uv** instead of system `pip3`; `ask` groups resolve to skip when there's no TTY;
no destructive surprises (see the Wi-Fi additive-only rule).

---

## 0. Headline

The `2026` branch is a genuine, well-thought refactor (Python installer, module.ini
contract, RO-root design, the audiohub hardening trail). But **a fresh install cannot succeed
by following the README**, several modules are **broken on the stated targets** (64-bit Pi OS
Bookworm and Ubuntu Server x86 — note the *biennale* target is Buster, where things work),
and there is a **credential-exposure register** (deferred, `SECURITY-REVIEW.md`). The ~150
findings collapse into eight root causes, so the fixes are far fewer than the findings.

Root-cause clusters:

1. **Branch/publish mismatch** — the installer lives only on `2026`; docs point at `main`.
2. **Incomplete `/boot` → `/boot/firmware` migration** — hardcoded `/boot` paths silently
   no-op on Bookworm across webconf, hostrename, synczinc, rtpmidi, and the legacy scripts.
3. **`script=yes` early-return** drops `[starter]`/`deps`/`enable`/`mask`.
4. **Weak "installed?" detection** (first-symlink) — re-runs never re-apply changes.
5. **`Restart=always` without `StartLimitIntervalSec=0`/`RestartSec`** — every failure mode
   converges to a *permanently* failed unit on an unattended box.
6. **RO-root hidden coupling** — modules assume `/data` + rorw exist; they hard-fail when not.
7. **Dual install truths** — a dead per-module `install.sh` shadows the module.ini path and
   has drifted; still live via the x86 legacy bootstrap.
8. **Secrets in tree** — deferred to `SECURITY-REVIEW.md`.

---

## PART 1 — AUDIT

### A. Global installation

| # | Sev | Where | Issue | Consequence |
|---|-----|-------|-------|-------------|
| G1 | **C** | `README.md:30`, `setup.sh:27` | Install curls `…/main/setup.sh`; manual path clones `main`. **`main` has no `setup.sh`/`setup/`** (verified). | Every documented fresh install fails. **→ Phase 0.** |
| G2 | **H** | `installer.py:459-463`, `ui.py:51-58` | Under `curl … \| sudo bash`, `input()` EOF → `ask_yn` returns default **True**. | Every `ask` group (web, audiohub, tailscale) installs **without consent** in the recommended invocation. |
| G3 | **H** | `config.py:22`, `pitools.example.txt:51`, `README.md` vs `installer.py:33` | Group key renamed `audioselect`→`audiohub`, config surfaces still say `audioselect`. | Headless `pitools.txt` from the example installs **no audio**; audioselect cleanup never runs. |
| G4 | **H** | `bootstrap.py:227-241` | On x86, netplan YAMLs deleted + NM restarted **mid-run over SSH**. | Can drop the SSH session and strand a half-bootstrapped machine. |
| G5 | **H** | installer re-run vs rorw | Re-run writes symlinks into `/etc`+`/usr/local/bin`; fails EROFS once root is RO. | "Add a module later" is broken on every hardened machine. |
| G6 | **H** | `installer.py:90-96` | `script=yes` returns before `[starter]`/`deps`/`enable`/`mask`. | tailscale's starter entry never written → can't be enabled the documented way. |
| G7 | **M** | `utils.py:119-146` | `is_module_installed` = "first symlink exists". | module.ini changes never re-applied; reflashed boot partition never repaired. |
| G8 | **M** | `utils.py:109-116` | `append_starter` dedup is **substring**-based. | Re-run re-appends `# setnet` after a user uncommented it; false skips. |
| G9 | **M** | `bootstrap.py:255-256` | IPv6 sysctl written, `sysctl --system` never run. | IPv6 stays on until reboot, during which avahi/NM already came up. |
| G10 | **M** | `bootstrap.py:148-156` | Node installed twice (apt + `n`); services call bare `node`. | Two runtimes; offline-fragile (n/npm-g/uv/oh-my-bash/filebrowser all fetch, `check=False`). |
| G11 | **M** | `bootstrap.py:127`, `config.py` | Default root pw `rootpi`, hotspot `raspberry`. | Fleet-wide known creds — **register in `SECURITY-REVIEW.md` (deferred).** |
| G12 | **M** | legacy `bootstrap/*.sh` + per-module `install.sh` | Two live install paths, drifted. | x86 installs exercise stale code; two truths per module. |

### B. Security — deferred register

All security findings (committed PSKs, syncthing shared key, filebrother noauth + its
hardcoded credential, webconf unauth + PSK disclosure + command-injection, mDNS XSS, open DNS
forwarder, default creds) are **acknowledged and deferred** per the 2026-07-22 decision, and
tracked in **`SECURITY-REVIEW.md`** with `file:line` and revisit triggers. They are **not** in
the fix plan below. Where a functional fix happens to touch the same file (e.g. webconf's
boot-dir bug, dnsmasq `bind-dynamic`), it's sequenced on its own merits.

### C. Per-component findings (C/H only; full M/N in the six transcripts)

#### Core: starter / extendfs / splash / datesync

- **starter** — **H** `main.py:33` appends `.service` unconditionally → `foo.timer` becomes
  `foo.timer.service`. **H** `main.py:36-39` blocking sequential `systemctl start` inside a
  oneshot that `multi-user.target` waits on → slow unit delays boot; latent deadlock. Fix:
  `--no-block`, suffix-aware naming.
- **extendfs** — **C** `extendfs:15-19` `rm -rf /var/lib/tailscale/` hits a **bind-mountpoint**
  → aborts before `ssh-keygen -A`, state already written → **every clone of a tailscale box
  keeps the donor's SSH host keys.** **H** non-atomic partition recreate overshoots GPT backup
  header (x86) → lost `/data`. **H** `mkdir -p /data/var` before any /data check → fails every
  boot on a no-/data RO box. **H** raw-clone fingerprints identical → clone undetected →
  duplicate machine-id/SSH keys. _[intent? confirm the identity-reset contract is desired as
  audited]_ Fix: `growpart`/in-place grow, disk-serial fingerprint, state only on success.
- **splash** (CORE) — **H** `splash:15-20` no `/dev/fb0` check/`ConditionPathExists` → silent
  no-op on headless x86; parks resident python+fbi forever. Fix: condition + blank-and-exit.
- **datesync** — **H** `datesync:2` no `curl -m` timeout (hangs, then `date -s ""`); plain
  HTTP + blind `Date` trust. Fix: `curl -fsm5 -I https://…`, sanity-check.

#### System: rorw / usbautomount

- **rorw** — mechanism sound (fstab + binds, no overlay), but boot-safety gaps:
  - **C** `install.sh:134-137` empty snapd bind over seeded snaps → **snapd broken on Ubuntu**.
  - **C** `install.sh:116-131` no `nofail`, no fsck on `/data` → power-cut corruption →
    **emergency mode on a headless box**.
  - **C** `install.sh:8-13` vs `:96-101` symlinks created before detection can `exit 1` →
    failed install reports **"already installed"** while root is fully writable.
  - **C** `install.sh:91-94` NVMe probes whole disk not p3 → empty `UUID_data` → emergency mode.
  - **H** no rw refcount/lock → concurrent writers race a remount-ro → **dpkg/db corruption**.
  - **H** `/var/spool`→tmpfs → root crontabs vanish. **H** timesyncd+ntp both disabled,
    datesync unscheduled → clock drift → TLS breaks. **H** x86 GRUB `recordfail` → headless
    hang. **H** x86 `/boot/efi` vs `find_boot_dir()`→`/boot` conflict. Empty README.
- **usbautomount** — correct udev/systemd pattern. **H** advertises `ntfs` with no `ntfs-3g`
  (kernel wants `ntfs3`); once added, fuseblk unmount path (`:199`) never fires → slots leak.
  **H** `:146` `rm -rf "$MOUNTLAST"` before relink → a real `/data/usb` dir gets deleted.
  **H** `:191-213` unplug never re-points `/data/usb` to a surviving stick.

#### Network: network-tools (+ installer wiring)

- **setnet** — design right (FAT `umask=177` + ext4 `chmod 600` solves keyfile perms). **H**
  `:69-77` deletes any system-connection not in `<boot>/wifi` → field-added `nmcli` network
  wiped on next run. **H** `:84-89` an **empty** `<boot>/wifi` or `/data/usb/wifi` deletes
  everything incl. the hotspot → a stray empty `wifi/` on a USB stick **bricks remote access**.
  Fix (confirmed 2026-07-22): **additive-only — never delete** (in `/boot/wifi` or NM);
  preserve a locally-modified `/boot/wifi` profile and divert the incoming copy to
  `/boot/wifi/_legacy`; `nmcli connection reload` not a full restart. _(Phase 0 already
  guards the catastrophic empty-source wipe; the additive rework is Phase 1.)_
- **hotspot / regdom** — **H** `hotspot=no` not honored (`installer.py:308` vs hook copying the
  profile anyway) → **always-on AP with the public default PSK**. **H** 5 GHz `band=a`/`ch36`
  needs a **persistent** regdom; only non-persistent `iw reg set` → **hotspot dead on x86 after
  reboot**.
- **dnsmasq** — **H** leasefile dir created only by rorw → with `system=no`, **dnsmasq exits
  fatally** at boot. **H** `dnsmasq.d/hotspot-wlan{0,1}.conf` drifted trap files (`wlan0/1` not
  `wint`, `bind-interfaces` landmine). Fix: `interface=wint`+`bind-dynamic`, mkdir leasefile
  dir in the hook, delete drifted samples.
- **iface-off@ / _olides** — **C** `iface-off@.service:6-7` `/` illegal in instance names +
  no `$(…)` substitution in Exec → **feature cannot run**; starter prints FAILED. `_olides/*`
  non-functional (bad `env` shebang, `ifconfig`). Delete + drop webconf's `wint-off@` ref.
- **uplink-fwd** — **H** `:19-23` one-shot ordered only `After=NM` → NM DHCP re-installs the
  routes it deleted; `&>` bashism under dash. Fix: `ipv4.never-default` on profiles, dedicated
  iptables chain, add `iptables` dep.

#### Web: webconf / filebrother / 3615-disco

- **webconf** (4038) — **C** `settings/00-name.js:8` + wifi/sync panels hardcode `/boot/…`
  while the boot dir is `/boot/firmware` on Bookworm → null deref at construction →
  `Restart=always` **crash-loop on every Bookworm Pi**. Auth/PSK/injection items →
  `SECURITY-REVIEW.md`. Fix (functional): runtime boot-dir resolution; restore server-side
  validation.
- **filebrother** (9000) — noauth root file server + hardcoded credential → **deferred to
  `SECURITY-REVIEW.md`** (owner decision). Remaining functional items: **H** curl|bash
  unpinned filebrowser download, offline-fragile, silent no-binary; **H** `avahi-utils`
  undeclared; the node wrapper adds no value (dead SIGINT handler, `ExecStop` mismatch) →
  replace with a plain unit + `ExecStartPre` init.
- **3615-disco** (80) — **H** binds 80 as root, no conflict handling; **duplicates webconf's
  `/disco`** (comment says merged) → two processes, double advertisement. XSS → security
  register. Recommendation: retire the standalone in favor of webconf `/disco`.

#### Audio: audiohub

- **H (was C — reframed: Buster is the show target, works there)** `install.sh:18-21,67-68`
  on **aarch64** no ALSA graph is installed yet forwarders start → crash-loop → **audio dead
  on 64-bit Pi OS**. Buster/armv is fine, so this is the strategic Bookworm track, not a
  biennale blocker. Fix: ship an arm64 graph, or hard-skip enabling when no graph deployed +
  fix module.ini/README support matrix.
- **C** `audiohub@.service:5-14` default `KillMode=control-group` → systemd SIGTERMs
  `alsaloop` at t=0 on every stop/reboot, **bypassing the staggered-kill hardening** → the
  documented concurrent-firmware-close **kernel oops is still reproducible on any reboot**.
  This bites Buster too. Fix: `KillMode=mixed`, bump `TimeoutStopSec`, shared `flock`
  serializer for apply/watchdog/systemd-stop. _[intent? confirm against the hplayer2 hardening
  notes before touching the kill path.]_
- **H** `:8-9` `Restart=always` without `StartLimitIntervalSec=0` → fast-exit failure
  permanently fails the unit, defeating "restart = hotplug". **H** `install.sh:68` parallel
  restart violates the module's own sequential-stop rule. **H** `install.sh:54` audioselect
  cleanup `test -e` on an already-dangling symlink → dead udev rule survives. **H** G3 key
  drift. **H** `/data/hplayer-audio.conf` override not migrated. **H** watchdog phase-offset
  can still land concurrent kills. **H** `apply` unlocked + always reports success → lies to
  HPlayer3. UX: `audiohub get`/`status --json`, graph-deploy-state check, per-sink
  `latency_us_usb` for the parked GIGAPort lead.

#### Standalone: xrun / synczinc / rtpmidi / bluetooth-pi / tailscale

- **xrun** — **H** `xrun:32-42` `--help` doesn't `exit` → launches X. **H** `:74` `chmod 777
  /tmp` clears the sticky bit. **H** `[display] rotation` is **dead config** (nothing consumes
  it) despite the advertised feature. **H** no service/starter entry → X never starts at boot.
  **H** `bootstrap.py:387` writes `video=…` into config.txt (a cmdline param) → resolution
  no-op on KMS. _[intent? confirm HPlayer2 is expected to drive xrun rather than a boot unit.]_
- **synczinc** — **C** master mode broken **three** ways: PEP-668 `pip3 install syncthing`
  (`installer.py:279`), `poetry run` with no poetry (`synczinc:12`), empty `pyproject` deps.
  **H** `master.py:198` `system.reset()` **wipes the index DB** (meant `restart()`). **H**
  busy-spin at 100% CPU with no backoff when syncthing is down. Shared API key → security
  register. **`/data/sync` wipe on clone = INTENTIONAL** — see discussion below. Fix: single
  uv/pyproject dep story (or ~40 lines of `requests`), `restart()`, backoff.
- **rtpmidi** — **KEEP, no auto-install** (owner decision). Confirm default stays `no` and the
  module is marked manual/experimental. Deferred until deliberately enabled: **C** committed
  binary is **armhf** (declared `pi,x86`) and never linked (`bins` omits it) → can't start on
  Bookworm/x86 (would run on Buster armhf). **H** `ravelox.conf:18` hardcodes `hw:1,0,0`.
  When enabled: per-arch binary/build + `index=` pin, gate platforms, consider `rtpmidid`.
- **bluetooth-pi** — **H** Buster-era manual btattach duplicates Bookworm hciuart/serdev →
  ttyAMA0 busy → crash-loop; `AutoEnable` hook no-ops on Bookworm. _[intent? confirm which OS
  gen it targets]_ — recommendation: retire or scope to legacy images.
- **tailscale** — **H** G6 (starter entry never written). **H** no `mountpoint -q /data`
  check → under rorw the bind source is RO → tailscaled **infinite 5 s restart loop**; without
  rorw, state lands on rootfs and is shadowed if /data appears later. **M** installer starts
  tailscaled before the bind → state written to the shadowed inode is lost. Fix: `/data`
  guard, stop-before-bind, one bind mechanism.

### D. Discussion — synczinc `/data/sync` wipe (intent confirmed, trigger to refine)

The wipe itself stays: a genuinely cloned card **should** start with clean sync content and a
fresh device identity, not masquerade as the donor. The problem is the *trigger and blast
radius*, not the intent:

- **Protect the master.** The master is the sendonly source of truth. `peer.sh:47-53` wipes
  `/data/sync` regardless of role → a re-detected master loses authoritative content with no
  backup. **Better:** never auto-wipe `/data/sync` on a node running in master mode; a cloned
  master should be re-seeded deliberately or demoted to peer.
- **Kill the false positives.** The stored id embeds `$MODE` (`peer`/`master`), so a mode
  swap reads as a new drive; moving the SD to a USB reader changes `ID_SERIAL` too; an empty
  `ID_SERIAL` collapses to a constant that mis-triggers. **Better:** fingerprint on the bare
  disk serial (no mode suffix), and handle empty-serial explicitly.
- **One clone-detection authority.** extendfs already detects clones (→ resets machine-id, SSH
  keys, tailscale). synczinc running its own `ID_SERIAL` check is a second, divergent
  detector. **Better:** extendfs emits a single "this boot is a fresh clone" signal (a
  one-shot flag under `/data/var`), and synczinc keys its identity-reset + peer-only data-wipe
  off that — consistent timing and semantics, no duplicate logic.
- **Separate identity from data.** Always regenerate the syncthing identity (`CONFIG_HOME`) on
  clone (cheap, correct); gate the `/data/sync` content wipe behind "peer **and** confirmed
  clone".

This needs a quick confirent with Thomas on the master re-seed story before implementing.

---

## PART 2 — PHASED PLAN

Ordered by _blast radius × likelihood_. Each phase is independently shippable, **opens with an
intent-confirmation step** (the governing guardrail), and leaves the tree better. Estimates
are rough dev-days. **Security items are excluded** (deferred to `SECURITY-REVIEW.md`).

### Phase 0 — "It can't install" · ~1 d · ✅ DONE (commit `812d13e`)
_Goal: a fresh install works by following the docs, unattended._
1. **Install source (G1):** README one-liner + manual clone + `setup.sh` self-clone → `2026`. ✅
2. **Unattended determinism (G2, G3):** no-TTY/piped runs **skip** `ask` groups and first-run
   prompts (no silent EOF-default `True`); legacy `audioselect` key aliased to `audiohub`. ✅
3. **Empty-source brick guard + `hotspot=no`:** setnet won't wipe on an empty source (`WIPE`
   sentinel forces it); `hook_network_tools` won't seed the AP when `hotspot=no`. ✅
   _(The full additive-only + `_legacy` rework moves to Phase 1.)_

### Phase 1 — Primary-target correctness · ~3–4 d
_Goal: Bookworm Pi + Ubuntu x86 actually work headless. (Buster already works.)_
1a. _Intent:_ confirm the boot-dir contract and the audiohub kill-path design against the
   `hplayer2` hub notes + the recent audiohub commits before touching them.
4. **`/boot`→`/boot/firmware` sweep** via one shared helper (webconf, hostrename, synczinc,
   rtpmidi) — kills the webconf Bookworm crash-loop and the silent hotspot-rename/sync no-ops.
   Delete the dead per-module `install.sh` shadow-truth; x86 legacy bootstrap calls `setup.sh`.
4b. **Fully non-interactive install:** `DEBIAN_FRONTEND=noninteractive` + `-y` +
   dpkg-conflict options on every apt call; **uv** for Python deps instead of system `pip3`
   (PEP-668). Delivers the unattended-first principle end-to-end.
4c. **setnet additive-only (confirmed):** never delete; preserve locally-modified
   `/boot/wifi` profiles and divert incoming to `/boot/wifi/_legacy`; `nmcli connection reload`.
5. **audiohub stop-safety (C, bites Buster too):** `KillMode=mixed` + `TimeoutStopSec` + shared
   `flock` serializer; `StartLimitIntervalSec=0`.
6. **rorw boot-safety (C×4):** `nofail`+fsck on `/data`; copy snapd content before binding;
   move symlinking after detection (+ treat script failure as not-installed); fix NVMe p3
   probe + validate UUIDs; x86 GRUB `recordfail`.
7. **synczinc "cannot start" (C):** single dep story; `restart()` not `reset()`; the
   `/data/sync` trigger refinement from §D (peer-only, master-safe, extendfs-signalled).

### Phase 2 — Robustness & unattended survival · ~3 d
2a. _Intent:_ confirm each module's absent-hardware expectation (no screen, no /data, no peer).
8. **systemd hygiene pass** on all `Restart=always` units: start-limit reset + `RestartSec`,
   drop redundant `pkill` ExecStops, `After=`/`RequiresMountsFor=/data`, `ConditionPathExists`
   (splash fb0, bluetooth ttyAMA0, tailscale /data).
9. **rorw rw refcount** (`flock` in `/run`) — fixes concurrent-writer race + logout-hook flip;
   nesting-safe, injection-safe `with_rw`.
10. **Time story:** keep timesyncd (state bound to `/data`), fake-clock as boot-time floor;
    datesync gets a timeout + https.
11. **extendfs:** non-destructive grow (`growpart`), disk-serial fingerprint, state-on-success,
    fix the tailscale-bind `rm -rf`, restart ssh after identity reset _[intent-gated]_.
12. **installer engine:** process `[starter]`/`enable` for `script=yes` (G6); strengthen
    `is_module_installed` (G7); exact-line starter dedup (G8); apply sysctl immediately (G9);
    tailscale `/data` guard.

### Phase 3 — Web functional cleanup · ~1–2 d
_(Security hardening is deferred; this is the non-security half.)_
13. webconf boot-dir fix + server-side validation; replace filebrother's node wrapper with a
    plain unit (pin/vendor the binary, declare `avahi-utils`); retire standalone 3615-disco in
    favor of webconf `/disco`.

### Phase 4 — Audio strategic track (Bookworm/aarch64) · ~2 d · not biennale-blocking
14. Ship an arm64 ALSA graph (or hard-skip + correct support matrix); audioselect cleanup
    fixes (`test -e`→`-e||-L`, stop running instances); migrate `/data/hplayer-audio.conf`;
    `audiohub get`/`status --json`; per-sink `latency_us_usb` for the September GIGAPort lead.

### Phase 5 — UX, docs, cross-platform polish · ~2–3 d
15. READMEs where they matter (rorw recovery, network field guide, audiohub integrator
    contract). Real x86 network story (regdom persistence, non-Intel radios, cloud-init
    disable, GRUB append). Single Node runtime; offline-install story. Mark rtpmidi
    manual/experimental; decide bluetooth-pi retirement _[intent-gated]_.

### Phase 6 — Efficiency refactors (opportunistic) · ~2 d
16. `--no-block` starter; splash blank-and-exit; usbautomount by-UUID mountpoints + drop dead
    scaffolding; dedicated iptables chain + `never-default` for uplink-fwd; collapse xrun's
    xrandr blocks + wire `[display] rotation`; unify the two hotspot profile templates.

---

## Open items to confirm before implementing (intent-gated)

- **audiohub kill-path** — validate the `KillMode`/flock change against the hplayer2 hardening
  notes so we don't undo a deliberate choice.
- **synczinc master re-seed** — how should a genuinely-cloned *master* be handled (demote to
  peer? manual re-seed?) — needed to finalize §D.
- **extendfs identity reset** — confirm the SSH-key/machine-id/tailscale wipe contract is
  intended exactly as audited before changing its ordering.
- **xrun boot model** — is X meant to start from a boot unit here, or is HPlayer2 the driver?
- **bluetooth-pi** — which OS generation is it for (retire vs scope-to-legacy)?
- **rtpmidi** — kept + no auto-install (decided); confirm "manual/experimental" labelling is
  the desired surface.
