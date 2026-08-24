#!/usr/bin/env bash
# M4 Task 5: startup contract records the upstream UI adaptation and live proof.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

startup="$REPO_ROOT/docs/RUNTIME_STARTUP.md"
patches="$REPO_ROOT/packages/cachy-omarchy-shell/patches/README.md"

assert_file_exists "$startup" "RUNTIME_STARTUP.md 존재"
m4=$(awk '/^## 8\. M4 결과/ { found=1 } found { print }' "$startup")
assert_contains "$m4" "적응 카피" "M4 는 핀된 업스트림 스크립트 적응 카피"
assert_contains "$m4" "커스텀 QML" "M4 는 커스텀 QML 뷰어를 만들지 않는다"
assert_contains "$m4" "49" "M4 호스트 바인드 실측(v13: 49개)"
assert_contains "$m4" "v13" "M4 캐시 스키마 v13"
assert_contains "$m4" 'loadfile(config, "t", env)' "Lua 스캔은 제한 loadfile 환경"
assert_contains "$m4" "표준 dofile 하지" "Lua 스캔은 표준 dofile 을 쓰지 않는다"
assert_contains "$m4" "제한 `dofile`" "관리 source 블록은 제한 dofile 로 따라간다"
assert_contains "$m4" "os.execute" "악성 Lua 실행 회귀가 문서화됨"
assert_contains "$m4" "1920×1080 @ 0,0" "live omarchy-menu layer 기하가 기록됨"
assert_contains "$m4" "Escape" "Escape 취소 실측이 기록됨"
assert_contains "$m4" "helper exit 0" "Escape 뒤 helper 정상 종료가 기록됨"
assert_contains "$m4" "SUPER+K" "관리 SUPER+K 바인딩이 기록됨"
assert_contains "$m4" "hyprctl reload 없음" "M4 는 hyprctl reload 하지 않는다"
assert_contains "$m4" "Waybar 보존을 성공으로 선언하지 않는다" "Waybar 보존을 선언하지 않는다"
assert_contains "$m4" "M5" "M5 범위 밖이 기록됨"
assert_contains "$m4" "유지보수 패치" "런타임 패치 계약 기록"
assert_contains "$m4" "omarchy-menu-select" "스테이징된 upstream select helper"
assert_contains "$m4" "동명 shim" "메뉴 동명 action 이 범위 밖임을 기록"

assert_file_exists "$patches" "patches README 존재"
psrc=$(cat "$patches")
assert_contains "$psrc" "maintained runtime patches" "패치 README 유지보수 계약"

exit "$ASSERT_FAILURES"
