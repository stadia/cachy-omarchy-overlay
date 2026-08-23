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

# 핵심·주변 표를 각 섹션의 정확한 헤더에서만 읽어 열 위치까지 검사한다.
gate_tables=$(awk '
function trim(value) {
  sub(/^[[:space:]]+/, "", value)
  sub(/[[:space:]]+$/, "", value)
  return value
}
function fail(message) {
  if (!failed) reason = message
  failed = 1
}
function valid_lane(lane) {
  return lane == "container" || lane == "auto-live" || lane == "vm" || lane == "host"
}
function count_occurrences(line, needle, start, offset) {
  start = 1
  while ((offset = index(substr(line, start), needle)) != 0) {
    occurrences[needle]++
    start += offset + length(needle) - 1
  }
}
function parse_row(kind, line, fields, count, item, grade, lane, status) {
  count = split(line, fields, "|")
  if (count != 7 || trim(fields[1]) != "" || trim(fields[7]) != "") {
    fail(kind " 표 행은 다섯 열이어야 한다")
    return
  }

  item = trim(fields[2])
  grade = trim(fields[3])
  lane = trim(fields[4])
  status = trim(fields[5])
  if (item == "") fail(kind " 표 항목 열이 비어 있다")
  if (!valid_lane(lane)) fail(kind " 표 lane 열이 유효하지 않다")

  if (kind == "핵심") {
    if (grade != "핵심") fail("핵심 표 등급 열이 핵심이 아니다")
    if (status != "미검증") fail("핵심 표 상태 열이 미검증이 아니다")
    core_items[item]++
    if (item == "polkit (아래 §polkit)") core_polkit++
  } else {
    if (grade != "주변") fail("주변 표 등급 열이 주변이 아니다")
    if (status != "미검증") fail("주변 표 상태 열이 미검증이 아니다")
    peripheral_items[item]++
  }
}
{
  count_occurrences($0, "QR 스캔 / OCR")
  count_occurrences($0, "화면 녹화")
  count_occurrences($0, "플로팅 프레젠테이션 터미널")
}
$0 == "## 핵심 — 측정됨 필수" {
  phase = "core-before-header"
  next
}
$0 == "## 주변 — 미검증 문서화 허용" {
  phase = "peripheral-before-header"
  next
}
phase == "core-before-header" {
  if ($0 == "| 항목 | 등급 | lane | 상태 | 증거 |") {
    core_header = 1
    phase = "core-separator"
  }
  next
}
phase == "core-separator" {
  if ($0 != "| --- | --- | --- | --- | --- |") fail("핵심 표 헤더 구분선이 없다")
  phase = "core-rows"
  next
}
phase == "core-rows" {
  if ($0 == "") {
    core_blank = 1
    next
  }
  if (core_blank || $0 !~ /^\|/) {
    fail("핵심 표 안에 빈 줄 또는 표 밖 텍스트가 있다")
    next
  }
  parse_row("핵심", $0)
  core_rows++
  next
}
phase == "peripheral-before-header" {
  if ($0 == "| 항목 | 등급 | lane | 상태 | 증거 |") {
    peripheral_header = 1
    phase = "peripheral-separator"
  }
  next
}
phase == "peripheral-separator" {
  if ($0 != "| --- | --- | --- | --- | --- |") fail("주변 표 헤더 구분선이 없다")
  phase = "peripheral-rows"
  next
}
phase == "peripheral-rows" && /^## / {
  phase = "after-peripheral"
  next
}
phase == "peripheral-rows" {
  if ($0 == "") {
    peripheral_blank = 1
    next
  }
  if (peripheral_blank || $0 !~ /^\|/) {
    fail("주변 표 안에 빈 줄 또는 표 밖 텍스트가 있다")
    next
  }
  parse_row("주변", $0)
  peripheral_rows++
  next
}
END {
  if (!core_header || core_rows == 0) fail("핵심 표를 찾지 못했다")
  if (core_polkit != 1) fail("polkit 핵심 항목은 정확히 한 행이어야 한다")
  if (!peripheral_header || peripheral_rows == 0) fail("주변 표를 찾지 못했다")
  if (peripheral_items["QR 스캔 / OCR"] != 1 || occurrences["QR 스캔 / OCR"] != 1) fail("QR 스캔 / OCR 은 주변 표에만 한 번 있어야 한다")
  if (peripheral_items["화면 녹화"] != 1 || occurrences["화면 녹화"] != 1) fail("화면 녹화는 주변 표에만 한 번 있어야 한다")
  if (peripheral_items["플로팅 프레젠테이션 터미널"] != 1 || occurrences["플로팅 프레젠테이션 터미널"] != 1) fail("프레젠테이션 터미널은 주변 표에만 한 번 있어야 한다")
  print failed ? reason : "ok"
}
' "$doc")
assert_eq "$gate_tables" "ok" "게이트 표의 열 구조와 항목 위치를 유지한다"

# 선택 제공자를 쓰는 주변 항목의 판정 근거를 문서에 남긴다.
assert_contains "$text" "스크린샷은 핵심" "스크린샷 핵심 판정을 설명한다"
assert_contains "$text" "선택 의존성" "녹화·프레젠테이션 주변 판정을 설명한다"

# 알려진 편차와 함정은 문서에 남는다.
assert_contains "$text" "ISA" "ISA 레벨 편차를 기록한다"
assert_contains "$text" "polkit" "polkit 항목이 있다"
assert_contains "$text" "한글 입력기" "polkit 암호 측정의 입력기 함정을 경고한다"

exit "$ASSERT_FAILURES"
