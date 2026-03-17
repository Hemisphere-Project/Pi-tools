#!/bin/bash
# Shared RW/RO safety wrapper for Pi-tools modules.
# Source this file, then use with_rw to run commands on a read-write filesystem.
#
# Usage:
#   source /usr/local/lib/pitools/with_rw.sh
#   with_rw "sed -i 's/foo/bar/' /etc/something && sync"
#
# Guarantees RO is restored even on error.
# If rorw is not installed, commands run directly.

_PITOOLS_RW_ENGAGED=false

with_rw() {
    local cmd="$1"
    local rc=0

    if command -v rw >/dev/null 2>&1; then
        if ! $_PITOOLS_RW_ENGAGED; then
            rw || { echo "[with_rw] ERROR: failed to switch to read-write mode" >&2; return 1; }
            _PITOOLS_RW_ENGAGED=true
            trap '_pitools_restore_ro' EXIT INT TERM
        fi
    fi

    eval "$cmd" || rc=$?

    if $_PITOOLS_RW_ENGAGED; then
        sync
        ro || true
        _PITOOLS_RW_ENGAGED=false
        trap - EXIT INT TERM
    fi

    return $rc
}

_pitools_restore_ro() {
    if $_PITOOLS_RW_ENGAGED; then
        sync 2>/dev/null
        ro 2>/dev/null || true
        _PITOOLS_RW_ENGAGED=false
    fi
}
