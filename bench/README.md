# bench/ — laptop- and bench-side tools

Nothing in this directory is installed on a player. These are the tools you run
from **your own machine** against a player, a card, or a whole fleet. Module code
that runs *on* the Pi lives in the module directories (`network-tools/`,
`audiohub/`, …); anything that needs a laptop, a card reader or a radio lives
here.

| tool | what it is for |
|---|---|
| `verify` + `verify-modules.py` | the commit-time floor: every script parses, every file a `module.ini` names exists |
| `fleet-run` + `fleet-lib.sh` | walk a roster of player **hotspots**, run one command on each, skip the dead ones |
| `fleet-patch-hostapd.sh` | one-off: convert existing players from the NM/wpa_supplicant AP to hostapd, no reflash |
| `sd-converge` | bench SD carousel: converge player **cards** to this machine's checkouts, no network |
| `burn-batch` | clone one golden image onto N cards at once, and prove every card byte-for-byte |

---

## `verify` — what "green" means here

```sh
./bench/verify        # exit 0 green, 1 red, 2 could not run
```

This repo has no test suite and cannot have much of one: its product is shell
installers that run as root, on a Pi or an N100, against real cards and real
radios. So `verify` is a **floor**, and it is worth being exact about where that
floor sits.

**Layer 1 — syntax.** Every tracked shell script parses (`bash -n`), every
tracked python file compiles. Scripts are found by **shebang**, not extension:
most of them are extensionless (`rorw/ro`, `datesync`, `audiohub/audiohub`), and
`bootstrap/bootstrap-ubuntu-server-x86.sh` is the inverse — a `.sh` file that is
prose. This catches the unclosed `fi` and the stray paren, i.e. the class of
break otherwise found by a player, at boot, in a garden.

**Layer 2 — `module.ini` referential integrity.** `setup/installer.py` links
bins and installs services, timers and udev rules under `if os.path.isfile(src):`
**with no else**. A `module.ini` naming a file that is not in the repo installs
nothing, prints nothing, and reports success: the box comes up missing a unit
and the install log is clean. Layer 2 is that missing else branch — plus
`script = yes` without an `install.sh`, `npm = yes` without a `package.json`, a
`platforms` token `check_platform()` does not know, and a module the installer
lists but which has no `module.ini`.

A `module.ini` reachable from neither `MODULE_GROUPS` nor `CORE_MODULES` is a
**warning**, not a failure — unreachable-from-the-installer is a real finding,
but it is a judgement about intent, and a gate that refuses every commit until
someone resolves it would freeze the repo over a question nobody asked.

### What a green does not prove

* That any script **does** the right thing. `bash -n` parses; it never runs.
* Anything at all about **hardware** — no Pi, no N100, no sound card, no radio,
  no card reader is involved. The tools that need those are in this directory,
  and none of them runs here.
* That an **install succeeds**. Layer 2 proves a module's files are present in
  the repo, not that installing them onto a box works.

Green means "nothing is obviously broken", which is what a commit gate should
mean. It is not "it works". Everything past it is still a bench.

---

## `fleet-run` — one pass over N players' hotspots

Joining six garden hotspots one at a time, by hand, is slow, and the slow part is
not the work — it is the waiting on the ones that are not there. `fleet-run` does
the walking:

```
for each player in the roster:
    switch the laptop onto that player's hotspot
    ask it its hostname  ──── does not match the roster? REFUSE, record, move on
    run the command you typed
    record one outcome, leave, next
```

and prints a table with one row per player.

```sh
# see exactly what it would do, on a machine with no radio at all
./fleet-run --dry-run -r fixtures/fleet-roster.example 'uptime'

# the real thing, then a second pass over only the ones it never reached
./fleet-run --retry-misses 'cd /opt/HPlayer2 && git pull --ff-only'

# a laptop-side command, run while joined to each player
./fleet-run --local -- scp ./media.mp4 '%t:/data/'
```

```
PLAYER         OUTCOME        RC   SECS  DETAIL
player-000     ok              0     22  command ok
player-066     ok              0     19  command ok
player-067     wrong-host      -      8  answered as player-068
player-068     fail            1     24  command exited 1
player-069     miss            -     12  no association
player-absent  miss            -     12  no association
```

