#!/usr/bin/env bash
# M7 Task 5: RC evidence must retain measured/inferred/unverified boundaries.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

startup="$REPO_ROOT/docs/RUNTIME_STARTUP.md"
gaps="$REPO_ROOT/docs/RC_GAP_INVENTORY.md"
patches="$REPO_ROOT/packages/cachy-omarchy-shell/patches/README.md"

assert_file_exists "$startup" "RUNTIME_STARTUP.md exists"
m7=$(awk '/^## 11\. M7 / { found=1 } found { print }' "$startup")
assert_contains "$m7" "cachy-omarchy-doctor" "M7 records diagnostic doctor"
assert_contains "$m7" "clean build" "M7 records clean-build boundary"
assert_contains "$m7" "R07" "M7 records wrapper-restart evidence"
assert_contains "$m7" "manual wrapper-restart evidence" "M7 does not overclaim service recovery"
assert_contains "$m7" "미검증" "M7 retains unverified runtime boundaries"
assert_contains "$m7" "R09" "M7 records notification boundary"
assert_contains "$m7" "R10" "M7 records lock boundary"
assert_contains "$m7" "U01–U10" "M7 records update coverage"
assert_contains "$m7" "fake lane" "M7 labels fake package-manager evidence"
assert_contains "$m7" "install-pending.manifest" "M7 records pending state"
assert_contains "$m7" "fail-closed" "M7 records fail-closed behavior"
assert_contains "$m7" "패치 수 0" "M7 records zero patch count"
assert_contains "$m7" "omarchy-settings" "M7 records official package absence"

assert_file_exists "$gaps" "RC gap inventory exists"
gap_text=$(cat "$gaps")
assert_contains "$gap_text" "§61 final checklist" "inventory labels final §61 checklist"
assert_contains "$gap_text" "측정됨" "inventory distinguishes measured evidence"
assert_contains "$gap_text" "추론됨" "inventory distinguishes inferred evidence"
assert_contains "$gap_text" "미검증" "inventory distinguishes unverified evidence"
assert_contains "$gap_text" "tests/runtime/test_runtime_reliability.sh" "inventory cross-references runtime tests"
assert_contains "$gap_text" "tests/package/test_update_pipeline.sh" "inventory cross-references update tests"
assert_contains "$gap_text" "pending" "inventory records pending fail-closed state"

assert_file_exists "$patches" "patch README exists"
assert_contains "$(cat "$patches")" "none" "patch count remains zero"

exit "$ASSERT_FAILURES"
