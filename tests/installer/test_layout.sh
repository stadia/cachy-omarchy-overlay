#!/usr/bin/env bash
# Asserts the repository skeleton required by SPEC.md §10 exists.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?REPO_ROOT must be set by tests/test.sh}"
source "$REPO_ROOT/tests/lib/assert.sh"

for f in LICENSE UPSTREAM.md README.md lib/common.sh; do
  assert_file_exists "$REPO_ROOT/$f" "repo file $f"
done

source "$REPO_ROOT/lib/common.sh"
assert_eq "$COO_NAME" "cachy-omarchy-overlay" "COO_NAME"
assert_eq "$COO_MARKER_BEGIN" "# >>> cachy-omarchy-overlay >>>" "COO_MARKER_BEGIN"
assert_eq "$COO_MARKER_END" "# <<< cachy-omarchy-overlay <<<" "COO_MARKER_END"

have_cmd bash && ok=0 || ok=1
assert_eq "$ok" "0" "have_cmd bash"
have_cmd definitely-not-a-real-command-xyz && ok=0 || ok=1
assert_eq "$ok" "1" "have_cmd missing"

# The upstream pin must be an exact SHA, never a branch name.
pin=$(grep -oE '^Commit: [0-9a-f]{40}$' "$REPO_ROOT/UPSTREAM.md" || true)
assert_eq "$pin" "Commit: b724f7615630d7a7aca76dce070d469f43a3bfec" "upstream pin"

exit "$ASSERT_FAILURES"
