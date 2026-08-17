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
assert_contains "$lua" 'cachy-omarchy-launcher' "super+space → 런처 유지"

exit "$ASSERT_FAILURES"