### It is generic on purpose

`fleet-run` has no idea what a deploy is. It does not know which ref you want,
which media belong on which player, or what "converged" means — **the command is
readable at the invocation**, and when it misbehaves you fall back to doing the
same command by hand.

An opinionated deploy campaign that owns its own semantics fails differently: it
writes the *wrong content* to the *right* player, or the right content to the
wrong one, and neither is visible in a result table. That tool is deliberately
not this one. If you want it, it needs six players in a garden to rehearse
against, not a bench.

### The identity assert is the point

Every player serves its hotspot at **`10.0.0.1`**. After a blip — or with a
laptop that knows several player profiles — you can associate with a *neighbour*
and get a perfectly working root shell on the wrong machine. Nothing about the
session looks wrong.

So between the join and your command, `fleet-run` asks the player its `hostname`
and compares it with the roster name. A mismatch is `wrong-host`: it drops both
associations, records who actually answered, and **does not run the command**.
This is the one failure the tool cannot take back, so the assert is not optional
and has no flag to disable it.

The corollary is that the roster's first column must be right. It is the player's
hostname — the `hostrename@<name>` line in its `/boot/starter.txt` — and it is
also its SSID unless someone diverged them.

### Outcomes

| outcome | meaning | retried by `--retry-misses`? |
|---|---|---|
| `ok` | joined, identity matched, command exited 0 | — |
| `fail` | identity matched, command exited non-zero | **no** — it ran, and re-running someone else's command is a decision |
| `miss` | hotspot not on air, or association refused | yes |
| `unreachable` | associated, but ssh never answered | yes |
| `wrong-host` | answered as another player, command refused | yes |
| `timeout` | the per-player budget ran out | yes |
| `dry` | `--dry-run`, nothing was touched | — |

A retry **replaces** the first row, so the table always has exactly one line per
player, in roster order.

### Budgets

`--timeout SEC` (default 180) is a wall budget for one player: join, identify,
run, leave. `--join-timeout SEC` (default 45) bounds the association inside it. A
player that is not on air costs the join budget and nothing more — three of six
cold boots came up in the stale hostapd state that only a power-cycle clears
(2026-09-08), so **missing players are the normal case**, and the pass is built
around that rather than against it.

### The roster

Whitespace separated, `#` comments and blank lines ignored:

```
<name> [ssid] [target]
```

`name` is the hostname *and* the identity assert; `ssid` defaults to it; `target`
defaults to `root@10.0.0.1` — override it to reach a player over ethernet.
`fixtures/fleet-roster.example` is a working example, including a row for a
hotspot that is never on air, which is how you watch a miss cost seconds.

Search order when `-r` is not given: `./fleet-roster`,
`~/.config/pitools/fleet-roster`, `bench/fleet-roster`.

### Your laptop keeps its internet

Profiles `fleet-run` creates carry `ipv4.never-default`, `ipv4.ignore-auto-dns`,
`ipv6.method disabled` and `connection.autoconnect no`, so associating with a
player never steals your default route or your resolver, and a blip cannot
silently auto-join you to a neighbour. For a profile that already exists it
enforces only those three safety keys and leaves everything else you set.

Keep the uplink on **ethernet** (NM metric 100 beats wifi 600). And do not put a
bench router on `10.0.0.0/24` — it collides with the hotspot subnet and the
player reads as flaky rather than misrouted.

### Credentials

The fleet PSK is **never** in this repo. `fleet-run` reads `$FLEET_PSK`, or the
first line of `$FLEET_PSK_FILE` (default `~/.config/pitools/fleet.psk`). It is
only needed to *create* a profile; existing ones are reused as they are. The key
was rotated on 2026-09-04 — a profile built with the old one fails at the 4-way
handshake and NetworkManager reports it as `no-secrets`, not as a wrong password.

If your agent holds several identities, pin one with `FLEET_SSH_KEY=~/.ssh/<key>`:
otherwise the player's `MaxAuthTries` cuts the attempt before the right key is
offered, which reads as "keys not authorized, password only".

### Status

`--dry-run` and the roster/table/retry bookkeeping are exercised without a radio.
**The radio behaviour is not proven yet** — the association, a real identity
assert, and the cost of a genuine miss need a player and its hotspot in range.
That is the bench smoke in `pi-tools#t-025`. Until it has run, the fallback for a
fleet pass is the by-hand procedure, which is a slow day rather than a broken one.

