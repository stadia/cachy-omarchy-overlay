#!/usr/bin/env bash
# 지원 계약이 다섯 곳에서 갈라지지 않게 고정한다.
#
# 동작은 이미 A(=hyprland.lua 전용)다 — doctor 가 WARN 하고 seam 테스트가
# 그것을 측정한다. 빠진 것은 이것이 "약속된 경계"로 선언되지 않았다는 점이며,
# 문서만 두면 다음 리팩터에서 WARN 문구가 바뀌고 계약이 조용히 갈라진다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

CONTRACT="Lua toggle 파일은 hyprland.lua 설정에서만 적용된다"
DOCTOR_PREFIX="hyprland.conf setup: omarchy hypr toggles are not applied"
DOCTOR_GUIDANCE="clamshell/monitor toggles are ignored — switch to a hyprland.lua config"

spec=$(cat "$REPO_ROOT/SPEC.md")
assert_contains "$spec" "지원 계약" "SPEC 에 지원 계약 절이 있다"
assert_contains "$spec" "$CONTRACT" "SPEC 이 계약 문구를 쓴다"

# README 는 이미 lua/conf 경계를 설명한다. 새 기능을 선언하지 않고 이
# 기존 경계를 같은 계약 문구로 명시한다.
for r in README.md README.ko-KR.md; do
  assert_contains "$(cat "$REPO_ROOT/$r")" "$CONTRACT" "$r 이 계약 문구를 쓴다"
done

doctor=$(cat "$REPO_ROOT/overlay/bin/cachy-omarchy-doctor")
assert_contains "$doctor" "$DOCTOR_PREFIX" "doctor WARN 의 실제 앞문구를 유지한다"
assert_contains "$doctor" "$DOCTOR_GUIDANCE" "doctor WARN 의 실제 안내문을 유지한다"

init=$(cat "$REPO_ROOT/overlay/bin/cachy-omarchy-init")
assert_contains "$init" "$CONTRACT" "init 이 conf 사용자에게 계약을 고지한다"

exit "$ASSERT_FAILURES"
