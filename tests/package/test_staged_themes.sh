#!/usr/bin/env bash
# themes/ 와 default/themed/ 가 같은 핀 커밋에서 함께 스테이징되는지 검증한다.
# colors.toml 과 *.tpl 은 같이 진화하는 한 쌍이다 — 한쪽만 있으면 리베이스마다
# 조용히 어긋난다 (M9 설계 문서 "왜 가져오기인가").
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

src=${COO_OMARCHY_GIT:-$REPO_ROOT/build/omarchy}
[[ -d $src/themes ]] || { echo "skip: 업스트림 클론 없음"; exit 0; }

stage=$COO_TEST_SANDBOX/pkg
bash "$REPO_ROOT/packages/cachy-omarchy-shell/stage-upstream.sh" "$src" "$stage" \
  "$REPO_ROOT/overlay/defaults"

up="$stage/usr/share/cachy-omarchy/upstream"

n_themes=$(find "$up/themes" -mindepth 1 -maxdepth 1 -type d | wc -l)
assert_eq "$n_themes" "22" "테마 22개 스테이징"
assert_file_exists "$up/themes/tokyo-night/colors.toml" "tokyo-night colors.toml"
assert_file_exists "$up/themes/tokyo-night/icons.theme" "tokyo-night icons.theme"

n_tpl=$(find "$up/default/themed" -name '*.tpl' | wc -l)
assert_eq "$n_tpl" "17" "템플릿 17개 스테이징"
assert_file_exists "$up/default/themed/shell.toml.tpl" "shell.toml.tpl (셸 팔레트)"
assert_file_exists "$up/default/themed/hyprland.lua.tpl" "hyprland.lua.tpl"

# 스테이징본 == 핀 커밋 원본 (드리프트 없음)
if [[ -d $src/.git ]]; then
  diff -r "$src/themes" "$up/themes" >/dev/null \
    && d=0 || d=1
  assert_eq "$d" "0" "themes/ 는 원본과 동일 (수정 금지, D7)"
fi

exit "$ASSERT_FAILURES"
