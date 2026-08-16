#!/usr/bin/env bash
# Task 5: every omarchy-* visible from the packaged menu is classified.
# Does not reimplement the menu. Does not install official omarchy-*.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/lib/runtime.sh"

AUDIT="$REPO_ROOT/docs/COMMAND_AUDIT.md"
assert_file_exists "$AUDIT" "COMMAND_AUDIT.md 존재"
audit=$(cat "$AUDIT")
assert_contains "$audit" "SAFE" "분류 SAFE"
assert_contains "$audit" "ADAPTED" "분류 ADAPTED"
assert_contains "$audit" "DISABLED" "분류 DISABLED"
assert_contains "$audit" "MENU_AUDIT_BEGIN" "메뉴 전수 표 시작 마커"
assert_contains "$audit" "MENU_AUDIT_END" "메뉴 전수 표 끝 마커"
assert_contains "$audit" "비활성 경로" "비활성 경로가 문서화되어 있다"
assert_contains "$audit" "REIMPLEMENT 아님" "REIMPLEMENT 아님을 명시한다"
assert_contains "$audit" "바이너리 부재" "비활성 경로는 공식 bin 미설치를 쓴다"
assert_contains "$audit" "M5" "숨김/오버레이는 M5 로 미룬다"

dest="$COO_TEST_SANDBOX/pkg"
if ! coo_extract_pkg "$dest" 2>/dev/null; then
  echo "skip: 추출 실패"
  exit "$ASSERT_FAILURES"
fi
root=$(coo_upstream_root "$dest")
menu="$root/default/omarchy/omarchy-menu.jsonc"
qml="$root/shell/plugins/menu/Menu.qml"
assert_file_exists "$menu" "스테이징된 omarchy-menu.jsonc"

report=$COO_TEST_SANDBOX/menu-audit.report
if python3 "$REPO_ROOT/tests/runtime/menu_audit_check.py" "$AUDIT" "$menu" "$qml" >"$report"; then
  while IFS= read -r line; do
    printf '%s\n' "$line"
  done <"$report"
else
  while IFS= read -r line; do
    printf '%s\n' "$line"
  done <"$report"
  printf 'FAIL: 메뉴 전수 분류 대조\n'
  ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
fi

exit "$ASSERT_FAILURES"
