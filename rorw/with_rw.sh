#!/bin/bash
# Shared RW/RO safety wrapper for Pi-tools modules.
# Source this file, then use with_rw to run commands on a read-write filesystem.
#
# Usage:
#   source /usr/local/lib/pitools/with_rw.sh
#   with_rw "sed -i 's/foo/bar/' /etc/something && sync"
#
# rw/ro are reference-counted (see the `rw` script), so nested with_rw calls and
# concurrent callers/services are safe — each with_rw brackets exactly one
# rw...ro pair and the counter serializes the actual remounts.
# If rorw is not installed, the command runs directly.

with_rw() {
    local cmd="$1"
    local rc=0

    if ! command -v rw >/dev/null 2>&1; then
        eval "$cmd"
        return $?
    fi

    rw || { echo "[with_rw] ERROR: failed to switch to read-write mode" >&2; return 1; }

    # Run the snippet in a subshell: an `exit` inside it exits only the subshell,
    # so our matching `ro` always runs (balanced with the `rw` above), and we
    # never install an EXIT trap that would clobber the caller's own traps.
    ( eval "$cmd" )
    rc=$?

    sync
    ro >/dev/null 2>&1 || true
    return $rc
}
