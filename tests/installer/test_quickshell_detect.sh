#!/usr/bin/env bash
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/lib/common.sh"
source "$REPO_ROOT/lib/env.sh"

# This test depends on the real host having Quickshell installed (SPEC.md's
# target environment). If it isn't here, skip rather than fail -- this is not
# a bug in the overlay.
if ! have_cmd qs && ! have_cmd quickshell; then
  echo "note: neither qs nor quickshell on PATH, skipping"
  exit 0
fi

bin=$(coo_quickshell_bin); code=$?
assert_eq "$code" "0" "quickshell binary found"
assert_contains "$bin" "q" "binary name looks like qs/quickshell"

ver=$(coo_quickshell_version)
assert_contains "$ver" "." "version string has a dot: $ver"

# A missing binary must fail cleanly rather than emit a bogus name. Subshell,
# not assert_exit: coo_quickshell_bin's failure path is a plain `return 1`,
# not `die`, but PATH=/nonexistent must not leak into the rest of this script
# either, so it is scoped the same defensive way as the `die`-calling helpers
# in test_hypr_detect.sh.
out=$(PATH=/nonexistent coo_quickshell_bin); code=$?
assert_eq "$code" "1" "missing quickshell -> exit 1"
assert_eq "$out" "" "missing quickshell -> empty output"

# coo_quickshell_version must fail the same way when the binary is missing,
# rather than printing an empty or garbage version string.
out=$(PATH=/nonexistent coo_quickshell_version); code=$?
assert_eq "$code" "1" "missing quickshell -> version lookup exit 1"
assert_eq "$out" "" "missing quickshell -> version lookup empty output"

exit "$ASSERT_FAILURES"
