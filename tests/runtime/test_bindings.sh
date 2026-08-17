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

# M10 D6: media/brightness 키는 관리 블록에 자동 주입하지 않는다. audio helper 의
# 도달 경로는 명시 CLI/메뉴뿐이다 (P07).
for src_text in "$csrc" "$lsrc"; do
  if grep -qE 'XF86|omarchy-audio-output|omarchy-brightness' <<<"$src_text"; then
    printf 'FAIL: M10 — 관리 바인딩 소스에 media/brightness 키 주입 금지\n'
    ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
  fi
done
printf 'ok:   M10 media/brightness 키 미주입 (if no FAIL above)\n'

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

# --- literal Lua SUPER+K remains a conflict --------------------------------
cat >"$hypr/hyprland.lua" <<'EOF'
hl.bind("SUPER + K", hl.dsp.exec_cmd("literal-k"))
EOF
before=$(cat "$hypr/hyprland.lua")
out=$(COO_HYPR_DIR="$hypr" COO_CONFIG_DIR="$HOME/.config/cachy-omarchy" "$H" 2>&1); code=$?
assert_eq "$code" "0" "literal Lua SUPER+K 는 충돌이다"
assert_contains "$out" "SUPER+K" "literal Lua 충돌 경고가 SUPER+K 를 말한다"
after=$(cat "$hypr/hyprland.lua")
assert_eq "$after" "$before" "literal Lua SUPER+K 는 기본 주입을 막는다"

# --- single-quoted Lua SUPER+K forms remain conflicts ----------------------
cat >"$hypr/hyprland.lua" <<'EOF'
local mainMod = "SUPER"
hl.bind('SUPER + K', hl.dsp.exec_cmd("single-literal-k"))
hl.bind(mainMod .. ' + K', hl.dsp.exec_cmd("single-mainmod-k"))
EOF
before=$(cat "$hypr/hyprland.lua")
out=$(COO_HYPR_DIR="$hypr" COO_CONFIG_DIR="$HOME/.config/cachy-omarchy" "$H" 2>&1); code=$?
assert_eq "$code" "0" "단일 인용 Lua SUPER+K 형태도 충돌이다"
assert_contains "$out" "SUPER+K" "단일 인용 Lua 충돌 경고가 SUPER+K 를 말한다"
after=$(cat "$hypr/hyprland.lua")
assert_eq "$after" "$before" "단일 인용 literal/mainMod Lua 는 기본 주입을 막는다"

# --- lua K false positives do not block ------------------------------------
cat >"$hypr/hyprland.lua" <<'EOF'
hl.bind("ALT + K", hl.dsp.exec_cmd("alt-k"))
-- hl.bind("SUPER + K", hl.dsp.exec_cmd("comment-only"))
hl.bind("SUPER + Return", hl.dsp.exec_cmd("ghostty"))
EOF
out=$(COO_HYPR_DIR="$hypr" COO_CONFIG_DIR="$HOME/.config/cachy-omarchy" "$H" 2>&1); code=$?
assert_eq "$code" "0" "Lua ALT+K/주석은 SUPER+K 충돌이 아니다"
body=$(cat "$hypr/hyprland.lua")
assert_contains "$body" "-- >>> cachy-omarchy >>>" "Lua ALT+K/주석만 있으면 관리 블록을 주입한다"
assert_contains "$body" "alt-k" "Lua ALT+K 원본 줄을 보존한다"
assert_contains "$body" "comment-only" "Lua 주석 원본 줄을 보존한다"

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

# --- conf SUPER+K positive forms remain conflicts --------------------------
cat >"$hypr/hyprland.conf" <<'EOF'
bind = SUPER, K, exec, literal-k
EOF
before=$(cat "$hypr/hyprland.conf")
out=$(COO_HYPR_DIR="$hypr" COO_CONFIG_DIR="$HOME/.config/cachy-omarchy" "$H" 2>&1); code=$?
assert_eq "$code" "0" "literal conf SUPER,K 는 충돌이다"
after=$(cat "$hypr/hyprland.conf")
assert_eq "$after" "$before" "literal conf SUPER,K 는 기본 주입을 막는다"

cat >"$hypr/hyprland.conf" <<'EOF'
bind = $mainMod, K, exec, variable-k
EOF
before=$(cat "$hypr/hyprland.conf")
out=$(COO_HYPR_DIR="$hypr" COO_CONFIG_DIR="$HOME/.config/cachy-omarchy" "$H" 2>&1); code=$?
assert_eq "$code" "0" '$mainMod conf K 는 지원되는 충돌이다'
after=$(cat "$hypr/hyprland.conf")
assert_eq "$after" "$before" '$mainMod conf K 는 기본 주입을 막는다'

