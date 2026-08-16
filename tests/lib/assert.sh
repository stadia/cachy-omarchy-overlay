#!/usr/bin/env bash
# Minimal assertion helpers. Sourced by every tests/**/test_*.sh.
ASSERT_FAILURES=${ASSERT_FAILURES:-0}

assert_eq() {
  local actual="$1" expected="$2" label="$3"
  if [[ "$actual" == "$expected" ]]; then
    printf 'ok:   %s\n' "$label"
  else
    printf 'FAIL: %s\n      expected: %q\n      actual:   %q\n' "$label" "$expected" "$actual"
    ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    printf 'ok:   %s\n' "$label"
  else
    printf 'FAIL: %s\n      missing: %q\n      in:      %q\n' "$label" "$needle" "$haystack"
    ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
  fi
}

assert_file_exists() {
  local path="$1" label="$2"
  if [[ -e "$path" ]]; then
    printf 'ok:   %s\n' "$label"
  else
    printf 'FAIL: %s\n      no such path: %s\n' "$label" "$path"
    ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
  fi
}

assert_exit() {
  local expected="$1"; shift
  local label="$1"; shift
  local code=0
  "$@" >/dev/null 2>&1 || code=$?
  assert_eq "$code" "$expected" "$label (exit)"
}

# Live-runtime usability probe for tests that start `cachy-omarchy-shell --run`.
#
# `command -v` proves only that a binary is on PATH, not that it works.  The
# wrapper execs through `systemd-cat`, so in a sandbox/container without
# journald access systemd-cat fails ("Operation not permitted") and the
# Quickshell process dies before any IPC can answer.  A non-empty
# WAYLAND_DISPLAY likewise proves nothing until the socket actually exists.
# Tests gate on this probe instead of bare presence, so a broken environment is
# honestly noted/skipped rather than misjudged as runnable and failing for the
# wrong reason.
coo_live_runtime_usable() {
  command -v quickshell >/dev/null || return 1
  command -v qs >/dev/null || return 1
  command -v systemd-cat >/dev/null || return 1
  printf 'probe\n' | systemd-cat -t coo-live-runtime-probe >/dev/null 2>&1 || return 1
  [[ -n ${WAYLAND_DISPLAY:-} ]] || return 1
  [[ -S ${XDG_RUNTIME_DIR:-}/$WAYLAND_DISPLAY ]] || return 1
}
