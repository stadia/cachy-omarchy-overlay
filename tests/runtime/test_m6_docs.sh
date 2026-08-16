#!/usr/bin/env bash
# M6 Task 5: update pipeline safety contract is recorded for operators.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

startup="$REPO_ROOT/docs/RUNTIME_STARTUP.md"
upstream="$REPO_ROOT/UPSTREAM.md"
patches="$REPO_ROOT/packages/cachy-omarchy-shell/patches/README.md"

assert_file_exists "$startup" "RUNTIME_STARTUP.md exists"
m6=$(awk '/^## 10\. M6 / { found=1 } found { print }' "$startup")
assert_contains "$m6" "build-packages" "M6 builds both packages before tests"
assert_contains "$m6" "test_installed_tree.sh" "M6 names installed-tree skip coverage"
assert_contains "$m6" "skip:" "M6 rejects false-green skips"
assert_contains "$m6" "validated-build.manifest" "M6 records validated manifest authority"
assert_contains "$m6" "immutable" "M6 records immutable release storage"
assert_contains "$m6" "install-pending.manifest" "M6 records fail-closed pending install state"
assert_contains "$m6" "operator recovery" "M6 tells operators how to handle pending install state"
assert_contains "$m6" "마지막" "M6 records manifest-last publication invariant"
assert_contains "$m6" "--install" "M6 makes installation explicit"
assert_contains "$m6" "rollback" "M6 records rollback scope"
assert_contains "$m6" "UPSTREAM.md" "M6 records human snapshot status"
assert_contains "$m6" "clean chroot" "M6 records chroot deferral"
assert_contains "$m6" "graphical-session.target" "M6 does not claim automatic start"
assert_contains "$m6" "U01" "M6 update test coverage is recorded"
assert_contains "$m6" "U10" "M6 rollback test coverage is recorded"
assert_contains "$m6" "패치 수 0" "M6 records zero patch count"

assert_file_exists "$upstream" "UPSTREAM.md exists"
usrc=$(cat "$upstream")
assert_contains "$usrc" "사람이 유지하는" "UPSTREAM table is human-maintained snapshot"
assert_contains "$usrc" "stale" "UPSTREAM snapshot staleness is documented"

assert_file_exists "$patches" "patch README exists"
assert_contains "$(cat "$patches")" "none" "patch count remains zero"

exit "$ASSERT_FAILURES"
