#!/usr/bin/env bash
# toggles seam (v0.11): overlay/hypr/bindings.lua 가
# ~/.local/state/omarchy/toggles/hypr/*.lua 를 정렬 순서로 pcall(dofile) 한다.
# 업스트림 config/hypr/hyprland.lua:26 의 require("default.hypr.toggles") 자리를
# 우리 관리 블록 안에서 채우는 것이다. 이것이 없으면
# omarchy-hyprland-monitor-clamshell 의 disable_internal() 이 아무도 읽지 않는
# 파일만 쓰고 hyprctl reload 한다(dead file — v0.7 shell.json 과 같은 실패 형태).
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

LUA_TPL="$REPO_ROOT/overlay/hypr/bindings.lua"
src=$(<"$LUA_TPL")
assert_contains "$src" "toggles/hypr" "sweep 이 toggles 디렉터리를 본다"
assert_contains "$src" "pcall(dofile" "toggle 로드는 pcall 가드"

# hl 스텁: bindings.lua 의 최상위 hl.* 호출을 전부 흡수하는 permissive 테이블.
# hl.device 만 COO_HL_DEVICE_LOG 에 기록한다 — 4.0.1 의 *-disabled-name 복원이
# 진짜로 hl.device 를 부르는지 잰다.
harness=$COO_TEST_SANDBOX/harness.lua
cat > "$harness" <<'LUA'
local function stub()
  return setmetatable({}, {
    __index = function() return stub() end,
    __call = function() return stub() end,
  })
end
hl = stub()
local device_log = os.getenv("COO_HL_DEVICE_LOG")
if device_log then
  hl.device = function(t)
    local f = io.open(device_log, "a")
    if f then
      f:write("name=" .. tostring(t and t.name) .. " enabled=" .. tostring(t and t.enabled) .. "\n")
      f:close()
    end
    return stub()
  end
end
dofile(os.getenv("COO_BINDINGS_LUA"))
LUA

run_harness() {
  HOME="$1" COO_BINDINGS_LUA="$LUA_TPL" lua "$harness" >/dev/null 2>&1
}

# 경우 1: toggle 파일이 로드된다.
h1=$COO_TEST_SANDBOX/h1
mkdir -p "$h1/.local/state/omarchy/toggles/hypr"
cat > "$h1/.local/state/omarchy/toggles/hypr/10-ok.lua" <<LUA
local f = io.open("$h1/loaded", "w")
f:write("yes")
f:close()
LUA
run_harness "$h1"
assert_file_exists "$h1/loaded" "toggle 파일이 실제로 실행됐다"

# 경우 2: 디렉터리 부재는 정상 경로다 — 조용히 지나간다.
h2=$COO_TEST_SANDBOX/h2
mkdir -p "$h2"
run_harness "$h2"; rc=$?
assert_eq "$rc" "0" "toggles 디렉터리 부재는 오류가 아니다"

# 경우 3: 깨진 toggle 은 격리되고, 정렬상 뒤의 정상 toggle 은 그대로 로드된다.
h3=$COO_TEST_SANDBOX/h3
mkdir -p "$h3/.local/state/omarchy/toggles/hypr"
printf 'this is not lua ((((\n' > "$h3/.local/state/omarchy/toggles/hypr/00-broken.lua"
cat > "$h3/.local/state/omarchy/toggles/hypr/10-ok.lua" <<LUA
local f = io.open("$h3/loaded", "w")
f:write("yes")
f:close()
LUA
run_harness "$h3"; rc=$?
assert_eq "$rc" "0" "깨진 toggle 이 설정 전체를 죽이지 않는다"
assert_file_exists "$h3/loaded" "깨진 toggle 뒤의 정상 toggle 이 로드된다"