# --- conf K false positives do not block -----------------------------------
cat >"$hypr/hyprland.conf" <<'EOF'
bind = ALT, K, exec, alt-k
# bind = SUPER, K, exec, comment-only
bind = SUPER, Return, exec, ghostty
EOF
out=$(COO_HYPR_DIR="$hypr" COO_CONFIG_DIR="$HOME/.config/cachy-omarchy" "$H" 2>&1); code=$?
assert_eq "$code" "0" "conf ALT,K/주석은 SUPER+K 충돌이 아니다"
body=$(cat "$hypr/hyprland.conf")
assert_contains "$body" "# >>> cachy-omarchy >>>" "conf ALT,K/주석만 있으면 관리 블록을 주입한다"
assert_contains "$body" "alt-k" "conf ALT,K 원본 줄을 보존한다"
assert_contains "$body" "comment-only" "conf 주석 원본 줄을 보존한다"

cat >"$hypr/hyprland.conf" <<'EOF'
bind = SUPER, SPACE, exec, walker
bind = SUPER, Return, exec, ghostty
EOF
before=$(cat "$hypr/hyprland.conf")
out=$(COO_HYPR_DIR="$hypr" COO_CONFIG_DIR="$HOME/.config/cachy-omarchy" "$H" 2>&1); code=$?
assert_eq "$code" "0" "conf 충돌도 덮어쓰지 않는다"
after=$(cat "$hypr/hyprland.conf")
assert_eq "$after" "$before" "충돌 시 conf 본문이 그대로다"

# --- 설치 경로 해석 (M5 Task 1) ---
B="$REPO_ROOT/overlay/bin/cachy-omarchy-bindings"

# 1) COO_SRC_HYPR 를 존중한다.
fake_src="$COO_TEST_SANDBOX/prefix/hypr"
mkdir -p "$fake_src"
cp "$REPO_ROOT/overlay/hypr/bindings.conf" "$fake_src/"
cp "$REPO_ROOT/overlay/hypr/bindings.lua" "$fake_src/"
# 소스 경로 해석만 검증하는 케이스이므로, Hyprland 대상 탐지 단계까지
# 통과하도록 충돌 없는 최소 hyprland.conf 픽스처를 둔다(브리프 원문에는
# 없었지만, install_overlay 가 Hyprland 대상 탐지보다 먼저 실행되어
# 이 픽스처 없이는 무관한 사유로 항상 exit 1 이 된다 — 실측으로 확인).
mkdir -p "$COO_TEST_SANDBOX/hypr"
cat >"$COO_TEST_SANDBOX/hypr/hyprland.conf" <<'EOF'
$mainMod = SUPER
bind = $mainMod, Return, exec, ghostty
EOF
out=$(COO_SRC_HYPR="$fake_src" \
      COO_HYPR_DIR="$COO_TEST_SANDBOX/hypr" \
      COO_CONFIG_DIR="$COO_TEST_SANDBOX/cfg" \
      "$B" 2>&1); code=$?
assert_eq "$code" "0" "COO_SRC_HYPR 로 실행 성공"
assert_file_exists "$COO_TEST_SANDBOX/cfg/hypr/bindings.conf" "override 소스에서 복사됨"

# 2) 소스 디렉터리가 없으면 조용히 진행하지 않고 즉시 실패한다.
out=$(COO_SRC_HYPR="$COO_TEST_SANDBOX/nonexistent" \
      COO_HYPR_DIR="$COO_TEST_SANDBOX/hypr2" \
      COO_CONFIG_DIR="$COO_TEST_SANDBOX/cfg2" \
      "$B" 2>&1); code=$?
assert_eq "$code" "1" "소스 부재 → exit 1"
assert_contains "$out" "$COO_TEST_SANDBOX/nonexistent" "오류 메시지가 실제로 없는 경로를 보여준다"
[[ -e "$COO_TEST_SANDBOX/cfg2/hypr/bindings.conf" ]] && half=1 || half=0
assert_eq "$half" "0" "실패 시 반쯤 쓰인 상태를 남기지 않는다"

# 3) 설치 레이아웃을 흉내내도 동작한다: bin 과 share 가 형제가 아니다.
inst="$COO_TEST_SANDBOX/inst"
mkdir -p "$inst/usr/bin" "$inst/usr/share/cachy-omarchy/hypr"
cp "$B" "$inst/usr/bin/cachy-omarchy-bindings"
cp "$REPO_ROOT/overlay/hypr/"*.conf "$REPO_ROOT/overlay/hypr/"*.lua \
   "$inst/usr/share/cachy-omarchy/hypr/"
# 위 1번과 같은 이유로 충돌 없는 hyprland.conf 픽스처가 필요하다.
mkdir -p "$COO_TEST_SANDBOX/hypr3"
cat >"$COO_TEST_SANDBOX/hypr3/hyprland.conf" <<'EOF'
$mainMod = SUPER
bind = $mainMod, Return, exec, ghostty
EOF
out=$(COO_PREFIX_ROOT="$inst/usr/share/cachy-omarchy" \
      COO_HYPR_DIR="$COO_TEST_SANDBOX/hypr3" \
      COO_CONFIG_DIR="$COO_TEST_SANDBOX/cfg3" \
      "$inst/usr/bin/cachy-omarchy-bindings" 2>&1); code=$?
