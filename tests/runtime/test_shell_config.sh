#!/usr/bin/env bash
# 패키지 정본 shell.json 이 업스트림 기본값 그대로인지 검증한다.
# M8 원칙 0: upstream 기본값이 기본, 억제는 실측 충돌이 있을 때만 예외.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/lib/runtime.sh"

SRC="$REPO_ROOT/overlay/defaults/shell.json"
assert_file_exists "$SRC" "기본값 정본 존재"
[[ -f $SRC ]] || exit 1

command -v jq >/dev/null || { echo "skip: jq 없음"; exit 0; }

assert_eq "$(jq -r '.version' "$SRC")" "1" "version: 1 (없으면 셸이 무시한다)"

# 억제 해제: 빈 layout 도 disabledPlugins 도 없다.
total=$(jq -r '[.bar.layout.left, .bar.layout.center, .bar.layout.right]
               | map(length) | add' "$SRC")
assert_eq "$total" "14" "업스트림 기본 layout 14개 위젯"
assert_eq "$(jq -r 'has("disabledPlugins")' "$SRC")" "false" \
  "disabledPlugins 키 없음 (11개 전부 해제)"
assert_eq "$(jq -r '.bar.layout.left[0].id' "$SRC")" "omarchy.menu" \
  "left 첫 위젯은 omarchy.menu"

# upstream fidelity: 정본은 핀 커밋의 업스트림 파일과 내용이 같아야 한다.
UPSTREAM_GIT=${COO_OMARCHY_GIT:-$REPO_ROOT/build/omarchy}
PINNED=$(grep -oP "^_commit='\K[0-9a-f]+" \
  "$REPO_ROOT/packages/cachy-omarchy-shell/PKGBUILD")
if [[ -d $UPSTREAM_GIT/.git ]]; then
  upstream_json=$(git -C "$UPSTREAM_GIT" show \
    "$PINNED:config/omarchy/shell.json" 2>/dev/null)
  if [[ -n $upstream_json ]]; then
    assert_eq "$(jq -S . <<<"$upstream_json")" "$(jq -S . "$SRC")" \
      "정본 == 핀 커밋 업스트림 기본값 (드리프트 없음)"
  else
    echo "note: 핀 커밋에서 shell.json 을 읽지 못함 — 드리프트 검증 생략"
  fi
else
  echo "note: build/omarchy 클론 없음 — 드리프트 검증 생략"
fi

# 패키지에 실제로 그 내용이 들어갔는지
if artifact=$(coo_pkg_artifact); then
  dest="$COO_TEST_SANDBOX/pkg"
  coo_extract_pkg "$dest"
  staged="$(coo_upstream_root "$dest")/config/omarchy/shell.json"
  assert_file_exists "$staged" "스테이징된 shell.json"
  assert_eq "$(jq -S . "$staged")" "$(jq -S . "$SRC")" "스테이징된 파일 == 정본"
else
  echo "note: 아티팩트 없음 — 스테이징 검증 생략"
fi

exit "$ASSERT_FAILURES"
