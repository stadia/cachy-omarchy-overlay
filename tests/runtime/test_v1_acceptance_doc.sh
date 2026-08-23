#!/usr/bin/env bash
# 1.0 게이트를 소유하는 문서의 구조와 어휘를 고정한다.
#
# RC_GAP_INVENTORY.md 는 M7 시점 SPEC §61 에 묶여 있고 지금 목록은 그보다
# 넓다(하드웨어·업그레이드·polkit). 기존 문서는 역사적 기록으로 두고 이
# 문서가 게이트를 소유한다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

doc="$REPO_ROOT/docs/V1_ACCEPTANCE.md"
assert_file_exists "$doc" "1.0 acceptance 문서가 있다"
text=$(cat "$doc" 2>/dev/null)

# 증거 어휘 세 가지. 새 단어를 만들지 않는다.
for w in 측정됨 추론됨 미검증; do
  assert_contains "$text" "$w" "증거 등급 어휘 유지: $w"
done

# 등급 규칙이 문서 자체에 박혀 있어야 나중에 판정이 흔들리지 않는다.
assert_contains "$text" "핵심" "핵심 등급을 정의한다"
assert_contains "$text" "주변" "주변 등급을 정의한다"

# lane 네 개.
for l in container auto-live vm host; do
  assert_contains "$text" "$l" "lane 정의: $l"
done

# 알려진 편차와 함정은 문서에 남는다.
assert_contains "$text" "ISA" "ISA 레벨 편차를 기록한다"
assert_contains "$text" "polkit" "polkit 항목이 있다"
assert_contains "$text" "한글 입력기" "polkit 암호 측정의 입력기 함정을 경고한다"

exit "$ASSERT_FAILURES"
