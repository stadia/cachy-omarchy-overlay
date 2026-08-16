#!/usr/bin/env bash
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/lib/common.sh"
source "$REPO_ROOT/lib/env.sh"

CLI="$REPO_ROOT/bin/coo-shell"
assert_file_exists "$CLI" "coo-shell exists"
[[ -x $CLI ]] && x=0 || x=1
assert_eq "$x" "0" "coo-shell is executable"

# Help works with no shell running and no Wayland session.
out=$("$CLI" --help 2>&1); code=$?
assert_eq "$code" "0" "--help exits 0"
assert_contains "$out" "coo-shell" "--help mentions the command"
assert_contains "$out" "launcher toggle" "--help documents launcher toggle"

# With no shell running, autostart disabled, a ping must fail loudly.
out=$(COO_NO_AUTOSTART=1 COO_SHELL_PATH="$REPO_ROOT/shell" \
      WAYLAND_DISPLAY=coo-nonexistent-display "$CLI" ping 2>&1); code=$?
assert_eq "$code" "1" "ping with no shell exits 1"
assert_contains "$out" "not running" "ping with no shell says 'not running'"

# -q makes the same call silent and successful.
out=$(COO_NO_AUTOSTART=1 COO_SHELL_PATH="$REPO_ROOT/shell" \
      WAYLAND_DISPLAY=coo-nonexistent-display "$CLI" -q ping 2>&1); code=$?
assert_eq "$code" "0" "-q ping exits 0"
assert_eq "$out" "" "-q ping is silent"

# Against a live shell, ping and the test surface work end to end.
if coo_quickshell_bin >/dev/null && [[ -n ${WAYLAND_DISPLAY:-} ]]; then
  export COO_CONFIG_ROOT="$COO_TEST_SANDBOX/config"
  "$REPO_ROOT/dev/run-shell.sh" > "$COO_TEST_SANDBOX/shell.log" 2>&1 &
  shell_pid=$!
  trap 'kill "$shell_pid" 2>/dev/null; wait "$shell_pid" 2>/dev/null' EXIT
  export COO_SHELL_PATH="$REPO_ROOT/shell" COO_NO_AUTOSTART=1
  for _ in $(seq 1 30); do [[ $("$CLI" -q ping) == "ok" ]] && break; sleep 0.2; done

  assert_eq "$("$CLI" ping)"        "ok"     "live ping"
  assert_eq "$("$CLI" test open)"   "ok"     "live test open"
  assert_eq "$("$CLI" test state)"  "open"   "live test state"
  assert_eq "$("$CLI" test close)"  "ok"     "live test close"

  # Unknown target/method must be exit 1 even though qs exits 0.
  out=$("$CLI" nosuchtarget nosuchmethod 2>&1); code=$?
  assert_eq "$code" "1" "unknown target exits 1"
  assert_contains "$out" "not found" "unknown target message"
else
  echo "note: skipping live-shell CLI assertions"
fi

exit "$ASSERT_FAILURES"
