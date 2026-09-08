# bench/ — laptop- and bench-side tools

Nothing in this directory is installed on a player. These are the tools you run
from **your own machine** against a player, a card, or a whole fleet. Module code
that runs *on* the Pi lives in the module directories (`network-tools/`,
`audiohub/`, …); anything that needs a laptop, a card reader or a radio lives
here.

| tool | what it is for |
|---|---|
| `fleet-run` + `fleet-lib.sh` | walk a roster of player **hotspots**, run one command on each, skip the dead ones |
| `fleet-patch-hostapd.sh` | one-off: convert existing players from the NM/wpa_supplicant AP to hostapd, no reflash |
| `sd-converge` | bench SD carousel: converge player **cards** to this machine's checkouts, no network |

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
