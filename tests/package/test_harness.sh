#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/assert.sh"

assert_file_exists "$REPO_ROOT/tests/test.sh" "test runner exists"
assert_eq "${COO_TEST_SANDBOX:+set}" "set" "sandbox HOME isolation"
assert_exit 0 "true succeeds" true
assert_exit 1 "false fails" false
assert_eq "hello world" "hello world" "space in value"
[[ $ASSERT_FAILURES -eq 0 ]]
