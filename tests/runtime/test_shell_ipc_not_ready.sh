#!/usr/bin/env bash
# A booting shell answers `qs ipc` on stdout with "Not ready to accept queries
# yet" and exit 0.  Upstream bin/omarchy-shell treats that as unreachable; the
# wrapper must too, or a ping during startup reads as success.  qs is a stub —
# no real quickshell is started.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

W="$REPO_ROOT/overlay/bin/cachy-omarchy-shell"
fake="$COO_TEST_SANDBOX/ipc-not-ready"
mkdir -p "$fake/upstream/shell" "$fake/stub"
: > "$fake/upstream/shell/shell.qml"
cat > "$fake/stub/qs" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$STUB_OUT"
STUB
chmod +x "$fake/stub/qs"

run_ipc() { # $1 = stub stdout
  STUB_OUT=$1 PATH="$fake/stub:$PATH" COO_OMARCHY_PATH="$fake/upstream" \
    "$W" --ipc shell ping 2>&1
}

out=$(run_ipc "Not ready to accept queries yet"); code=$?
assert_eq "$code" "1" "booting shell → wrapper exit 1"
assert_contains "$out" "not ready" "error says the shell is not ready"

out=$(run_ipc "pong"); code=$?
assert_eq "$code" "0" "a real answer still passes"
assert_eq "$out" "pong" "a real answer is printed"

exit "$ASSERT_FAILURES"
