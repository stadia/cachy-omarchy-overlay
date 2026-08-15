#!/usr/bin/env bash
# Boots the repo host via dev/run-shell.sh and pings it over IPC.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/lib/common.sh"
source "$REPO_ROOT/lib/env.sh"

if ! coo_quickshell_bin >/dev/null; then echo "skip: quickshell not installed"; exit 0; fi
if [[ -z ${WAYLAND_DISPLAY:-} ]]; then echo "skip: no WAYLAND_DISPLAY"; exit 0; fi

QS=$(coo_quickshell_bin)
export COO_CONFIG_ROOT="$COO_TEST_SANDBOX/config"

"$REPO_ROOT/dev/run-shell.sh" > "$COO_TEST_SANDBOX/shell.log" 2>&1 &
shell_pid=$!
cleanup() { kill "$shell_pid" 2>/dev/null; wait "$shell_pid" 2>/dev/null; }
trap cleanup EXIT

# Bounded wait: 30 x 200ms = 6s ceiling. Never unbounded (SPEC 19.3).
out=""
for _ in $(seq 1 30); do
  out=$(timeout 2s "$QS" ipc -n -p "$REPO_ROOT/shell" call -- shell ping 2>/dev/null)
  [[ $out == "ok" ]] && break
  sleep 0.2
done

assert_eq "$out" "ok" "shell ping returns ok"
if [[ $out != "ok" ]]; then
  printf '      --- shell.log tail ---\n'; tail -30 "$COO_TEST_SANDBOX/shell.log" | sed 's/^/      /'
fi

ver=$(timeout 2s "$QS" ipc -n -p "$REPO_ROOT/shell" call -- shell version 2>/dev/null)
assert_contains "$ver" "0." "shell version returns a version: $ver"

exit "$ASSERT_FAILURES"
