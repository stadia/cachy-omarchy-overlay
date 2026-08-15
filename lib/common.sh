#!/usr/bin/env bash
# Shared constants and helpers. Sourced, never executed.

COO_NAME="cachy-omarchy-overlay"
COO_MARKER_BEGIN="# >>> cachy-omarchy-overlay >>>"
COO_MARKER_END="# <<< cachy-omarchy-overlay <<<"
COO_VERBOSE=${COO_VERBOSE:-0}

log()  { printf '%s\n' "$*" >&2; }
vlog() { (( COO_VERBOSE )) && printf 'debug: %s\n' "$*" >&2; return 0; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

have_cmd() { command -v "$1" >/dev/null 2>&1; }
