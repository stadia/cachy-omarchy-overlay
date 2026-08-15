#!/usr/bin/env bash
# Regression test for shell/services/Config.qml's get(): a path that runs
# through a non-object leaf (string/number/boolean/null) before it is
# exhausted must degrade to the fallback, not throw
# "TypeError: Cannot use 'in' operator to search for ... in <primitive>".
#
# get() lives in QML, so this drives it through a standalone QML probe
# (tests/fixtures/shell/config_get_probe.qml) run directly via `qs -p`,
# rather than through the long-running host's IPC surface. The probe is
# copied into a throwaway scratch tree alongside a copy of the *real*
# shell/services/Config.qml -- Quickshell requires relative-path directory
# imports to stay inside the folder given to -p, which a fixture living
# under tests/ cannot satisfy in place -- so this always exercises the live
# source, never a frozen duplicate.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/lib/common.sh"
source "$REPO_ROOT/lib/env.sh"

if ! coo_quickshell_bin >/dev/null; then echo "skip: quickshell not installed"; exit 0; fi

QS=$(coo_quickshell_bin)

scratch="$COO_TEST_SANDBOX/config_get_probe"
mkdir -p "$scratch/services"
cp "$REPO_ROOT/tests/fixtures/shell/config_get_probe.qml" "$scratch/shell.qml"
cp "$REPO_ROOT/shell/services/Config.qml" "$scratch/services/Config.qml"

export COO_PROBE_CONFIG_ROOT="$REPO_ROOT/tests/fixtures/shell/config_get_probe"

out="$COO_TEST_SANDBOX/probe.log"
: > "$out"

"$QS" -p "$scratch" > "$out" 2>&1 &
probe_pid=$!
cleanup() { kill "$probe_pid" 2>/dev/null; wait "$probe_pid" 2>/dev/null; }
trap cleanup EXIT

# Bounded wait: 25 x 200ms = 5s ceiling. Never unbounded (SPEC 19.3). The
# probe prints synchronously once its fixture config loads, then idles --
# Quickshell 0.3.0 has no receiver for QQmlEngine::exit() -- so waiting for
# the PROBE_DONE sentinel (not process exit) is the correct completion
# signal.
for _ in $(seq 1 25); do
  grep -q "PROBE_DONE" "$out" 2>/dev/null && break
  sleep 0.2
done

body=$(cat "$out" 2>/dev/null || true)

assert_contains "$body" "PROBE_DONE" "probe completed within the time budget"
assert_contains "$body" "ok: path through string leaf" "path through string leaf returns fallback, not a throw"
assert_contains "$body" "ok: path through number leaf" "path through number leaf returns fallback, not a throw"
assert_contains "$body" "ok: path through boolean leaf" "path through boolean leaf returns fallback, not a throw"
assert_contains "$body" "ok: path through explicit null" "path through explicit null returns fallback"
assert_contains "$body" "ok: absent top-level key" "absent top-level key returns fallback"
assert_contains "$body" "ok: absent nested key under valid object" "absent nested key under valid object returns fallback"
assert_contains "$body" "ok: valid multi-segment path resolves" "valid multi-segment path still resolves correctly"

if [[ $body == *FAIL* ]]; then
  printf '      --- probe.log ---\n'; printf '%s\n' "$body" | sed 's/^/      /'
fi

exit "$ASSERT_FAILURES"
