#!/usr/bin/env bash
# tests/test.sh must not leak processes out of a sandbox.
#
# Quickshell 0.3.0's `Process` does not terminate its child when the shell
# exits, and the upstream plugin registry spawns `inotifywait -m` on the
# plugin directory (services/PluginRegistry.qml:638).  Every runtime test that
# starts the shell therefore left one behind, and `rm -rf "$sandbox"` did not
# free it: the watches are dropped, no further events arrive, and the process
# blocks in select() forever.  The runner reaps by sandbox path -- never by
# process name, which would reach the user's live session.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

# A process that carries the sandbox path in its own argv[0] and owns no
# children, standing in for the upstream watcher.  `exec -a` is what puts the
# path on the command line, which is the only thing the reaper matches on.
#
# Called through `$(...)`, so the marker is spawned by a subshell and is
# orphaned the moment that subshell exits -- the same state the shell's
# inotifywait ends up in.  It is therefore nobody's child and `wait` cannot be
# used on it; liveness is polled with `kill -0` instead.
spawn_marker() { # $1 = path to carry
  bash -c 'exec -a "$0" sleep 300' "$1" >/dev/null 2>&1 &
  printf '%s\n' "$!"
}

# Bounded poll for a PID to disappear.  0 = gone, 1 = still alive.
await_gone() { # $1 = pid
  local i
  for (( i = 0; i < 20; i++ )); do
    kill -0 "$1" 2>/dev/null || return 0
    sleep 0.1
  done
  return 1
}

# ------------------------------------------------------------ fixture mode
#
# Under COO_REAP_FIXTURE this file is not a test but the leak itself: it
# strands a marker inside its own sandbox and exits, exactly as a runtime test
# strands the shell's inotifywait.  The outer run below drives a nested
# tests/test.sh in this mode and then asks whether the marker survived.
if [[ ${COO_REAP_FIXTURE:-} == 1 ]]; then
  spawn_marker "${COO_TEST_SANDBOX:?}/watcher" > "${COO_REAP_FIXTURE_OUT:?}"
  disown 2>/dev/null
  exit 0
fi

assert_file_exists "$REPO_ROOT/tests/lib/sandbox.sh" "sandbox reaper library exists"
if [[ ! -f $REPO_ROOT/tests/lib/sandbox.sh ]]; then
  exit "$ASSERT_FAILURES"
fi
source "$REPO_ROOT/tests/lib/sandbox.sh"

# ------------------------------------------------------- reaper in isolation
work=$(mktemp -d "${TMPDIR:-/tmp}/coo-test-reapXXXXXX")
marker=$(spawn_marker "$work/watcher")
# The marker must actually be running, or the kill below proves nothing.
for _ in $(seq 20); do kill -0 "$marker" 2>/dev/null && break; sleep 0.1; done
kill -0 "$marker" 2>/dev/null && spawned=0 || spawned=1
assert_eq "$spawned" "0" "marker process is running before the reap"

coo_reap_sandbox_procs "$work"
reap_code=$?
gone=0; await_gone "$marker" || gone=1
rm -rf "$work"

assert_eq "$reap_code" "0" "reaper reports success when the sandbox is clear"
assert_eq "$gone" "0" "reaper kills a process whose command line names the sandbox"
(( gone )) && kill -KILL "$marker" 2>/dev/null

# --------------------------------------------------------------- path guard
#
# The reaper takes a kill loop over whatever path it is handed, so it must
# refuse anything that is not one of the runner's own mktemp sandboxes.  A
# widened match here would reach the user's live session (SPEC 4.3, 66).
#
# $HOME is deliberately absent from this list: under the runner it *is* the
# sandbox, so the guard is supposed to accept it.  /home/nobody stands in for a
# real user home instead.
outsider_dir=$(mktemp -d "${TMPDIR:-/tmp}/coo-outsider-XXXXXX")
outsider=$(spawn_marker "$outsider_dir/watcher")
for bad in "" "/" "/tmp" "/home/nobody" "$outsider_dir"; do
  code=0; coo_reap_sandbox_procs "$bad" >/dev/null 2>&1 || code=$?
  assert_eq "$code" "2" "reaper refuses non-sandbox path: ${bad:-<empty>}"
done
kill -0 "$outsider" 2>/dev/null && alive=0 || alive=1
assert_eq "$alive" "0" "a refused path kills nothing"
kill -KILL "$outsider" 2>/dev/null
rm -rf "$outsider_dir"

# ------------------------------------------------------ runner end to end
#
# The isolated checks above prove the function; this proves it is actually
# wired into the per-test teardown, which is where the leak happened.
outfile="$COO_TEST_SANDBOX/leaked.pid"
: > "$outfile"
COO_REAP_FIXTURE=1 COO_REAP_FIXTURE_OUT="$outfile" \
  "$REPO_ROOT/tests/test.sh" package/test_sandbox_reap.sh >/dev/null 2>&1
leaked=$(<"$outfile")

assert_eq "$(printf '%s' "$leaked" | grep -cE '^[0-9]+$')" "1" \
  "fixture run reported the PID it stranded (got: ${leaked:-<empty>})"
if [[ $leaked =~ ^[0-9]+$ ]]; then
  kill -0 "$leaked" 2>/dev/null && survived=1 || survived=0
  assert_eq "$survived" "0" "runner reaps a process stranded inside a test sandbox"
  # Never let a failing run become the leak it is testing for.
  (( survived )) && kill -KILL "$leaked" 2>/dev/null
fi

exit "$ASSERT_FAILURES"
