#!/usr/bin/env bash
# M8 원칙 0: 신규 설치에서 바가 기본으로 보인다 — init 은 bar-off 를 만들지
# 않는다. 이미 있는 사용자 상태는 건드리지 않는다 (SPEC 6.6).
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

INIT="$REPO_ROOT/overlay/bin/cachy-omarchy-init"
DOCTOR="$REPO_ROOT/overlay/bin/cachy-omarchy-doctor"
assert_file_exists "$INIT" "init 존재"

home=$COO_TEST_SANDBOX/inithome
state=$home/.local/state/omarchy
conf=$home/.config/cachy-omarchy
hypr=$home/.config/hypr
mkdir -p "$state" "$conf" "$hypr"

run_init() {
  HOME="$home" COO_STATE_DIR="$state" COO_CONFIG_DIR="$conf" COO_HYPR_DIR="$hypr" \
    "$INIT" >/dev/null 2>&1
}

run_init
[[ -e $state/toggles/bar-off ]] && x=1 || x=0
assert_eq "$x" "0" "init 은 bar-off 를 만들지 않는다"

# toggles 디렉터리조차 만들지 않는다 — 만들면 다음 init 이 "사용자 상태 존재"
# 로 오독할 근거를 스스로 심는 셈이다.
[[ -e $state/toggles ]] && x=1 || x=0
assert_eq "$x" "0" "init 은 toggles 디렉터리도 만들지 않는다"

# 사용자가 이미 가진 bar-off 는 유지된다.
mkdir -p "$state/toggles"; : > "$state/toggles/bar-off"
run_init
assert_file_exists "$state/toggles/bar-off" "기존 bar-off 는 지우지 않는다"

# doctor 는 삭제 방법을 안내한다 (자동 삭제 금지). doctor 의 STATE_DIR 은
# cachy-omarchy 상태이고 bar-off 가 사는 곳은 omarchy 상태라 다른 변수다.
out=$(HOME="$home" COO_OMARCHY_STATE_DIR="$state" COO_CONFIG_DIR="$conf" \
  "$DOCTOR" 2>&1)
assert_contains "$out" "bar-off" "doctor 가 bar-off 를 언급한다"
assert_contains "$out" "WARN" "안내는 기존 출력 함수(WARN)로 나간다"
assert_file_exists "$state/toggles/bar-off" "doctor 는 삭제하지 않는다"

# 없으면 조용하지 않고 PASS 로 명시한다 — 침묵은 "점검했다" 의 증거가 못 된다.
rm -f "$state/toggles/bar-off"
out=$(HOME="$home" COO_OMARCHY_STATE_DIR="$state" COO_CONFIG_DIR="$conf" \
  "$DOCTOR" 2>&1)
assert_contains "$out" "bar-off toggle absent" "없으면 PASS 한 줄로 보고한다"

exit "$ASSERT_FAILURES"
