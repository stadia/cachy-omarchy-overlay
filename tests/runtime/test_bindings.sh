#!/usr/bin/env bash
# Task 4: Hyprland SUPER+SPACE managed block. Static only — no hyprctl reload.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

H="$REPO_ROOT/overlay/bin/cachy-omarchy-bindings"
CONF="$REPO_ROOT/overlay/hypr/bindings.conf"
LUA="$REPO_ROOT/overlay/hypr/bindings.lua"

assert_file_exists "$H" "바인딩 헬퍼 존재"
[[ -x $H ]] && x=0 || x=1
assert_eq "$x" "0" "바인딩 헬퍼 실행 가능"
[[ -x $H ]] || exit 1

assert_file_exists "$CONF" "정본 bindings.conf"
assert_file_exists "$LUA" "정본 bindings.lua"

csrc=$(cat "$CONF")
assert_contains "$csrc" "SUPER, SPACE" "conf 가 SUPER+SPACE 를 바인딩한다"
assert_contains "$csrc" "cachy-omarchy-launcher" "conf 대상은 런처"
assert_contains "$csrc" "unbind = SUPER, K" "conf 는 SUPER+K 를 먼저 unbind 한다"
assert_contains "$csrc" "bind = SUPER, K, exec, cachy-omarchy-keybindings" "conf 가 SUPER+K 를 keybindings 명령에 바인딩한다"
[[ $csrc == *"bind = SUPER, K,"* ]] && klive=1 || klive=0
assert_eq "$klive" "1" "conf 는 SUPER+K 를 활성화한다"

lsrc=$(cat "$LUA")
assert_contains "$lsrc" 'SUPER + space' "lua 가 SUPER+SPACE 를 바인딩한다"
assert_contains "$lsrc" "cachy-omarchy-launcher" "lua 대상은 런처"
assert_contains "$lsrc" "hl.unbind" "lua 는 unbind 후 bind 한다"
assert_contains "$lsrc" 'hl.unbind("SUPER + K")' "lua 는 SUPER+K 를 먼저 unbind 한다"
assert_contains "$lsrc" 'hl.bind("SUPER + K", hl.dsp.exec_cmd("cachy-omarchy-keybindings"))' "lua 가 SUPER+K 를 keybindings 명령에 바인딩한다"
[[ $lsrc == *'hl.bind("SUPER + K"'* ]] && klive=1 || klive=0
assert_eq "$klive" "1" "lua 는 SUPER+K 를 활성화한다"

hsrc=$(cat "$H")
if grep -Eiq '^[[:space:]]*hyprctl[[:space:]]+reload' <<<"$hsrc"; then
  printf 'FAIL: 헬퍼가 hyprctl reload 를 호출한다\n'
  ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
else
  printf 'ok:   헬퍼는 hyprctl reload 를 호출하지 않는다\n'
fi
[[ $hsrc == *"pkill Hyprland"* ]] && p=1 || p=0
assert_eq "$p" "0" "헬퍼에 pkill Hyprland 없음"

out=$("$H" --help 2>&1); code=$?
assert_eq "$code" "0" "--help exit 0"
assert_contains "$out" "--force" "--help 가 --force 를 설명한다"

[[ ${HOME:-} == "${COO_TEST_SANDBOX:?}" ]] || {
  printf 'FAIL: HOME 이 샌드박스가 아니다 — 사용자 hypr 를 건드릴 수 있어 중단한다\n' >&2
  exit 1
}

hypr="$HOME/.config/hypr"
coo="$HOME/.config/cachy-omarchy/hypr"
mkdir -p "$hypr"

# --- lua, no conflict -------------------------------------------------------
cat >"$hypr/hyprland.lua" <<'EOF'
-- sandbox root
local mainMod = "SUPER"
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd("ghostty"))
EOF
orig=$(cat "$hypr/hyprland.lua")

out=$(COO_HYPR_DIR="$hypr" COO_CONFIG_DIR="$HOME/.config/cachy-omarchy" "$H" 2>&1); code=$?
assert_eq "$code" "0" "충돌 없는 lua → exit 0"
assert_file_exists "$coo/bindings.lua" "사용자 overlay lua 가 설치된다"
body=$(cat "$hypr/hyprland.lua")
assert_contains "$body" "-- >>> cachy-omarchy >>>" "lua 관리 블록 시작 마커"
assert_contains "$body" "-- <<< cachy-omarchy <<<" "lua 관리 블록 끝 마커"
assert_contains "$body" "pcall" "lua 블록은 pcall(dofile) 이다"
assert_contains "$body" "ghostty" "관리 블록 밖 본문은 보존된다"
[[ $body == *"#"*"cachy-omarchy"* ]] && hash=1 || hash=0
assert_eq "$hash" "0" "lua 마커는 # 가 아니다"

