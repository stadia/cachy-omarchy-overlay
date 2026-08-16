#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/assert.sh"

assert_file_exists "$REPO_ROOT/tests/test.sh" "test runner exists"
assert_eq "${COO_TEST_SANDBOX:+set}" "set" "sandbox HOME isolation"
[[ $ASSERT_FAILURES -eq 0 ]]
