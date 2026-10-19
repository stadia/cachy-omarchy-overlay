#!/usr/bin/env bash
# toggles seam (#12): overlay/hypr/bindings.lua 가 업스트림 bootstrap.lua 로
# package.path 를 세운 뒤 require("default.hypr.toggles") 를 부른다. 업스트림
# config/hypr/hyprland.lua:26 의 자리를 우리 관리 블록 안에서 채우는 것이다.
# 이것이 없으면 omarchy-hyprland-monitor-clamshell 의 disable_internal() 이
# 아무도 읽지 않는 파일만 쓰고 hyprctl reload 한다(dead file).
#
# 하네스는 빌드된 shell 패키지를 추출한 업스트림 트리(OMARCHY_PATH)에서 돈다 —
# 스테이징된 require 체인(bootstrap/toggles/paths/require_all/...)이 실제로
# 성립하는지까지 같이 재기 위해서다. Hyprland 자체의 require 래핑(에러를 config
# 에러로 보고하고 계속 진행)은 이 스텁에 없다 — 그건 중첩 Hyprland 실측 몫이다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/lib/runtime.sh"

LUA_TPL="$REPO_ROOT/overlay/hypr/bindings.lua"
src=$(<"$LUA_TPL")
assert_contains "$src" 'require("default.hypr.toggles")' "업스트림 toggles 를 require 한다"
assert_contains "$src" "bootstrap.lua" "bootstrap 으로 package.path 를 세운다"
assert_contains "$src" "pcall(function()" "toggles 진입은 pcall 가드"
[[ $src == *"find "* ]] && x=1 || x=0
assert_eq "$x" "0" "재구현 sweep(find) 이 남아 있지 않다"

pkgroot=$COO_TEST_SANDBOX/pkgroot
if ! coo_extract_pkg "$pkgroot"; then
  printf 'FAIL: shell 패키지 아티팩트가 없다 — bin/build-packages 먼저\n'
  exit 1
fi
OMARCHY_ROOT=$(coo_upstream_root "$pkgroot")
assert_file_exists "$OMARCHY_ROOT/default/hypr/toggles.lua" "패키지에 업스트림 toggles.lua 가 있다"

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

# env -u XDG_STATE_HOME: 호스트 값이 새어 들어가면 임시 HOME 을 보지 않는다.
run_harness() {
  env -u XDG_STATE_HOME HOME="$1" OMARCHY_PATH="${COO_OMARCHY_PATH-$OMARCHY_ROOT}" \
    COO_BINDINGS_LUA="$LUA_TPL" lua "$harness" >/dev/null 2>&1
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

# 경우 3: 깨진 toggle 이 있어도 설정 전체는 죽지 않는다(pcall 가드). 이 스텁에서는
# 업스트림 require_all 이 첫 에러에서 멈추므로 뒤의 toggle 이 로드되는지는 재지
# 않는다 — 실제 Hyprland 의 require 는 에러를 config 에러로 보고하고 계속
# 진행한다(2026-10-19 중첩 인스턴스 실측, #12 PR 본문).
h3=$COO_TEST_SANDBOX/h3
mkdir -p "$h3/.local/state/omarchy/toggles/hypr"
printf 'this is not lua ((((\n' > "$h3/.local/state/omarchy/toggles/hypr/00-broken.lua"
run_harness "$h3"; rc=$?
assert_eq "$rc" "0" "깨진 toggle 이 설정 전체를 죽이지 않는다"

# 경우 4: 워크스페이스 레이아웃 파일이 있어도 에러 없이 복원된다. package.path 에
# $OMARCHY_PATH/?.lua 만 붙이면 omarchy.workspace-layouts.* 를 못 찾아 config 에러가
# 나던 경로다(bootstrap.lua 가 ~/.local/state/?.lua 를 올려 해결).
h4=$COO_TEST_SANDBOX/h4
mkdir -p "$h4/.local/state/omarchy/workspace-layouts"
cat > "$h4/.local/state/omarchy/workspace-layouts/3.lua" <<LUA
local f = io.open("$h4/layout-loaded", "w")
f:write("yes")
f:close()
LUA
run_harness "$h4"; rc=$?
assert_eq "$rc" "0" "레이아웃 파일이 있어도 설정이 죽지 않는다"
assert_file_exists "$h4/layout-loaded" "워크스페이스 레이아웃 파일이 실행된다"

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

# 경우 8: OMARCHY_PATH 가 없는 환경(uwsm 드롭인 미적용)은 조용히 지나간다 —
# toggle 은 로드되지 않지만 설정은 죽지 않는다.
h8=$COO_TEST_SANDBOX/h8
mkdir -p "$h8/.local/state/omarchy/toggles/hypr"
cat > "$h8/.local/state/omarchy/toggles/hypr/10-ok.lua" <<LUA
local f = io.open("$h8/loaded", "w")
f:write("yes")
f:close()
LUA
COO_OMARCHY_PATH="" run_harness "$h8"; rc=$?
assert_eq "$rc" "0" "OMARCHY_PATH 가 비어 있어도 오류가 아니다"
[[ -e $h8/loaded ]] && x=1 || x=0
assert_eq "$x" "0" "OMARCHY_PATH 없이는 toggle 을 로드하지 않는다"

# 경우 9: 업스트림 트리가 없는 경로(구버전 shell 패키지)도 조용히 지나간다.
h9=$COO_TEST_SANDBOX/h9
mkdir -p "$h9"
COO_OMARCHY_PATH="$h9/no-such-tree" run_harness "$h9"; rc=$?
assert_eq "$rc" "0" "bootstrap.lua 부재는 오류가 아니다"

exit "$ASSERT_FAILURES"
