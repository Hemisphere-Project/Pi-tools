#!/bin/bash
# upgrade.sh — the RE-RUNNABLE tail of rorw/install.sh.
#
#   ro/rw an installed box, then:   bash /opt/Pi-tools/rorw/upgrade.sh
#
# WHY THIS FILE EXISTS. The checkout is not the machine: a box deployed by
# `git pull` only never re-runs the installer, so an image-level rorw change
# (a new ro-assert timer, a changed logout hook) simply never reaches it.
# player-000 was found that way on the 7.3 golden review — installed at
# af6e1cd, still carrying the pre-51b425e logout bracket, a 40 KB root history
# and no ro-assert timer, all of it fixed by hand.
#
# And `install.sh` cannot be that path: it is NOT idempotent. It rewrites
# /etc/fstab from freshly detected partition UUIDs, re-appends its two lines to
# /root/.bashrc, and re-`mv`s the oh-my-bash log that is already a symlink.
# Re-running it on a field box is how you get a duplicated .bashrc and, on a
# machine whose partitions no longer probe the same way, an unbootable fstab.
#
# So the split is by IDEMPOTENCE, not by convenience. Everything here is
# `ln -sf`, `systemctl enable`, a marker-delimited block, or a write to a file
# this module owns outright — all safe to run any number of times. Everything
# that rewrites shared state stays in install.sh and runs exactly once.
# install.sh ends by calling this file, so there is ONE copy of the tail and it
# cannot drift.
#
# NOT carried here, on purpose: the /root/.bashrc lines (`source rorw.bashrc`
# + OSH_THEME). They are appended blind by install.sh, so re-applying them
# duplicates them; an installed box already has them.
#
# Usage:
#   upgrade.sh                run on an installed box; brackets the work rw...ro
#   upgrade.sh --installing   called by install.sh as its tail; NO bracket (see below)
#
# Exit 0 applied, 1 refused or failed.

set -u

BASEPATH="$(dirname "$(readlink -f "$0")")"

INSTALLING=
[ "${1:-}" = "--installing" ] && INSTALLING=1

# with_rw comes from the CHECKOUT, never from /usr/local/lib/pitools: that
# symlink is published at the end of this very script, so on a first install it
# does not exist yet. with_rw itself no-ops the bracket when `rw` is not on PATH
# (first install, root still writable) and brackets exactly one rw...ro pair
# when it is (upgrade on a read-only box).
# shellcheck source=with_rw.sh
source "$BASEPATH/with_rw.sh"

if [ "$(id -u)" -ne 0 ]; then
    echo "rorw/upgrade.sh: must run as root" >&2
    exit 1
fi

# /data must be REALLY mounted before anything below points at it. If it is not,
# the root history symlink and the fake clock land on the root filesystem and
# are silently shadowed the moment /data mounts for real — the same trap
# install.sh guards when it builds /data's skeleton.
if ! mountpoint -q /data; then
    echo "rorw/upgrade.sh: /data is not mounted — refusing (run install.sh first)" >&2
    exit 1
fi

