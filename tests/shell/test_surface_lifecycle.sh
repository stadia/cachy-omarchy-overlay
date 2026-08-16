#!/usr/bin/env bash
# Lifecycle test for the Milestone 1 test surface: open/close/toggle/state
# over IPC (target "test"). This is the exact open/close/toggle/state shape
# Task 7's CLI and Milestone 2's launcher/keybindings targets reuse verbatim,
# so its assertions are the contract.
#
# A boolean IPC flag flipping is not proof the LayerShell surface actually
# rendered -- a PanelWindow that fails to construct (wrong attached-property
# name, missing import) would still let shell.testOpen flip and state()
# report "open" while nothing appears on screen. So beyond the twelve base
# assertions this also checks, when `hyprctl` is available, that a real
# layer-shell surface with namespace "coo-test" appears in `hyprctl layers`
# while open and disappears while closed, and that shell.log carries no QML
# construction/runtime error before or after the run.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/lib/common.sh"
source "$REPO_ROOT/lib/env.sh"

if ! coo_quickshell_bin >/dev/null; then echo "skip: quickshell not installed"; exit 0; fi
if [[ -z ${WAYLAND_DISPLAY:-} ]]; then echo "skip: no WAYLAND_DISPLAY"; exit 0; fi

QS=$(coo_quickshell_bin)
export COO_CONFIG_ROOT="$COO_TEST_SANDBOX/config"
ipc() { timeout 2s "$QS" ipc -n -p "$REPO_ROOT/shell" call -- "$@" 2>/dev/null; }

HYPRCTL=$(command -v hyprctl || true)
if [[ -z $HYPRCTL ]]; then
  printf 'note: hyprctl not found, skipping layer-render assertions (IPC-level assertions still run)\n'
fi

log="$COO_TEST_SANDBOX/shell.log"
"$REPO_ROOT/dev/run-shell.sh" > "$log" 2>&1 &
shell_pid=$!
trap 'kill "$shell_pid" 2>/dev/null; wait "$shell_pid" 2>/dev/null' EXIT

for _ in $(seq 1 30); do [[ $(ipc shell ping) == "ok" ]] && break; sleep 0.2; done

# Bounded wait (SPEC 19.3): poll `hyprctl layers` for the coo-test namespace
# until it matches the wanted presence, or give up after ~2s. Proves the
# PanelWindow actually became a live layer-shell surface, not just that the
# testOpen boolean flipped.
layer_state() {
  local want=$1 cur i
  for i in $(seq 1 20); do
    if [[ -n $HYPRCTL ]] && "$HYPRCTL" layers 2>/dev/null | grep -q 'namespace: coo-test'; then
      cur="visible"
    else
      cur="hidden"
    fi
    [[ $cur == "$want" ]] && { printf '%s\n' "$cur"; return; }
    sleep 0.1
  done
  printf '%s\n' "$cur"
}

assert_eq "$(ipc test state)"  "closed" "starts closed"
if [[ -n $HYPRCTL ]]; then
  assert_eq "$(layer_state hidden)" "hidden" "no coo-test layer before open"
fi

assert_eq "$(ipc test open)"   "ok"     "open returns ok"
assert_eq "$(ipc test state)"  "open"   "state is open after open"
if [[ -n $HYPRCTL ]]; then
  assert_eq "$(layer_state visible)" "visible" "coo-test layer actually renders after open"
fi

assert_eq "$(ipc test open)"   "ok"     "open is idempotent"
assert_eq "$(ipc test state)"  "open"   "still open after second open"

assert_eq "$(ipc test close)"  "ok"     "close returns ok"
assert_eq "$(ipc test state)"  "closed" "state is closed after close"
if [[ -n $HYPRCTL ]]; then
  assert_eq "$(layer_state hidden)" "hidden" "coo-test layer disappears after close"
fi

assert_eq "$(ipc test close)"  "ok"     "close is idempotent"

assert_eq "$(ipc test toggle)" "ok"     "toggle returns ok"
assert_eq "$(ipc test state)"  "open"   "toggle from closed opens"
if [[ -n $HYPRCTL ]]; then
  assert_eq "$(layer_state visible)" "visible" "coo-test layer renders after toggle-open"
fi

assert_eq "$(ipc test toggle)" "ok"     "toggle returns ok again"
assert_eq "$(ipc test state)"  "closed" "toggle from open closes"
if [[ -n $HYPRCTL ]]; then
  assert_eq "$(layer_state hidden)" "hidden" "coo-test layer disappears after toggle-close"
fi

# Log health: a wrong attached-property name or a missing import fails
# silently as far as the boolean/IPC contract is concerned but still logs a
# QML error. Catch that here rather than letting the assertions above pass
# on a surface that never actually rendered.
body=$(cat "$log" 2>/dev/null || true)
errors=$(printf '%s' "$body" | grep -icE \
  'TypeError|ReferenceError|is not a type|Cannot assign to non-existent property|Invalid property assignment|Unable to assign|is not available|Binding loop detected' \
  || true)
assert_eq "${errors:-0}" "0" "shell.log has no QML construction/runtime errors"

if [[ $ASSERT_FAILURES -gt 0 ]]; then
  printf '      --- shell.log tail ---\n'; tail -40 "$log" | sed 's/^/      /'
fi

exit "$ASSERT_FAILURES"