`fleet-patch-hostapd.sh` is intentionally **not** refactored onto `fleet-lib.sh`:
it is field-proven code, and the week before a site visit is the wrong week to
touch it.

---

## `burn-batch` — N cards from one golden image, each one proved

```sh
./bench/burn-batch -l                              # which readers, which serials
./bench/burn-batch -n ~/RPi-images/RastaOS-7.3.img # plan it: targets, refusals
pkexec bash bench/burn-batch /home/me/RPi-images/RastaOS-7.3.img
```

Rolling a card lot is not `dd` in a loop. Four phases, and each one is there
because skipping it produces a card that looks burned and does not boot:

1. **fsck the image**, once, before it is cloned N times. An image captured
   from a card that was not cleanly unmounted carries an unreplayed `/data`
   journal that *every* clone replays on first boot, and `rorw`'s helper leaves
   the vfat dirty bit set on `/boot`. The boot vfat and the **last** ext4
   (`/data`) are repaired; every other ext4 is checked and never written — a
   golden's rootfs is the thing under test, not something to silently repair.
   `--fsck-only` runs this phase alone, which is worth doing once to an image
   you are about to archive.
2. **Unmount.** The desktop automounts every inserted card read-write.
3. **Burn**, in parallel, capped by `-j` (default 3).
4. **`cmp` every card against the image.** This is the phase the tool exists
   for. A reused card can silently fail its write in the most-worn zone — the
   first ~260 MB, where its previous FAT lived: the burn "completes", the
   rootfs is correct, `/boot` keeps a foreign volume id, and the Pi does not
   boot. Nothing else catches it.

### The refusals are the safety, not the confirmation

Nothing is written until every target survives: not `nvme`, not non-removable,
not the disk the image itself lives on, not a card smaller than the image, and
not a slot reporting 0 B (that is an **unseated card**, not a dead one —
reseat it). A device with no reader serial is refused too, because it could not
be re-resolved later. Then it still asks you to type the card count.

### Why serials, and why the tool looks them up three times

Targets are named by **reader serial**, and the serial is resolved to a `/dev`
node again immediately before the write *and* again before the verify. Device
names shuffle after a hub reset, and with several cards in, `/dev/disk/by-label`
points at one arbitrary card — a `/dev/sdX` noted a minute ago is how a batch
lands on the wrong card. Pass `/dev/sdX` if you like; it is pinned to its serial
at once. `-l` also prints each reader's **USB port path**, so you can label the
physical slot.

### The hub is the ceiling, not the reader count

`-j 3` by default. On the 16-card LEA run (2026-09-10) a **bus-powered** hub
dropped **all five** of its readers at once at six parallel writes — every one
raised `[Errno 19] No such device` mid-write, while the card on a direct port
finished alone. `-j 3` completed the same batch. Sizing a batch by how many
readers fit is how you lose the whole batch mid-write.

Expect the batch to finish ragged: cards of different brands and ages write
anywhere between **14 and 100 MB/s**, so planning on the fastest card's time is
wrong by a factor of several. The per-card rate lands in the table and in
`~/burn-batch.csv`.

### Not in scope: identity

`burn-batch` clones and proves. It never stamps a hostname, a role or a
`config.txt` — which card becomes which player is per-engagement, and belongs in
that engagement's runbook. `sd-converge` is the no-reflash path for cards that
already have an identity.

### Status

**The phases that need no hardware are exercised; the card path is not proven
yet.** `--fsck-only` was rehearsed against a real three-partition loop-mounted
image (vfat repaired, rootfs checked-only, `/data` repaired), the parallel pool
was verified to cap and to complete every item, every refusal above was
triggered, and the verify *technique* was proved on a loop device: a card larger
than the image reads identical, and a single byte flipped 100 MB in is caught
with its offset.

What that leaves unproven is everything a card reader owns — serial resolution
across a real hub, the re-resolve after a reset, `dd` to a genuine card, and the
worn-card failure the `cmp` pass exists for. That is a bench session with the
reader and a lot of cards; until it has run, the fallback is the by-hand
procedure this tool was written from.