out2=$(COO_HYPR_DIR="$hypr" COO_CONFIG_DIR="$HOME/.config/cachy-omarchy" "$H" 2>&1); code=$?
assert_eq "$code" "0" "멱등 재실행 exit 0"
n=$(grep -c 'cachy-omarchy >>>' "$hypr/hyprland.lua" || true)
assert_eq "$n" "1" "관리 블록은 한 번만 있다"

# --- lua conflict, default does not override --------------------------------
cat >"$hypr/hyprland.lua" <<'EOF'
local mainMod = "SUPER"
hl.bind(mainMod .. " + space", hl.dsp.exec_cmd("walker"))
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd("ghostty"))
EOF
before=$(cat "$hypr/hyprland.lua")
out=$(COO_HYPR_DIR="$hypr" COO_CONFIG_DIR="$HOME/.config/cachy-omarchy" "$H" 2>&1); code=$?
assert_eq "$code" "0" "충돌 시 기본 모드는 조용히 덮어쓰지 않는다 (exit 0)"
assert_contains "$out" "SUPER" "충돌 경고가 SUPER 를 언급한다"
after=$(cat "$hypr/hyprland.lua")
assert_eq "$after" "$before" "충돌 시 lua 본문이 그대로다"

out=$(COO_HYPR_DIR="$hypr" COO_CONFIG_DIR="$HOME/.config/cachy-omarchy" "$H" --force 2>&1); code=$?
assert_eq "$code" "0" "--force 는 충돌이 있어도 주입한다"
body=$(cat "$hypr/hyprland.lua")
assert_contains "$body" "-- >>> cachy-omarchy >>>" "--force 후 관리 블록"
assert_contains "$body" "walker" "--force 는 기존 bind 줄을 지우지 않는다"
assert_contains "$out" "기존 설정은 삭제하지 않는다" "--force 는 기존 설정 보존을 고지한다"

# --- lua K-only conflict ----------------------------------------------------
cat >"$hypr/hyprland.lua" <<'EOF'
local mainMod = "SUPER"
hl.bind(mainMod .. " + K", hl.dsp.exec_cmd("existing-k"))
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd("ghostty"))
EOF
before=$(cat "$hypr/hyprland.lua")
out=$(COO_HYPR_DIR="$hypr" COO_CONFIG_DIR="$HOME/.config/cachy-omarchy" "$H" 2>&1); code=$?
assert_eq "$code" "0" "SUPER+K 단독 충돌도 기본 모드는 주입하지 않는다"
assert_contains "$out" "SUPER+K" "K 단독 충돌 경고가 SUPER+K 를 말한다"
after=$(cat "$hypr/hyprland.lua")
assert_eq "$after" "$before" "K 단독 충돌 시 lua 본문이 그대로다"

out=$(COO_HYPR_DIR="$hypr" COO_CONFIG_DIR="$HOME/.config/cachy-omarchy" "$H" --force 2>&1); code=$?
assert_eq "$code" "0" "--force 는 K 단독 충돌에도 주입한다"
assert_contains "$out" "기존 설정은 삭제하지 않는다" "K 충돌 --force 전 보존 고지"
body=$(cat "$hypr/hyprland.lua")
assert_contains "$body" "-- >>> cachy-omarchy >>>" "K 충돌 --force 후 관리 블록"
assert_contains "$body" "existing-k" "K 충돌 --force 도 기존 bind 줄을 지우지 않는다"

# --- conf, no conflict ------------------------------------------------------
rm -f "$hypr/hyprland.lua"
cat >"$hypr/hyprland.conf" <<'EOF'
$mainMod = SUPER
bind = $mainMod, Return, exec, ghostty
EOF
out=$(COO_HYPR_DIR="$hypr" COO_CONFIG_DIR="$HOME/.config/cachy-omarchy" "$H" 2>&1); code=$?
assert_eq "$code" "0" "충돌 없는 conf → exit 0"
assert_file_exists "$coo/bindings.conf" "사용자 overlay conf 가 설치된다"
body=$(cat "$hypr/hyprland.conf")
assert_contains "$body" "# >>> cachy-omarchy >>>" "conf 관리 블록"
assert_contains "$body" "source =" "conf 블록은 source 한다"
assert_contains "$body" "ghostty" "conf 본문 보존"

cat >"$hypr/hyprland.conf" <<'EOF'
bind = SUPER, SPACE, exec, walker
bind = SUPER, Return, exec, ghostty
EOF
before=$(cat "$hypr/hyprland.conf")
out=$(COO_HYPR_DIR="$hypr" COO_CONFIG_DIR="$HOME/.config/cachy-omarchy" "$H" 2>&1); code=$?
assert_eq "$code" "0" "conf 충돌도 덮어쓰지 않는다"
after=$(cat "$hypr/hyprland.conf")
assert_eq "$after" "$before" "충돌 시 conf 본문이 그대로다"

exit "$ASSERT_FAILURES"
