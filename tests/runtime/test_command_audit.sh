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

# --- 스테이징 집합 ⇔ 전수 표 분류 -----------------------------------------
#
# menu_audit_check.py 는 한 방향만 본다: 메뉴에 보이는 이름이 표에 있는가.
# 반대 방향 — 우리가 실제로 스테이징해 `/usr/bin` 에 노출한 helper 가 표에
# 있는가, 그리고 표가 그것을 DISABLED 라 부르고 있지는 않은가 — 는 아무도
# 보지 않았다. 그 사각에서 표가 조용히 낡았다: M9 테마 체인과 M10 전이
# closure 가 통째로 분류 없이 들어왔고, 채택된 helper 몇 개는 표에서 여전히
# DISABLED 였다. 스테이징 배열이 단일 정의이므로(SPEC §45) 그것을 기준으로
# 잡는다.
staged=$(awk '/^helpers=\(/,/^\)/' \
  "$REPO_ROOT/packages/cachy-omarchy-shell/stage-upstream.sh" \
  | grep -v '^[[:space:]]*#' \
  | grep -oE '\bomarchy-[a-z0-9-]+' | sort -u)
[[ -n $staged ]] && parsed=0 || parsed=1
assert_eq "$parsed" "0" "stage-upstream.sh 의 helpers 배열을 파싱했다"

# 두 전수 표에서 각각 `이름 분류` 를 뽑는다.
census_of() { # $1 = BEGIN 마커 이름
  awk -v b="${1}_BEGIN" -v e="${1}_END" '$0 ~ b, $0 ~ e' "$AUDIT" \
    | sed -n 's/^| `\(omarchy-[a-z0-9-]*\)` *| *\(SAFE\|ADAPTED\|DISABLED\) *|.*/\1 \2/p' \
    | sort -u
}
staged_census=$(census_of STAGED_AUDIT)
menu_census=$(census_of MENU_AUDIT)
[[ -n $staged_census && -n $menu_census ]] && parsed=0 || parsed=1
assert_eq "$parsed" "0" "두 전수 표에서 분류 행을 파싱했다"

# (1) 올린 것은 전부 스테이징 전수에 있어야 한다.
unclassified=$(comm -23 <(printf '%s\n' "$staged") \
  <(awk '{print $1}' <<<"$staged_census") | tr '\n' ' ')
assert_eq "${unclassified% }" "" "스테이징된 helper 가 전부 스테이징 전수 표에 있다"

# 반대 방향도 막는다 — 배열에서 빠진 helper 가 표에만 남아 유령이 되면 안 된다.
phantom=$(comm -13 <(printf '%s\n' "$staged") \
  <(awk '{print $1}' <<<"$staged_census") | tr '\n' ' ')
assert_eq "${phantom% }" "" "스테이징 전수 표에 배열이 안 올리는 유령 행이 없다"

# (2) 올린 것을 DISABLED 라 부르는 행이 어느 표에도 없어야 한다.
disabled_staged=$(awk '$2=="DISABLED"{print $1}' <<<"$staged_census
$menu_census" | sort -u | comm -12 - <(printf '%s\n' "$staged") | tr '\n' ' ')
assert_eq "${disabled_staged% }" "" "스테이징된 helper 를 DISABLED 로 분류한 행이 없다"

# (3) 두 표가 겹치는 행에서 분류가 갈라지면 안 된다 — 같은 명령이 표마다 다른
#     등급을 갖는 것이 이 문서가 조용히 낡던 방식이었다.
conflict=$(join <(printf '%s\n' "$staged_census") <(printf '%s\n' "$menu_census") \
  | awk '$2 != $3 {printf "%s(%s vs %s) ", $1, $2, $3}')
assert_eq "${conflict% }" "" "두 전수 표가 겹치는 행에서 같은 분류를 쓴다"

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
