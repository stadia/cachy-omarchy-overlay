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

# Fix round 2 residual: a timed-out retry (rc 4) must keep polling, not end
# the loop. Full 25.5s hang ceiling stays untested by ruling; this narrower
# PATH-scoped qs stub proves the loop guard itself. coo_quickshell_bin()
# resolves a bare `qs` name via command -v, so a prepended stub is enough
# (same PATH-isolation pattern as test_quickshell_detect.sh).
stub_dir="$COO_TEST_SANDBOX/qs-stub"
mkdir -p "$stub_dir"
stub_count="$stub_dir/count"
stub_hangs=2
cat > "$stub_dir/qs" <<'STUB'
#!/usr/bin/env bash
# Invocation 1: fail-fast (enter autostart retry). Next HANGS calls: hang
# until `timeout` kills us (rc 4). After that: answer ok.
set -uo pipefail
count_file=${COO_QS_STUB_COUNT:?}
hangs=${COO_QS_STUB_HANGS:?}
n=$(cat "$count_file")
n=$((n + 1))
printf '%s\n' "$n" > "$count_file"
if (( n == 1 )); then
  printf 'No running instances for "stub"\n'
  exit 255
fi
if (( n <= 1 + hangs )); then
  exec sleep infinity
fi
printf 'ok\n'
exit 0
STUB
chmod +x "$stub_dir/qs"

run_stub_ping() {
  local cli=$1
  # Reset counter for each run so red/green share the same stub script.
  printf '0\n' > "$stub_count"
  COO_SHELL_PATH="$REPO_ROOT/shell" \
  COO_IPC_TIMEOUT=0.3s \
  COO_IPC_RETRY_TIMEOUT=0.15s \
  COO_QS_STUB_COUNT="$stub_count" \
  COO_QS_STUB_HANGS="$stub_hangs" \
  PATH="$stub_dir:$PATH" \
  WAYLAND_DISPLAY=coo-nonexistent-display \
  "$cli" ping 2>&1
}

# Red: break the loop guard so rc 4 exits early → must fail "not responding".
# Copy must still resolve lib/ against the real repo: a naive cp into the
# sandbox makes SELF_DIR/REPO_ROOT point at /tmp and dies before the guard.
broken_cli="$COO_TEST_SANDBOX/coo-shell-broken-rc4"
if ! grep -qF '(( rc == 1 || rc == 4 )) || break' "$CLI"; then
  echo "fatal: expected rc-4 continue guard missing from coo-shell" >&2
  exit 1
fi
sed \
  -e "s|^SELF_DIR=.*|SELF_DIR=\"$REPO_ROOT/bin\"|" \
  -e "s|^REPO_ROOT=.*|REPO_ROOT=\"$REPO_ROOT\"|" \
  -e 's/(( rc == 1 || rc == 4 )) || break/(( rc == 1 )) || break/' \
  "$CLI" > "$broken_cli"
chmod +x "$broken_cli"
grep -qF '(( rc == 1 )) || break' "$broken_cli" || {
  echo "fatal: failed to inject broken rc-4 guard" >&2
  exit 1
}
SECONDS=0
out=$(run_stub_ping "$broken_cli"); code=$?
elapsed=$SECONDS
assert_eq "$code" "1" "broken rc-4 guard exits 1 (red)"
assert_contains "$out" "not responding" "broken rc-4 guard says not responding (red)"
[[ $elapsed -le 5 ]] && b=0 || b=1
assert_eq "$b" "0" "broken-guard stub run stays fast (took ${elapsed}s, expected <=5s)"

# Green: real CLI recovers after timed-out retries and returns ok.
SECONDS=0
out=$(run_stub_ping "$CLI"); code=$?
elapsed=$SECONDS
assert_eq "$code" "0" "rc-4 continue guard recovers after timed-out retries (green)"
assert_eq "$out" "ok" "rc-4 continue guard returns ok (green)"
[[ $elapsed -le 5 ]] && b=0 || b=1
assert_eq "$b" "0" "rc-4 stub recovery stays fast (took ${elapsed}s, expected <=5s)"

# No stub child may survive timeout --kill-after (never pkill; match our path).
leftover=0
while read -r pid; do
  [[ -n $pid ]] || continue
  leftover=1
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
done < <(pgrep -f "$stub_dir/qs" || true)
assert_eq "$leftover" "0" "qs stub left no leftover processes"

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
