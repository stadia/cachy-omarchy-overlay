#!/usr/bin/env bash
# Task 6: Milestone 3 startup contract is recorded from live measurements.
# 2026-08-19 개정: uwsm-app compat shim 이 삭제되고 /usr/bin/uwsm-app 이 uwsm
# 패키지 소유 실제 바이너리가 되면서, 문서가 새 no-shim 계약을 서술하는지 단언한다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

startup="$REPO_ROOT/docs/RUNTIME_STARTUP.md"
audit="$REPO_ROOT/docs/COMMAND_AUDIT.md"
deps="$REPO_ROOT/docs/RUNTIME_DEPENDENCIES.md"
upstream="$REPO_ROOT/UPSTREAM.md"
pkg_audit="$REPO_ROOT/docs/PACKAGE_AUDIT.md"
patches="$REPO_ROOT/packages/cachy-omarchy-shell/patches/README.md"

assert_file_exists "$startup" "RUNTIME_STARTUP.md 존재"
src=$(cat "$startup")
assert_contains "$src" "Target not found." "IPC Target not found. 실측이 기록됨"
assert_contains "$src" "Function not found." "IPC Function not found. 실측이 기록됨"
assert_contains "$src" "shim 은 삭제됐다" "uwsm-app shim 삭제가 기록됨"
assert_contains "$src" "uwsm-app 은 uwsm 패키지가 소유하는 실제 바이너리" \
  "uwsm-app 소유권 계약이 기록됨"
assert_contains "$src" "R03" "R03 실측이 기록됨"
assert_contains "$src" "R04" "R04 실측이 기록됨"
assert_contains "$src" "R05" "R05 실측이 기록됨"
assert_contains "$src" "R06" "R06 실측이 기록됨"
assert_contains "$src" "omarchy-menu" "메뉴 layer 네임스페이스가 기록됨"
assert_contains "$src" "바 억제 미충족" "Waybar 보존을 성공으로 선언하지 않는다"
assert_contains "$src" "## 7. M3 결과" "§7 이 M3 결과를 담는다"
assert_contains "$src" "개정 전 측정" "§16.2 environ 실측이 개정 전 스냅샷으로 표기됨"

assert_file_exists "$audit" "COMMAND_AUDIT.md 존재"
asrc=$(cat "$audit")
assert_contains "$asrc" "MENU_AUDIT_BEGIN" "메뉴 전수 표가 있다"
assert_contains "$asrc" "compat shim 삭제됨" "감사 표가 uwsm-app shim 삭제를 기록"
omarchy_bar_row=$(grep -F '| `omarchy-bar` |' <<<"$asrc" || true)
assert_contains "$omarchy_bar_row" "bin/omarchy-bar" \
  "omarchy-bar 전수 행은 업스트림 바 설정 헬퍼다"
assert_contains "$omarchy_bar_row" "SAFE" \
  "omarchy-bar 전수 행은 스테이징된 SAFE 헬퍼다"
assert_contains "$omarchy_bar_row" "package" \
  "omarchy-bar 전수 행의 조치는 package 다"
assert_contains "$omarchy_bar_row" "layer-shell" \
  "omarchy-bar 전수 행이 layer-shell 네임스페이스와 동명임을 적는다"
assert_contains "$omarchy_bar_row" "omarchy-toggle-bar" \
  "omarchy-bar 전수 행이 가시성 토글과 구분된다"
grep -qF '바/토글. 내장 바는 M5. 플러그인 disable이 우선' <<<"$omarchy_bar_row" \
  && bar_toggle_copypaste=1 || bar_toggle_copypaste=0
assert_eq "$bar_toggle_copypaste" "0" \
  "omarchy-bar 행에 토글/플러그인 copypaste 설명이 남아있지 않다"
grep -qE '미스테이징|command not found' <<<"$omarchy_bar_row" \
  && bar_unstaged=1 || bar_unstaged=0
assert_eq "$bar_unstaged" "0" \
  "omarchy-bar 행이 미스테이징으로 남아있지 않다"
assert_contains "$asrc" "실행 가능한 명령이 아니며" \
  "전수 서문이 layer-shell 네임스페이스는 명령이 아님을 적는다"
grep -qF '있으면 위임' <<<"$asrc" && stale=1 || stale=0
assert_eq "$stale" "0" "감사 표에 삭제된 shim 위임 설명이 남아있지 않다"

assert_file_exists "$deps" "RUNTIME_DEPENDENCIES.md 존재"
dsrc=$(cat "$deps")
assert_contains "$dsrc" "uwsm-app 은 uwsm 패키지가 소유하는 실제 바이너리" \
  "의존 표가 uwsm-app 을 uwsm 패키지 소유로 기록"
grep -qF 'overlay/compat/bin/uwsm-app' <<<"$dsrc" && stale=1 || stale=0
assert_eq "$stale" "0" "의존 감사에 삭제된 uwsm-app shim 경로가 남아있지 않다"

assert_file_exists "$upstream" "UPSTREAM.md 존재"
usrc=$(cat "$upstream")
grep -qF 'compat/bin/{omarchy-shell,uwsm-app' <<<"$usrc" && stale=1 || stale=0
assert_eq "$stale" "0" "UPSTREAM.md 소유 목록에 삭제된 uwsm-app shim 이 없다"
assert_contains "$usrc" 'uwsm 패키지(`cachy-omarchy-shell` 의 hard depends)' \
  "UPSTREAM.md 가 uwsm-app 소유권을 기록"

assert_file_exists "$pkg_audit" "PACKAGE_AUDIT.md 존재"
pasrc=$(cat "$pkg_audit")
grep -qF 'adapt away' <<<"$pasrc" && stale=1 || stale=0
assert_eq "$stale" "0" "PACKAGE_AUDIT.md §6 결론에 uwsm-app 을 걷어내라는 구 판정이 없다"

assert_file_exists "$patches" "patches README 존재"
psrc=$(cat "$patches")
assert_contains "$psrc" "none" "패치 수 0"

exit "$ASSERT_FAILURES"
