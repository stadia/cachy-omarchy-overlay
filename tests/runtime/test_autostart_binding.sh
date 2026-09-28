#!/usr/bin/env bash
# bindings.lua 가 hyprland.start 1회 autostart 로 셸을 기동하는지 정적 검증.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

B="$REPO_ROOT/overlay/hypr/bindings.lua"
assert_file_exists "$B" "bindings.lua 존재"
lua=$(cat "$B")

assert_contains "$lua" 'hyprland.start' "autostart 가 hyprland.start 1회 트리거"
assert_contains "$lua" 'cachy-omarchy-shell --run' "autostart 가 래퍼 --run 을 기동"
assert_contains "$lua" 'hl.on(' "hl.on 으로 1회 구독"
# 기존 리바인딩은 그대로 유지돼야 한다.
assert_contains "$lua" 'SUPER + space' "super+space 리바인딩 유지"
assert_contains "$lua" 'omarchy-menu toggle' "super+space → 업스트림 메뉴"

# hyprland.conf 사용자도 같은 1회 기동을 받아야 한다. conf 는 Lua 를 실행하지
# 않으므로 hl.on 대신 exec-once 로 선언한다 — 없으면 conf 구성에서 셸이 뜨지
# 않아 런처·키바인딩 뷰어가 모두 실패한다.
conf=$(cat "$REPO_ROOT/overlay/hypr/bindings.conf")
assert_contains "$conf" 'exec-once = cachy-omarchy-shell --run' "conf 도 세션 시작 시 셸을 1회 기동"

exit "$ASSERT_FAILURES"