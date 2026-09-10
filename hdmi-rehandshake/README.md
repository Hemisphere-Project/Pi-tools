# hdmi-rehandshake

A boot-time oneshot that re-negotiates the HDMI link with the **explicit** mode found in
`config.txt` (`tvservice -e "<CEA|DMT> <mode> <HDMI|DVI>"`), before `starter.service` launches
the player.

## Why

With `hdmi_force_hotplug=1` the firmware drives the link the instant the Pi boots. A TV powered
at the same moment — every venue's morning switch-on — can fail its first evaluation and latch
*"Mode non pris en charge"* on a mode it accepts. Seen on Samsung SyncMasters (CEA 16) and Samsung
28" sets, KARIKIS and LEA fleets, 2026-09-10. The only thing that cleared them was `tvservice -e`
with explicit settings, which powers the output off and on with the mode spelled out. Doing that
once at boot cures the boot path the same way; a TV switched on later negotiates against a stable
signal and needs nothing.

## What it does

- reads `hdmi_group` / `hdmi_mode` from the `[pi3]` block of `/boot/config.txt` (falls back to the
  first global ones), `hdmi_drive=1` → DVI signalling;
- no explicit mode (firmware auto from EDID) → exits 0, touches nothing;
- waits 3 s, `tvservice -e`, wakes the framebuffer (`fbset` depth dance), prints `tvservice -s`.

Cost: one blink of the screen ~3 s into boot. Legacy (dispmanx) display stack only — exits 0
where `tvservice` does not exist.

## Later

A hotplug listener (`tvservice -M`) re-asserting the mode on every attach event, plus re-asserts
at 15 s and 45 s, would also cover TVs slower than the Pi and TVs cycled during the day.
