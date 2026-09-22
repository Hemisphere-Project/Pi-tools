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
| `fleet-patch-hostapd.sh` | one-off: convert existing players from the NM/wpa_supplicant AP to hostapd, no reflash |
| `sd-converge` | bench SD carousel: converge player **cards** to this machine's checkouts, no network |

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

### Status

The reader, the ledger parser, the three states, `--only`, the refusals and both
transports are exercised — `--here` against controlled ledgers, and a timeout and
a dead ssh target both landing in `?`. **No detect line in
`fixtures/patch-ledger.example` has been run against a real player from this
repo**: the example rows are grounded on units this repo ships, not on a probed
card. The first run against a card is the one that proves the ledger, and the
tool is built so that run costs one command.