apply() {

    #
    # fake-hwclock
    #

    systemctl disable systemd-timesyncd
    systemctl disable ntp

    ln -sf "$BASEPATH/fake-clock" /usr/local/bin/
    ln -sf "$BASEPATH/fake-clock.service" /etc/systemd/system/
    ln -sf "$BASEPATH/fake-clock-autosave.service" /etc/systemd/system/
    ln -sf "$BASEPATH/fake-clock-autosave.timer" /etc/systemd/system/

    systemctl daemon-reload
    systemctl enable fake-clock
    systemctl enable fake-clock-autosave.timer

    fake-clock save

    # /var/log lives on tmpfs and /var/backups on the ro root: log rotation
    # and dpkg db backups can only fail (found failing on both the N100 minis
    # and the RPi golden, 2026-07-22) — mask them.
    systemctl mask logrotate.service logrotate.timer 2>/dev/null
    systemctl disable --now dpkg-db-backup.timer 2>/dev/null
    systemctl mask dpkg-db-backup.service dpkg-db-backup.timer 2>/dev/null

    # /var/log is a bind of /tmp: rsyslog's tmpfiles rule (z /var/log 0775
    # root syslog) force-perms the shared inode at EVERY boot, silently
    # stripping /tmp's 1777 — which breaks apt's GPG sandbox (_apt can't
    # write temp files; fleet-wide, 2026-07-22). A z-rule in a file sorting
    # last re-asserts /tmp after rsyslog's.
    echo "z /tmp 1777 root root -" > /etc/tmpfiles.d/zz-pitools-tmp.conf

    # Root shell history lives on /data so `history -a` works on a read-only
    # root — the logout hook then needs NO rw/ro bracket. The old bracket was
    # the only runtime rw excursion in the stack, and its `ro` could lose the
    # transient remount-busy race and strand the box silently writable
    # (mini fleet, 2026-07-24). Never again: logout only appends history
    # (through the /data symlink) and saves the fake clock (/data too).
    mkdir -p /data/var
    if [ -f /root/.bash_history ] && [ ! -L /root/.bash_history ]; then
        cat /root/.bash_history >> /data/var/root.bash_history 2>/dev/null
        rm -f /root/.bash_history
    fi
    touch /data/var/root.bash_history
    ln -sf /data/var/root.bash_history /root/.bash_history

    # drop any previously-installed rw/ro logout bracket, then append the
    # marker-delimited hook (idempotent across reinstalls)
    if [ -f /etc/bash.bash_logout ]; then
        sed -i '/^if \[ "\$(id -u)" -eq 0 \]; then$/,/^fi$/d' /etc/bash.bash_logout
        sed -i '/^# >>> pitools rorw >>>$/,/^# <<< pitools rorw <<<$/d' /etc/bash.bash_logout
    fi
    echo '# >>> pitools rorw >>>
if [ "$(id -u)" -eq 0 ]; then
history -a
fake-clock save
fi
# <<< pitools rorw <<<
' >> /etc/bash.bash_logout

    # self-heal: any stray rw with no registered holder is remounted ro by
    # the ro-assert timer (3min after boot, then every 5min)
    ln -sf "$BASEPATH/ro-assert" /usr/local/bin/
    ln -sf "$BASEPATH/ro-assert.service" /etc/systemd/system/
    ln -sf "$BASEPATH/ro-assert.timer" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable ro-assert.timer
    systemctl start ro-assert.timer 2>/dev/null

    #
    # install succeeded — publish the toggle symlinks last, so
    # is_module_installed only sees rorw as "installed" once the whole thing
    # actually ran.
    #
    ln -sf "$BASEPATH/ro" /usr/local/bin/
    ln -sf "$BASEPATH/rw" /usr/local/bin/
    mkdir -p /usr/local/lib/pitools
    ln -sf "$BASEPATH/with_rw.sh" /usr/local/lib/pitools/
}

# The rw/ro bracket is for the UPGRADE path only, and `--installing` is not an
# optimisation — taking it during an install is actively wrong. rw/ro are
# reference-counted through a counter on /run that resets to 0 at boot, and 0
# *means* "root is read-only". During an install that invariant does not hold:
# the root is writable because the image made it so, not because anyone called
# `rw`, so the counter still reads 0. A bracket there would go 0->1 on entry and
# 1->0 on exit, and the exit would remount the root READ-ONLY in the middle of
# the installer. rorw is the FIRST module in the first group (setup/installer.py
# MODULE_GROUPS), so usbautomount, network-tools, webconf, audiohub and every
# other module after it would then install onto a read-only root.
#
# Reinstalls are what make this reachable: `rw` is only on PATH once rorw has
# been installed at least once, so a second install.sh run is exactly the case
# that would take the bracket.
#
# On the upgrade path the counter IS authoritative, and taking the bracket is
# the right thing even when the root is already writable: another holder
# (a with_rw service, an admin shell) is then registered, and `ro` correctly
# reports "staying RW" instead of remounting under their writes.
if [ -n "$INSTALLING" ]; then
    apply || { echo "RORW upgrade FAILED" >&2; exit 1; }
else
    with_rw apply || { echo "RORW upgrade FAILED" >&2; exit 1; }
fi

echo "RORW upgrade applied"