# 경우 4: 파일명에 개행이 들어가도 경로가 잘리지 않는다. find -print0 + NUL 분리
# 이전에는 `find | sort` 의 줄 단위 읽기가 개행에서 경로를 두 조각으로 잘라,
# 두 조각 중 어느 것도 실재하지 않아 toggle 이 조용히 로드되지 않았다.
# 위험도는 낮다(정상 omarchy 헬퍼는 고정된 이름만 쓴다) — 그래도 sweep 이
# 파일명을 해석하지 않고 그대로 다루는지는 고정해 둔다.
h4=$COO_TEST_SANDBOX/h4
mkdir -p "$h4/.local/state/omarchy/toggles/hypr"
nl_toggle=$(printf '%s/.local/state/omarchy/toggles/hypr/10-new
line.lua' "$h4")
cat > "$nl_toggle" <<LUA
local f = io.open("$h4/loaded-newline", "w")
f:write("yes")
f:close()
LUA
run_harness "$h4"; rc=$?
assert_eq "$rc" "0" "개행 파일명이 설정을 죽이지 않는다"
assert_file_exists "$h4/loaded-newline" "개행이 든 파일명의 toggle 도 로드된다"

# 경우 5 (4.0.1): 레거시 touchpad-disabled.lua / touchscreen-disabled.lua 는
# 절대 코드로 로드하지 않는다. 업스트림 4.0.1 toggles.lua 의 exclude 와 같은
# 계약이다 — 이 파일들은 구버전에서 생성됐고 USB 디스크립터의 장치 이름이
# Lua 코드로 들어가던 형태라, 아직 마이그레이션되지 않은 설치에서 리로드마다
# 주입된 람다를 실행하는 통로가 된다. sweep 이 제외 목록을 적용하지 않으면
# 그 통로를 우리만 열어 두는 셈이다.
h5=$COO_TEST_SANDBOX/h5
mkdir -p "$h5/.local/state/omarchy/toggles/hypr"
for kind in touchpad touchscreen; do
  cat > "$h5/.local/state/omarchy/toggles/hypr/$kind-disabled.lua" <<LUA
local f = io.open("$h5/pwned-$kind", "w")
f:write("yes")
f:close()
LUA
done
run_harness "$h5"; rc=$?
assert_eq "$rc" "0" "레거시 *-disabled.lua 가 있어도 설정이 죽지 않는다"
for kind in touchpad touchscreen; do
  [[ -e $h5/pwned-$kind ]] && x=1 || x=0
  assert_eq "$x" "0" "레거시 $kind-disabled.lua 는 실행되지 않는다"
done

# 경우 6 (4.0.1): *-disabled-name 은 데이터로 읽어 hl.device({ name, enabled
# = false }) 를 부른다 — 업스트림 default/hypr/disabled-input-device.lua 자리.
# 장치 이름을 코드로 합성하지 않는다(문자열 보간으로 Lua/쉘을 만들지 않는다).
h6=$COO_TEST_SANDBOX/h6
mkdir -p "$h6/.local/state/omarchy/toggles/hypr"
printf 'test-touchpad\n' > "$h6/.local/state/omarchy/toggles/hypr/touchpad-disabled-name"
printf 'test-touchscreen; touch /tmp/owned\n' \
  > "$h6/.local/state/omarchy/toggles/hypr/touchscreen-disabled-name"
COO_HL_DEVICE_LOG="$h6/devices.log" run_harness "$h6"; rc=$?
assert_eq "$rc" "0" "*-disabled-name 복원이 설정을 죽이지 않는다"
assert_file_exists "$h6/devices.log" "disabled-name 이 있으면 hl.device 를 부른다"
assert_contains "$(cat "$h6/devices.log")" "name=test-touchpad enabled=false" \
  "touchpad-disabled-name 이 장치를 끈다"
assert_contains "$(cat "$h6/devices.log")" \
  "name=test-touchscreen; touch /tmp/owned enabled=false" \
  "장치 이름은 코드가 아니라 데이터로 전달된다"
[[ -e $h6/owned ]] && x=1 || x=0
assert_eq "$x" "0" "장치 이름 속 명령은 실행되지 않는다"

# 경우 7 (4.0.1): 비어 있는 *-disabled-name 은 hl.device 호출을 만들지
# 않는다(업스트림의 name ~= "" 가드).
h7=$COO_TEST_SANDBOX/h7
mkdir -p "$h7/.local/state/omarchy/toggles/hypr"
: >"$h7/.local/state/omarchy/toggles/hypr/touchpad-disabled-name"
COO_HL_DEVICE_LOG="$h7/devices.log" run_harness "$h7"; rc=$?
assert_eq "$rc" "0" "빈 disabled-name 은 오류가 아니다"
[[ -s $h7/devices.log ]] && x=1 || x=0
assert_eq "$x" "0" "빈 disabled-name 은 hl.device 를 부르지 않는다"

# conf 경로: .lua 글롭을 받지 않는다(2026-08-23 중첩 Hyprland 실측 —
# source = <dir>/*.lua 자체는 파싱 오류를 내지 않지만, 그 안의 Lua 는
# 실행되지 않고 일반 config 키워드 줄로 취급돼 조용히 버려진다). 관리
# 블록에 글롭 source 를 넣지 않는 것이 확정 동작이며, 대신 doctor 가 WARN.
src_bindings=$(<"$REPO_ROOT/overlay/bin/cachy-omarchy-bindings")
grep -q "toggles/hypr" <<<"$src_bindings" && x=1 || x=0
assert_eq "$x" "0" "conf 스니펫은 toggles 글롭을 넣지 않는다"
src_doctor=$(<"$REPO_ROOT/overlay/bin/cachy-omarchy-doctor")
assert_contains "$src_doctor" "toggles/hypr" "doctor 가 conf 사용자에게 WARN 한다"

# 위 grep 은 블록이 통째로 지워지는 것만 잡는다 — 변수 오타나 조건 반전은
# 못 잡는다. doctor 를 실제로 실행해 네 가지 상태에서 WARN 유무를 잰다.
ddir=$COO_TEST_SANDBOX/doctor
WARN_TXT="omarchy hypr toggles are not applied"
run_doctor_seam() {
  local hypr=$1 omarchy_state=$2
  HOME="$ddir/home" COO_HYPR_DIR="$hypr" COO_CONFIG_DIR="$ddir/home/.config/cachy-omarchy" \
    COO_OMARCHY_STATE_DIR="$omarchy_state" COO_STATE_DIR="$ddir/home/.local/state/cachy-omarchy" \
    COO_OMARCHY_CONFIG_DIR="$ddir/home/.config/omarchy" \
    "$REPO_ROOT/overlay/bin/cachy-omarchy-doctor" 2>&1
}

# 상태 1: conf 만 있고 lua 없음 + toggles 파일 있음 → WARN 이 실제로 찍힌다.
s1=$ddir/s1
mkdir -p "$s1/hypr" "$s1/state/toggles/hypr"
printf 'monitor=,preferred,auto,1\n' > "$s1/hypr/hyprland.conf"
printf 'hl.monitor({ output = "HEADLESS-1", disabled = true })\n' \
  > "$s1/state/toggles/hypr/10-clamshell.lua"
out1=$(run_doctor_seam "$s1/hypr" "$s1/state")
assert_contains "$out1" "$WARN_TXT" "conf+toggles 실행 시 doctor 가 실제로 WARN 을 출력한다"

# 상태 2: 같은 conf, toggles 파일이 없음 → WARN 없음.
s2=$ddir/s2
mkdir -p "$s2/hypr" "$s2/state"
printf 'monitor=,preferred,auto,1\n' > "$s2/hypr/hyprland.conf"
out2=$(run_doctor_seam "$s2/hypr" "$s2/state")
grep -qF "$WARN_TXT" <<<"$out2" && x=1 || x=0
assert_eq "$x" "0" "toggles 파일이 없으면 WARN 을 내지 않는다"

# 상태 3: conf 도 있고 hyprland.lua 도 있음(사용자가 lua 로 옮긴 상태) +
# toggles 파일 있음 → WARN 없음(hyprland.lua 존재가 조건을 막는다).
s3=$ddir/s3
mkdir -p "$s3/hypr" "$s3/state/toggles/hypr"
printf 'monitor=,preferred,auto,1\n' > "$s3/hypr/hyprland.conf"
printf 'hl.monitor(",preferred,auto,1")\n' > "$s3/hypr/hyprland.lua"
printf 'hl.monitor({ output = "HEADLESS-1", disabled = true })\n' \
  > "$s3/state/toggles/hypr/10-clamshell.lua"
out3=$(run_doctor_seam "$s3/hypr" "$s3/state")
grep -qF "$WARN_TXT" <<<"$out3" && x=1 || x=0
assert_eq "$x" "0" "hyprland.lua 가 있으면 WARN 을 내지 않는다"

# 상태 4: hyprland.conf 자체가 없음(lua 만) + toggles 파일 있음 → WARN 없음.
s4=$ddir/s4
mkdir -p "$s4/hypr" "$s4/state/toggles/hypr"
printf 'hl.monitor(",preferred,auto,1")\n' > "$s4/hypr/hyprland.lua"
printf 'hl.monitor({ output = "HEADLESS-1", disabled = true })\n' \
  > "$s4/state/toggles/hypr/10-clamshell.lua"
out4=$(run_doctor_seam "$s4/hypr" "$s4/state")
grep -qF "$WARN_TXT" <<<"$out4" && x=1 || x=0
assert_eq "$x" "0" "hyprland.conf 가 없으면 WARN 을 내지 않는다"

exit "$ASSERT_FAILURES"
