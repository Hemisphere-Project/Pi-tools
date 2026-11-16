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
| `probe-level` | which patches does this player actually carry? one `y`/`n` per patch and a `missing:` line |
| `module-level` | which version of each module does this player carry? one row per module and a `drift:` line |
| `precheck` | one screen per player, read-only: card health and **write load**, journal, HPlayer2 defects and sync state, watchdog actions per day, unexplained warnings |
| `eth-sync` | move one player's sync group from the wlan0 dongle to **eth0** (master `AP`, slaves `STA`), no reflash |
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

## `probe-level` — which patches does this player actually carry?

A fleet that has been patched in the field for a month is not at one software
level; it is at N levels, and nobody can name them from memory. `probe-level`
reads a **ledger** of patches, runs every detection in **one** session on the
box, and answers in the only form that is useful at 1am on site:

```sh
./bench/probe-level -t root@10.0.0.1
```

```
ID     HAVE  GOLDEN-SINCE  PATCH
P1     y     7.3           hdmi-rehandshake v2 (the late re-handshake pass)
P2     y     7.3           blackbox state logger
P3     n     7.3           blackbox persistent journal on /data
P5     ?     -             linkwatch sync-link watchdog

have: 2 of 4
unread: P5
missing: P3 — and 1 of 4 could not be read, so this is not a full answer
```

```sh
./bench/probe-level --here                       # you are on the player already
./bench/probe-level --only P5,P8                 # just these
./bench/probe-level --dry-run -l fixtures/patch-ledger.example   # no player needed
./fleet-run --local -- ./bench/probe-level -t %t -q              # the whole fleet
```

Exit `0` nothing missing and nothing unread · `1` something missing · `2` could
not run, or could not read.

### `?` is not `n`, and that is the whole design

A detect command's exit code is the answer, and it has **three** outcomes:

| exit | column | means |
|---|---|---|
| `0` | `y` | the patch is there |
| `1` | `n` | the patch is not there |
| anything else | `?` | **could not read** — the command broke, timed out (`124`), or the box never answered |

A probe that collapses the third into `n` sends someone to re-apply a patch that
is already there. Collapsing it the other way is worse: an unread fleet reads as
a clean one. So `missing: none` is printed **only** when every patch was read
*and* every one answered yes, and it is always the last line — it is the line
that gets grepped, pasted into a note, and quoted a week later.

A dead transport is therefore every patch *unread*, never every patch missing.
`fixtures/patch-ledger.example` carries a deliberately unrunnable row for this:
the first time you point the tool at a new ledger, that row must come back `?`.
If it ever shows `n`, the tool is lying about every other row too.

### The ledger is not in this repo

Same split as `fleet-run` and its roster, for the same reason: **which patches a
given installation is supposed to carry is engagement state, not component
state.** This repo ships the reader and a worked example; the real ledger lives
with the fleet it describes, and the ids are that ledger's — a fleet's `P7` is
whatever its own ledger says `P7` is, and the example's numbering is nobody's.

Search order when `-l` is not given: `./patch-ledger`,
`~/.config/pitools/patch-ledger`, `bench/patch-ledger`.

Five `|` separated fields, the detect command last so it can contain `|`
(pipelines are the normal case):

```
<id> | <title> | <golden-since> | <apply> | <detect command>
```

Only a line whose first non-blank character is `#` is a comment — a trailing `#`
is not, because detect commands contain them. `golden-since` is what makes a
missing patch readable: older card than that, expected; newer card than that,
**drift**, which is the case worth a phone call. `apply` is printed under the
missing list, so the answer and the act land on one screen.

### Writing a detect command

Ask about the **box**, not about the checkout. `git -C /opt/Pi-tools merge-base
--is-ancestor <sha> HEAD` proves the code is on disk and proves nothing about
whether the unit was reloaded and restarted — which is exactly the live-box
deploy gotcha in `AUDIT-2026.md`. Prefer a question about the installed
artefact (`systemctl is-enabled <unit>`, a marker `grep` in the installed
script), and keep the checkout form for patches that really are just files.

