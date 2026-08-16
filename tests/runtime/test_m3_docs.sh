#!/usr/bin/env bash
# Task 6: Milestone 3 startup contract is recorded from live measurements.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

startup="$REPO_ROOT/docs/RUNTIME_STARTUP.md"
audit="$REPO_ROOT/docs/COMMAND_AUDIT.md"
deps="$REPO_ROOT/docs/RUNTIME_DEPENDENCIES.md"
patches="$REPO_ROOT/packages/cachy-omarchy-shell/patches/README.md"

assert_file_exists "$startup" "RUNTIME_STARTUP.md 존재"
src=$(cat "$startup")
assert_contains "$src" "Target not found." "IPC Target not found. 실측이 기록됨"
assert_contains "$src" "Function not found." "IPC Function not found. 실측이 기록됨"
assert_contains "$src" "overlay/compat/bin/uwsm-app" "uwsm-app WRAPPER 경로가 기록됨"
assert_contains "$src" "R03" "R03 실측이 기록됨"
assert_contains "$src" "R04" "R04 실측이 기록됨"
assert_contains "$src" "R05" "R05 실측이 기록됨"
assert_contains "$src" "R06" "R06 실측이 기록됨"
assert_contains "$src" "omarchy-menu" "메뉴 layer 네임스페이스가 기록됨"
assert_contains "$src" "바 억제 미충족" "Waybar 보존을 성공으로 선언하지 않는다"
assert_contains "$src" "## 7. M3 결과" "§7 이 M3 결과를 담는다"

assert_file_exists "$audit" "COMMAND_AUDIT.md 존재"
asrc=$(cat "$audit")
assert_contains "$asrc" "MENU_AUDIT_BEGIN" "메뉴 전수 표가 있다"

assert_file_exists "$deps" "RUNTIME_DEPENDENCIES.md 존재"
dsrc=$(cat "$deps")
assert_contains "$dsrc" "overlay/compat/bin/uwsm-app" "의존 표에 uwsm WRAPPER 실측이 있다"

assert_file_exists "$patches" "patches README 존재"
psrc=$(cat "$patches")
assert_contains "$psrc" "none" "패치 수 0"

exit "$ASSERT_FAILURES"
