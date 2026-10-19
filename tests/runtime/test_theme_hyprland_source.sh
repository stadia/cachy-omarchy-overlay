#!/usr/bin/env bash
# 테마 hyprland.lua 연결: 관리 파일(bindings.lua) 안의 가드 로드.
# 사용자 설정 본문은 무침.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

LUA_TPL="$REPO_ROOT/overlay/hypr/bindings.lua"
src=$(<"$LUA_TPL")
assert_contains "$src" "current/theme/hyprland.lua" "lua 가드가 테마 경로를 본다"
assert_contains "$src" "pcall" "테마 로드는 pcall 가드"
assert_contains "$src" "io.open" "존재 확인 후에만 로드"

# 관리 블록은 pcall(dofile) 스니펫만 넣는다 (가드는 bindings.lua 안)
home2=$COO_TEST_SANDBOX/h2
mkdir -p "$home2/.config/hypr"
printf 'hl.monitor(",preferred,auto,1")\n' > "$home2/.config/hypr/hyprland.lua"
HOME="$home2" COO_CONFIG_DIR="$home2/.config/cachy-omarchy" \
  COO_HYPR_DIR="$home2/.config/hypr" \
  "$REPO_ROOT/overlay/bin/cachy-omarchy-bindings" >/dev/null 2>&1
assert_contains "$(cat "$home2/.config/hypr/hyprland.lua")" \
  "pcall(dofile" "lua 관리 블록은 pcall 스니펫"

exit "$ASSERT_FAILURES"
