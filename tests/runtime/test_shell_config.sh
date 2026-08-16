#!/usr/bin/env bash
# 패키지에 스테이징된 기본 shell.json 이 사용자 데스크톱과 충돌하는
# 플러그인을 끄는지 검증한다. SPEC 4.3 / 17.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/lib/runtime.sh"

SRC="$REPO_ROOT/overlay/defaults/shell.json"
assert_file_exists "$SRC" "기본값 정본 존재"
[[ -f $SRC ]] || exit 1

command -v jq >/dev/null || { echo "skip: jq 없음"; exit 0; }

assert_eq "$(jq -r '.version' "$SRC")" "1" "version: 1 (없으면 셸이 무시한다)"

for w in left center right; do
  assert_eq "$(jq -r ".bar.layout.$w | length" "$SRC")" "0" "bar.layout.$w 비어 있음"
done

# 사용자 데스크톱과 겹치는 플러그인은 반드시 꺼져 있어야 한다.
for p in omarchy.bar omarchy.notifications omarchy.lock omarchy.osd \
         omarchy.idle omarchy.polkit omarchy.background; do
  has=$(jq -r --arg p "$p" '.disabledPlugins | index($p) != null' "$SRC")
  assert_eq "$has" "true" "$p 비활성"
done

# 메뉴는 절대 꺼지면 안 된다 — M3 의 런처가 이것이다.
has=$(jq -r '.disabledPlugins | index("omarchy.menu") != null' "$SRC")
assert_eq "$has" "false" "omarchy.menu 는 활성 유지"

# 패키지에 실제로 우리 파일이 들어갔는지 (업스트림 것이 아니라)
if artifact=$(coo_pkg_artifact); then
  dest="$COO_TEST_SANDBOX/pkg"
  coo_extract_pkg "$dest"
  staged="$(coo_upstream_root "$dest")/config/omarchy/shell.json"
  assert_file_exists "$staged" "스테이징된 shell.json"
  assert_eq "$(jq -S . "$staged")" "$(jq -S . "$SRC")" "스테이징된 파일 == 우리 정본"
else
  echo "note: 아티팩트 없음 — 스테이징 검증 생략"
fi

exit "$ASSERT_FAILURES"
