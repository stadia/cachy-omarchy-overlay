#!/usr/bin/env bash
# 테마 hyprland.lua 연결 (M9 D5): lua 는 관리 파일 안의 가드 로드,
# conf 는 관리 블록 스니펫의 조건부 source 줄. 사용자 설정 본문은 무침.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

LUA_TPL="$REPO_ROOT/overlay/hypr/bindings.lua"
src=$(<"$LUA_TPL")
assert_contains "$src" "current/theme/hyprland.lua" "lua 가드가 테마 경로를 본다"
assert_contains "$src" "pcall" "테마 로드는 pcall 가드"
assert_contains "$src" "io.open" "존재 확인 후에만 로드"

# conf 스니펫: 테마 파일이 있을 때만 source 줄이 들어간다.
home=$COO_TEST_SANDBOX/h
mkdir -p "$home/.config/hypr" "$home/.config/cachy-omarchy/hypr"
printf 'monitor=,preferred,auto,1\n' > "$home/.config/hypr/hyprland.conf"

run_bindings() {
  HOME="$home" COO_CONFIG_DIR="$home/.config/cachy-omarchy" \
  COO_HYPR_DIR="$home/.config/hypr" \
    "$REPO_ROOT/overlay/bin/cachy-omarchy-bindings" "$@"
}

# 테마 부재 → source 줄 없음
run_bindings >/dev/null 2>&1
grep -q "current/theme/hyprland.lua" "$home/.config/hypr/hyprland.conf" \
  && x=1 || x=0
assert_eq "$x" "0" "테마 부재 시 conf 블록에 theme source 없음"

# 테마 존재 → 재주입 시 source 줄 포함
mkdir -p "$home/.local/state/omarchy/current/theme"
printf 'hl.general.border_size(2)\n' \
  > "$home/.local/state/omarchy/current/theme/hyprland.lua"
run_bindings --force >/dev/null 2>&1
grep -q "source = .*current/theme/hyprland.lua" \
  "$home/.config/hypr/hyprland.conf" && x=0 || x=1
assert_eq "$x" "0" "테마 존재 시 conf 블록에 theme source 포함"

# 사용자 본문 무침: 첫 줄이 그대로다
assert_eq "$(head -1 "$home/.config/hypr/hyprland.conf")" \
  "monitor=,preferred,auto,1" "사용자 설정 본문은 그대로"

# lua 경로는 여전히 pcall(dofile) 스니펫만 넣는다 (가드는 bindings.lua 안)
home2=$COO_TEST_SANDBOX/h2
mkdir -p "$home2/.config/hypr"
printf 'hl.monitor(",preferred,auto,1")\n' > "$home2/.config/hypr/hyprland.lua"
HOME="$home2" COO_CONFIG_DIR="$home2/.config/cachy-omarchy" \
  COO_HYPR_DIR="$home2/.config/hypr" \
  "$REPO_ROOT/overlay/bin/cachy-omarchy-bindings" >/dev/null 2>&1
assert_contains "$(cat "$home2/.config/hypr/hyprland.lua")" \
  "pcall(dofile" "lua 관리 블록은 pcall 스니펫"

exit "$ASSERT_FAILURES"
