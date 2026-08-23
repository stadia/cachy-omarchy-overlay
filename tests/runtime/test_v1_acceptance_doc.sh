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

# lane 표는 네 lane 만 정확히 한 번씩 선언한다.
lane_section=$(awk '/^## lane$/ { found=1; next } /^## / { if (found) exit } found { print }' "$doc")
for row in \
  '| `container` | CI (`.github/workflows/ci.yml`) | 설치·의존 해석·init 헤드리스 |' \
  '| `auto-live` | `COO_RUN_LIVE=1 tests/test.sh` | 런처/키바인딩 토글, 앱 실행, 앱 스코프 격리 |' \
  '| `vm` | 깨끗한 VM | init → UWSM 로그인 완주, 업그레이드·롤백·상태 보존 |' \
  '| `host` | 실기기 | 하드웨어, 세션 라이프사이클, polkit |'; do
  assert_contains "$lane_section" "$row" "lane 표 행 유지: $row"
done
lane_rows=$(awk '$0 ~ /^\| / && $0 !~ /^\| lane \|/ && $0 !~ /^\| ---/ { count++ } END { print count + 0 }' <<<"$lane_section")
assert_eq "$lane_rows" "4" "lane 표에는 네 행만 있다"

# 핵심 표 행은 중간에 끊기지 않고 모두 핵심·미검증 상태여야 한다.
core_section=$(awk '/^## 핵심 — 측정됨 필수$/ { found=1; next } /^## 주변/ { if (found) exit } found { print }' "$doc")
polkit_row='| polkit (아래 §polkit) | 핵심 | host | 미검증 | |'
assert_contains "$core_section" "$polkit_row" "polkit 은 핵심 표의 행이다"
if grep -q -B1 -F "$polkit_row" <<<"$core_section" | grep -qx -- ''; then
  printf 'FAIL: polkit 앞에 빈 줄이 없어 핵심 표에 이어진다\n'
  ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
else
  printf 'ok:   polkit 앞에 빈 줄이 없어 핵심 표에 이어진다\n'
fi

while IFS= read -r row; do
  [[ "$row" == '| 항목 |'* || "$row" == '| --- |'* ]] && continue
  if [[ "$row" == '|'* ]]; then
    assert_contains "$row" '| 핵심 |' "핵심 표 행 등급: $row"
    assert_contains "$row" '| 미검증 |' "핵심 표 행 상태: $row"
  fi
done <<<"$core_section"

# 선택 의존 제공자를 쓰는 주변 행은 주변 등급을 유지한다.
for row in 'QR 스캔 / OCR' '화면 녹화' '플로팅 프레젠테이션 터미널'; do
  assert_contains "$text" "| $row | 주변 |" "선택 제공자 항목은 주변: $row"
done

# 알려진 편차와 함정은 문서에 남는다.
assert_contains "$text" "ISA" "ISA 레벨 편차를 기록한다"
assert_contains "$text" "polkit" "polkit 항목이 있다"
assert_contains "$text" "한글 입력기" "polkit 암호 측정의 입력기 함정을 경고한다"

exit "$ASSERT_FAILURES"