Two traps worth knowing before they cost a round:

* **`systemctl is-enabled` exits 1 for `masked` and for `disabled` alike.** For a
  unit that must be masked, compare the word: `[ "$(systemctl is-enabled
  man-db.timer 2>/dev/null)" = masked ]`.
* **Grep a marker, not a version.** The marker is what the fix *is*, and it
  survives someone bumping a number.

And one that costs the whole answer, not just a round: **a module that was never
installed is the most common negative there is, and the plain detect commands
above do not land it on `n`.** `systemctl is-enabled` exits **4**, not 1, for a
unit it has never heard of; `grep` exits **2** on a file that is not there; `git
-C` exits **128** on a directory that is not there. None of 4/2/128 is 0 or 1, so
every one of them lands in `?` — measured on dev37, `probe-level --here` against
`fixtures/patch-ledger.example` before this fix came back `missing: UNKNOWN`, not
naming a single one of the (correctly) absent modules (pi-tools#t-044). `probe-
level` exports a helper for exactly this, into every detect command's own
execution context:

```sh
systemctl is-enabled some.timer >/dev/null 2>&1 || absent_on 4
```

`absent_on CODE...` reads the exit code of the command that just failed: a code
in its list re-exits as 1 (`n`); anything else re-exits **unchanged**, so an
undeclared code — 127 no such command, 124 timeout, a dead transport — still
reaches `?`. Nothing is mapped unless a row asks for it, and asking is a row's
own call: `fixtures/patch-ledger.example`'s P1/P2/P3/P5/P6 (`is-enabled`/4), P8
(`grep`/2) and P9 (`git -C`/128) all use it now; P4's check does not end at the
enabled bit, so it maps the same code inline instead — see its comment.

### Status

The reader, the ledger parser, the three states, `--only`, the refusals and both
transports are exercised — `--here` against controlled ledgers, and a timeout and
a dead ssh target both landing in `?`. `absent_on` is exercised the same way,
`--here` on dev37 against `fixtures/patch-ledger.example` (no Pi-tools module
installed there): before the fix, `missing: UNKNOWN — 8 of 10 could not be
read`; after, `missing: P1 P2 P3 P4 P5 P6 P7 P8 P9` with only the deliberately
unrunnable `P99` left `unread`. **No detect line in
`fixtures/patch-ledger.example` has been run against a real player from this
repo**: the example rows are grounded on units this repo ships, not on a probed
card. The first run against a card is the one that proves the ledger, and the
tool is built so that run costs one command.

---

## `module-level` — which version of each module does this player carry?

On 22/09 `usbfix` was corrected three times while a six-player round was in
flight. The deployers install one module each, so every box ended the day on
whatever `usbfix` was when *its* pass ran — and nothing on the box said which.
It was caught by hand, a `grep` per guard per player (pi-tools#t-047).

So every install pass now leaves a receipt. `setup/module-manifest record`
rewrites the module's line in the box's `/etc/pi-tools-modules.txt`; each
`install.sh` calls it, and `setup/installer.py` calls it for the modules it
installs itself:

```
usbfix 12570ed434da 2026-09-22T14:03:11+02:00 eaf9b35+dirty
<module> <fingerprint> <installed-at> <source>
```

`module-level` reads that file and compares every module with **this clone** —
the tree the deployers copy from:

```sh
./bench/module-level                          # the player on this hotspot
./bench/module-level usbfix blackbox          # just these
./bench/module-level -m <card>/etc/pi-tools-modules.txt   # a card in a reader
./fleet-run --local -- ./bench/module-level -t %t -q      # the whole fleet
```

```
MODULE             STATE  INSTALLED        BOX CARRIES                          CLONE
blackbox           =      2026-09-22 11:00 c9ed73f                              c9ed73f
usbfix             drift  2026-09-22 14:03 51142e7 2026-09-22                   c9ed73f
linkwatch          ?      -                not recorded on the box              c9ed73f

recorded: 2 of 3
unread: linkwatch
drift: usbfix — and 1 of 3 could not be read, so this is not a full answer
```

Exit `0` no drift and nothing unread · `1` drift · `2` could not run, or could
not read. `drift:` is always the last line, for the same reason as
`probe-level`'s `missing:`.

### The fingerprint is content, not a commit

The deployers copy a laptop's **working tree** onto the box (`scp`, or `cp`
over `/opt/Pi-tools/<module>`), so the box's own `git HEAD` says nothing about
what a module directory holds, and the laptop's tree may not even be
committed. The fingerprint is therefore a hash of the module directory's
**content**: sha1 over the sorted `<git-blob-id> <path>` lines of its files.
The same content always gives the same fingerprint, so `module-level` can walk
this clone's history (`git ls-tree` hands over the blob ids, nothing is
re-hashed) and **name the commit** a box's version came from — `51142e7`
above. A box whose version is in no commit here was installed from somebody's
uncommitted tree, and the row says so, along with the sha the box's checkout
reported (`source`, `+dirty` when the module directory differed from it).

Files are listed the way git sees the directory — tracked plus untracked
files that are not ignored, or everything but `__pycache__`, `node_modules`,
`.venv` and `*.pyc` outside a checkout. A stale file a `cp` left behind in a
module directory is part of the content, so it reads as drift: that is a real
difference, just a harmless one.

### `?` is not `=`

A module the box never recorded is `?` — installed before the manifest
existed, or by a deployer that bypasses `install.sh` (the 22/09
`usbfix-deploy` copied the bare script and wrote its own units). A box with no
manifest at all is `drift: UNKNOWN`. Neither is ever read as a match: an
unread fleet must not look like a converged one. `bench/verify` refuses a
`script = yes` module whose `install.sh` does not record itself, so the
manifest cannot decay one new module at a time.

The receipt is written only when the root is writable (install passes run
under `rw` anyway), and a failure to write it warns and never fails the
install: a module must not refuse to install over its own receipt.

### Status

Recording, the three states and the commit lookup are exercised on dev37
against this repo's own history: manifests built from the 22/09 shas
(`1fb89ce`, `51142e7`, `eaf9b35`) resolve to exactly those commits, a module
installed from an uncommitted tree reads `=` while the tree is unchanged and
`not in this clone` once it is reverted, and every `install.sh`'s record line
was run as written. On a real player (bench-02, a RastaOS-7.4 card, 14/11):
`usbfix/install.sh` from a clean checkout of this branch printed `usbfix:
recorded d30b8c7d6f8b (a14d08b)`, the fingerprint the laptop computes for
`a14d08b`; `module-level` then read `usbfix =` and `linkwatch ?` (exit 2), and
against a clone at `c9ed73f` read `usbfix drift`, naming `a14d08b` (exit 1).

---

## `precheck` — is what this player logs coherent?

```sh
./bench/precheck -t root@10.0.0.1           # one player
./bench/precheck --here --days 1            # on the player itself
./bench/fleet-run --local -- ./bench/precheck -t %t     # the whole fleet
```

Read-only, one ssh session, six to ten lines per player: the card (name, date,
serial, `/data` filesystem state, mmc errors, and the **MB written to `/data`
this boot, per day**), where the journal lives and how big it is, HPlayer2's
level, restarts and the known defects counted over the window (`--days`,
default 3), the sync group right now (slave: multicast membership, last drift
window, link; master: stations, leases, linked peers), watchdog actions and
beacon-loss bursts per day, and the top warning kinds that no known pattern
explains.

It is the field kit's `precheck.sh` (Biennale 2026, run on every player before
the 21/09 pack). What it measures is unchanged; what tied it to one show is
gone: the HPlayer2 unit is found (`--unit` overrides), the boot partition is
`/boot` or `/boot/firmware` as `setnet` resolves it, and `/data`'s partition is
found from its mountpoint instead of assumed to be `mmcblk0p3`.

What it cannot say is **who** writes: the write load is a total for the boot.
Naming the process takes per-process counters read over a day (pi-tools#t-037).
On an x86 box the card line reads blank.

## `eth-sync` — the sync group over eth0 instead of the dongle

```sh
./bench/eth-sync -n -r AP                                  # show the program, touch nothing
./bench/eth-sync -r AP  -e player-000 -t root@10.0.0.1     # the master
./bench/fleet-run -r slaves.roster --local -- ./bench/eth-sync -r STA -e %h -t %t
```

Same layout as the network-tools sync templates: master `eth0-sync-AP` (static
`10.1.0.1`, dnsmasq serves the /24), slaves `eth0-sync-STA` (DHCP). On the box
it archives the wifi sync marker and the golden's `eth0-dhcp` to
`wifi/_disabled/`, drops the `eth0-sync-<ROLE>` marker in, removes
NetworkManager's copies of the two archived profiles (`setnet` is additive and
would keep them), runs `setnet`, and reports eth0's address and carrier.

* **The template**: the card's own `wifi/_disabled/` copy first, else
  `/opt/Pi-tools/network-tools/profiles/_disabled/` — an installer-made card has
  no `_disabled/` on its boot partition (`network-tools/README.md`). Neither →
  abort, nothing touched.
* **`-e NAME`** refuses unless the box's hostname is `NAME`. Every player answers
  on `10.0.0.1` and this tool writes; under `fleet-run`, pass `-e %h`.
* **Reach the player over its hotspot, not over eth0** — the run re-addresses
  eth0 and a session riding it dies before the report.
* **HPlayer2 is not restarted**: it reads its role at start. Restart it (or
  reboot) once every player of the group is switched.
* **Back to wifi** is the same move mirrored, by hand: archive
  `eth0-sync-<ROLE>`, restore `wlan0-sync-<ROLE>` and `eth0-dhcp`, `setnet`.

It is the field kit's `on-player-eth-sync.sh` (Biennale 2026), with the same
steps; the template fallback and `-e` are new.

### Status (both)

The two on-box programs ran on the Biennale fleet as field scripts. The folded
versions are exercised **without a player only**: argument refusals, `--dry-run`,
`precheck --here` on a Debian VM (every line prints, blank where there is no
card), a dead ssh target landing on exit 2, and `eth-sync`'s program run in a
sandbox tree with stubbed system tools — golden card, installer card (template
from `/opt/Pi-tools`), no template (abort, untouched), wrong host (refused,
untouched). **Their first run against a real player is the proof still owed.**

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
   the vfat dirty bit set on `/boot`. Each filesystem is **checked first, with
   the read-only tools** — `fsck.fat -n`; for ext4 the superblock (an
   unreplayed journal, a state other than `clean`) and then `e2fsck -fn`, which
   alone exits 0 on both — and **repaired only on a finding**: the boot vfat and
   the **last** ext4 (`/data`). A repair run on a clean filesystem still writes
   it (`e2fsck -fy` stamps the superblock's last-checked time), so until
   pi-tools#t-062 a golden changed sha256 and mtime at every burn. Now a clean
   golden comes out byte-identical and the phase says `image clean, not
   written`. Every other ext4 is checked and never written — a golden's rootfs
   is the thing under test, not something to silently repair; a finding there
   is a warning. `--fsck-only` runs this phase alone, which is worth doing once
   to an image you are about to archive.
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

Phase 1 has its own desk test, `sudo bash bench/burn-fsck-desk.sh` (root for
`losetup`; 49 checks). On a RastaOS-shaped image file, a clean golden keeps its
sha256, its mtime and `/data`'s last-checked time. A dirty bit, an unreplayed
journal, a superblock left not clean and freed blocks are each repaired, the
other partitions' bytes untouched, and the next run writes nothing. A journal
on the rootfs is a warning and is never written. Then it burns for real —
phases 1 to 4, `dd` and `cmp` — onto a 300 MB `scsi_debug` RAM card it creates
and removes, and checks the golden is unchanged after the burn.

What that leaves unproven is everything a card reader owns — serial resolution
across a real hub, the re-resolve after a reset, `dd` to a genuine card, and the
worn-card failure the `cmp` pass exists for. That is a bench session with the
reader and a lot of cards; until it has run, the fallback is the by-hand
procedure this tool was written from.

## `test-rastaos-update` — the updater, exercised without a box

`setup/rastaos-update <tag>` converges a player's `/opt/Pi-tools` checkout to a release tag, from
origin or (`--bundle FILE`) an offline git bundle. It writes `/etc/rastaos-release` (the receipt:
tag, full commit, when, from where, what it replaced) and `refs/rastaos/rollback` in the checkout
(the rollback point, which also keeps image-only commits from `git gc`). `--rollback` swaps back,
`--status` reads both, `-n` changes nothing. A box already on the tag with a matching receipt gets
`already at <tag>` and **no write at all** — that is what makes a second run provably a no-op.
It refuses (exit 3, nothing changed) local edits in the checkout and a tag that moved: a field
hotfix is a new tag.

`bench/test-rastaos-update` builds a throwaway origin and checkout and drives every one of those
paths, with `/etc` and `/run` redirected. It does not prove `rw`/`ro` on a real
read-only root, nor anything on hardware — that is the bench proof on bench-01 (pi-tools#t-057).

After a move the updater runs `setup/converge.py` from the new checkout: the box's OWN modules
(named in `/etc/pi-tools-modules.txt`, or with a declared bin/unit present), never one it did not
have, never one its platform cannot run (`platforms = pi` is skipped on an N100). A fully linked
standard module needs nothing (its symlinks already carry the new code); a partly linked one is
reinstalled. A script module runs its own `[install] upgrade` script when it declares one (with
`--converging`: the updater holds `rw`, so the script takes no rw...ro bracket of its own), else
its `install.sh` again if its module.ini says `[install] rerun = yes`, else it is `held`.
`python3 setup/converge.py --plan` prints that table and changes nothing. A failed module writes
`MODULES=failed` in the receipt (exit 6), and the next run converges again instead of saying
`already at`.

Which script module gets what, and why (each module.ini says it in a comment over the key):

| module | on a tag move | why |
|---|---|---|
| rorw | `upgrade.sh --converging` | install.sh runs ONCE: fstab from freshly probed UUIDs, cmdline.txt seds, .bashrc appends. upgrade.sh is its re-runnable tail (fake clock, logout hook, ro-assert, toggles) |
| linkwatch, usbfix | install.sh again | their scripts are COPIED to /usr/local/sbin — a re-run is the only way the tag reaches them. usbfix remembers `--no-rsyslog` in /etc/default/usbfix |
| audiohub | install.sh again | rewrites its graph (/etc/asound.conf), keeps /etc/audiohub.conf; restarts the 3 forwarders one at a time — a playing box blips |
| blackbox, flightbox, hdmi-rehandshake, splash | install.sh again | `ln -sf`, enable, files rewritten whole; splash x86 also re-runs update-grub + update-initramfs |
| tailscale | held | install.sh pipes the vendor installer from the network: fails offline, and would move tailscale itself to latest. Its wrapper is linked, so the tag still reaches it |

`bench/verify` lints the two keys (`rerun` a boolean, `upgrade` an existing file, both on a
`script = yes` module only): a `rerun` converge cannot parse would abort the whole convergence.

### Status

pi-tools#t-057, slices 1-3: checkout, receipt, rollback point, module convergence, every script
module marked (56 checks, the last five against the real module set). What a desk cannot prove is
the bench proof on bench-01 — `rastaos-update` run twice, the second changing nothing, on a real
read-only root with the real installers.
