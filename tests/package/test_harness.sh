#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/assert.sh"

assert_file_exists "$REPO_ROOT/tests/test.sh" "test runner exists"
assert_eq "${COO_TEST_SANDBOX:+set}" "set" "sandbox exists"
assert_eq "$HOME" "$COO_TEST_SANDBOX" "sandbox HOME isolation"
assert_eq "${XDG_CONFIG_HOME:-}" "$COO_TEST_SANDBOX/.config" "sandbox XDG config isolation"
assert_eq "${XDG_DATA_HOME:-}" "$COO_TEST_SANDBOX/.local/share" "sandbox XDG data isolation"
assert_eq "${XDG_STATE_HOME:-}" "$COO_TEST_SANDBOX/.local/state" "sandbox XDG state isolation"
assert_eq "${XDG_CACHE_HOME:-}" "$COO_TEST_SANDBOX/.cache" "sandbox XDG cache isolation"

# A discovery failure must be reported as such, not hidden by process
# substitution and misreported later as an empty test selection.
discovery_fake=$COO_TEST_SANDBOX/discovery-fake
mkdir -p "$discovery_fake"
printf '#!/usr/bin/env bash\nexit 23\n' > "$discovery_fake/find"
chmod +x "$discovery_fake/find"
code=0
out=$(PATH="$discovery_fake:$PATH" "$REPO_ROOT/tests/test.sh" package/test_harness.sh 2>&1) || code=$?
assert_eq "$code" "1" "discovery failure exits nonzero"
assert_contains "$out" "error: test discovery failed" "discovery failure is not hidden"

assert_exit 0 "true succeeds" true
assert_exit 1 "false fails" false
assert_eq "hello world" "hello world" "space in value"
[[ $ASSERT_FAILURES -eq 0 ]]
