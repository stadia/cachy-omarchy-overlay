#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/assert.sh"

readme=$REPO_ROOT/packages/cachy-omarchy-shell/patches/README.md
assert_file_exists "$readme" "patches README"

mapfile -t patches < <(find "$REPO_ROOT/packages/cachy-omarchy-shell/patches" -name '*.patch' -type f | sort)
assert_eq "${#patches[@]}" "0" "P09 no patches in Milestone 1"
assert_contains "$(cat "$readme")" "none" "README records no patches"

[[ $ASSERT_FAILURES -eq 0 ]]
