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

# -q with no target/method at all must ALSO be silent (fix round 1, minor):
# the usage/help short-circuit used to call usage() unconditionally, so a
# bare -q (or -q -h) leaked the full help text to stdout despite promising
# "no output, always exit 0".
out=$(COO_NO_AUTOSTART=1 COO_SHELL_PATH="$REPO_ROOT/shell" \
      WAYLAND_DISPLAY=coo-nonexistent-display "$CLI" -q 2>&1); code=$?
assert_eq "$code" "0" "bare -q exits 0"
assert_eq "$out" "" "bare -q is silent (no usage text leaks through)"

# The bounded autostart-retry path (fix round 1, important): with no shell
# ever coming up and autostart NOT disabled, `qs` fails fast on every
# attempt (docs/QUICKSHELL_API.md §9 -- a missing instance is a fast
# failure, not a hang) so this should land near the 25 x 200ms = 5s typical
# ceiling from the retry loop's own comment, not the ~25.5s worst case and
# nowhere near the ~83s an unshortened per-retry timeout would have cost.
# 15s is a generous margin above the ~5s typical case (covers slow-CI
# jitter) while still catching a regression back toward an unbounded or
# multi-tens-of-seconds wait.
SECONDS=0
out=$(COO_SHELL_PATH="$REPO_ROOT/shell" \
      WAYLAND_DISPLAY=coo-nonexistent-display "$CLI" ping 2>&1); code=$?
elapsed=$SECONDS
assert_eq "$code" "1" "autostart retry with no shell still exits 1"
assert_contains "$out" "not running" "autostart retry with no shell says 'not running'"
[[ $elapsed -le 15 ]] && b=0 || b=1
assert_eq "$b" "0" "autostart retry loop is bounded (took ${elapsed}s, expected <=15s)"

# Against a live shell, ping and the test surface work end to end.
if coo_quickshell_bin >/dev/null && [[ -n ${WAYLAND_DISPLAY:-} ]]; then
  export COO_CONFIG_ROOT="$COO_TEST_SANDBOX/config"
  coo_test_pids=()
  cleanup() {
    local p
    for p in "${coo_test_pids[@]:-}"; do
      [[ -n $p ]] && { kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; }
    done
  }
  trap cleanup EXIT

  "$REPO_ROOT/dev/run-shell.sh" > "$COO_TEST_SANDBOX/shell.log" 2>&1 &
  shell_pid=$!
  coo_test_pids+=("$shell_pid")
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

  # Bounded retry actually RECOVERS a shell that comes up mid-wait (fix
  # round 1, important -- proves the shortened per-retry timeout does not
  # make the loop give up on a shell that is merely slow to start). Kill the
  # already-running instance first so this doesn't trivially pass against
  # the still-live one above, then poll until it's verifiably gone, then
  # launch a fresh instance after a deliberate 1s delay and confirm
  # `coo-shell ping` (autostart path, not -q so a real "ok"/error is
  # visible) still succeeds despite racing the delayed start.
  kill "$shell_pid" 2>/dev/null; wait "$shell_pid" 2>/dev/null
  # Bounded wait (30 x 200ms = 6s ceiling): confirm the killed instance is
  # actually gone from `qs`'s point of view before racing the delayed one,
  # so this doesn't trivially "recover" against a shell that never left.
  for _ in $(seq 1 30); do
    [[ $(COO_NO_AUTOSTART=1 "$CLI" ping 2>/dev/null) == "ok" ]] || break
    sleep 0.2
  done

  (
    sleep 1
    exec "$REPO_ROOT/dev/run-shell.sh"
  ) > "$COO_TEST_SANDBOX/shell-delayed.log" 2>&1 &
  delayed_pid=$!
  coo_test_pids+=("$delayed_pid")

  unset COO_NO_AUTOSTART
  SECONDS=0
  out=$("$CLI" ping 2>&1); code=$?
  elapsed=$SECONDS
  assert_eq "$code" "0" "retry loop recovers a shell that starts mid-wait"
  assert_eq "$out" "ok" "recovered ping returns ok"
  [[ $elapsed -le 15 ]] && b=0 || b=1
  assert_eq "$b" "0" "recovery still lands within the bounded ceiling (took ${elapsed}s, expected <=15s)"
else
  echo "note: skipping live-shell CLI assertions"
fi

exit "$ASSERT_FAILURES"