assert_eq "$code" "0" "설치 레이아웃에서 실행 성공"
assert_file_exists "$COO_TEST_SANDBOX/cfg3/hypr/bindings.lua" "PREFIX_ROOT/hypr 에서 복사됨"

# --- --force 재주입 안전성 (M9 후속, 리뷰 블로커) -----------------------------
# inject() --force 경로는 이 스크립트 최초의 파괴적 쓰기다(그 전까지 append 만).
# 게다가 doctor 가 구형 주입에 --force 를 안내하므로 실사용자가 반드시 밟는다.
# 세 가지를 단언한다:
#   ① 스니펫이 같으면 파일을 다시 쓰지 않는다 (mtime 유지 — churn 없음)
#   ② 블록이 파일 중간에 있어도 제자리에서 교체된다 (끝으로 밀지 않는다)
#   ③ 교체가 실패하면 원본을 한 바이트도 건드리지 않는다 (awk 실패 주입)

fresh="$COO_TEST_SANDBOX/fresh-hypr"
mkdir -p "$fresh"
printf 'monitor=,preferred,auto,1\n' > "$fresh/hyprland.conf"
run_fresh() {
  COO_HYPR_DIR="$fresh" COO_CONFIG_DIR="$COO_TEST_SANDBOX/fresh-cfg" "$H" "$@"
}
run_fresh >/dev/null 2>&1
mt1=$(stat -c %Y "$fresh/hyprland.conf")
sleep 1.1
run_fresh --force >/dev/null 2>&1
mt2=$(stat -c %Y "$fresh/hyprland.conf")
assert_eq "$mt2" "$mt1" "--force 는 스니펫이 같으면 다시 쓰지 않는다"

# ② 제자리 교체: 블록이 중간에 있고, 스니펫이 달라지는 경우(DEST_HYPR 경로 변경)
mid="$COO_TEST_SANDBOX/mid-hypr"
mkdir -p "$mid"
cat >"$mid/hyprland.conf" <<EOF
monitor=,preferred,auto,1

# >>> cachy-omarchy >>>
source = $COO_TEST_SANDBOX/old-cfg/hypr/bindings.conf
# <<< cachy-omarchy <<<

bind = SUPER, Return, exec, ghostty
EOF
out=$(COO_HYPR_DIR="$mid" COO_CONFIG_DIR="$COO_TEST_SANDBOX/new-cfg" \
      "$H" --force 2>&1); code=$?
assert_eq "$code" "0" "스니펫 변경 --force → exit 0"
assert_contains "$(cat "$mid/hyprland.conf")" \
  "source = $COO_TEST_SANDBOX/new-cfg/hypr/bindings.conf" "블록 내용이 새 스니펫으로 교체된다"
end_ln=$(grep -n 'cachy-omarchy <<<' "$mid/hyprland.conf" | cut -d: -f1)
user_ln=$(grep -n 'ghostty' "$mid/hyprland.conf" | cut -d: -f1)
[[ -n $end_ln && -n $user_ln && $user_ln -gt $end_ln ]] && pos=0 || pos=1
assert_eq "$pos" "0" "교체 후에도 블록은 제자리 (사용자 줄이 블록 뒤에 남는다)"
n=$(grep -c 'cachy-omarchy >>>' "$mid/hyprland.conf" || true)
assert_eq "$n" "1" "교체 후에도 관리 블록은 한 번만 있다"

# ③ 실패 주입: awk 가 항상 실패하는 환경에서 --force — 원본 보존 + 비정상 종료
failbin="$COO_TEST_SANDBOX/fail-bin"
mkdir -p "$failbin"
printf '#!/usr/bin/env bash\nexit 1\n' > "$failbin/awk"
chmod +x "$failbin/awk"
victim="$COO_TEST_SANDBOX/victim-hypr"
mkdir -p "$victim"
cat >"$victim/hyprland.conf" <<EOF
monitor=,preferred,auto,1

# >>> cachy-omarchy >>>
source = $COO_TEST_SANDBOX/old-cfg/hypr/bindings.conf
# <<< cachy-omarchy <<<

bind = SUPER, Return, exec, ghostty
EOF
cp "$victim/hyprland.conf" "$COO_TEST_SANDBOX/victim.orig"
out=$(PATH="$failbin:$PATH" COO_HYPR_DIR="$victim" \
      COO_CONFIG_DIR="$COO_TEST_SANDBOX/victim-cfg" "$H" --force 2>&1); code=$?
assert_eq "$code" "1" "교체 실패 시 exit 1 (조용한 성공 아님)"
assert_contains "$out" "건드리지 않았다" "실패 시 무엇을 안 했는지 명시한다"
cmp -s "$victim/hyprland.conf" "$COO_TEST_SANDBOX/victim.orig" && same=0 || same=1
assert_eq "$same" "0" "교체 실패 시 원본은 한 바이트도 변하지 않는다"

exit "$ASSERT_FAILURES"
