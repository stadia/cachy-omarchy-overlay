#!/usr/bin/env bash
# Sandbox process reaper. Sourced by tests/test.sh.
#
# Removing a sandbox directory does not stop the processes a test left running
# inside it.  Measured on Quickshell 0.3.0: `Io.Process` does not terminate its
# child when the shell exits -- quickshell answers SIGTERM in ~250ms and the
# child is reparented to `systemd --user`, still running -- and the type
# exposes no property to change that.  The upstream plugin registry spawns
# `inotifywait -m -r` on the plugin directory
# (services/PluginRegistry.qml:638), so every runtime test that starts the
# shell stranded one.  `rm -rf "$sandbox"` did not free them either: the watch
# descriptors are dropped, no further events can arrive, and the process blocks
# in select() indefinitely.  They accumulate one per shell start, forever.
#
# Reaping by process name (pkill inotifywait) would kill the watcher belonging
# to the user's own live shell, so the match is on the sandbox path instead --
# a unique `mktemp -d` value that only this runner's processes can carry.

# List PIDs whose command line names $1.  Environment is deliberately not
# consulted: the runner exports COO_TEST_SANDBOX to every test, so matching on
# it would sweep in the runner's own descendants.
coo_sandbox_pids() {
  local dir=$1 self=$$ pid cmdline
  for pid in /proc/[0-9]*; do
    pid=${pid#/proc/}
    (( pid == self )) && continue
    # `2>/dev/null` must precede the input redirection: redirections apply left
    # to right, so with the order reversed a process that exits mid-scan makes
    # bash report the failed open before stderr is silenced.
    cmdline=$(tr '\0' ' ' 2>/dev/null < "/proc/$pid/cmdline") || continue
    [[ $cmdline == *"$dir"* ]] && printf '%s\n' "$pid"
  done
  return 0
}

# Terminate everything still running inside sandbox $1.
#   0 = nothing left (including "nothing was there")
#   1 = something survived SIGKILL
#   2 = refused: $1 is not one of the runner's sandboxes
coo_reap_sandbox_procs() {
  local dir=${1:-}
  # This function is a kill loop over whatever path it is handed.  Accepting
  # "", "/", "/tmp" or $HOME would reach the user's live session (SPEC 4.3,
  # 66), so only the runner's own `coo-test-` sandboxes are honoured.
  [[ $dir == /*/coo-test-* ]] || return 2

  local pids=() pid i
  mapfile -t pids < <(coo_sandbox_pids "$dir")
  (( ${#pids[@]} )) || return 0

  printf 'note: reaping %d process(es) left inside %s\n' "${#pids[@]}" "$dir"
  for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null; done

  # These are not our children, so `wait` cannot see them -- poll instead, and
  # bound the poll (SPEC 19.3: no unbounded waiting).  2s for TERM, then 1s to
  # confirm KILL landed.
  for (( i = 0; i < 20; i++ )); do
    sleep 0.1
    mapfile -t pids < <(coo_sandbox_pids "$dir")
    (( ${#pids[@]} )) || return 0
  done

  for pid in "${pids[@]}"; do kill -KILL "$pid" 2>/dev/null; done
  for (( i = 0; i < 10; i++ )); do
    sleep 0.1
    mapfile -t pids < <(coo_sandbox_pids "$dir")
    (( ${#pids[@]} )) || return 0
  done

  printf 'warn: %d process(es) survived SIGKILL in %s: %s\n' \
    "${#pids[@]}" "$dir" "${pids[*]}" >&2
  return 1
}
