#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/assert.sh"

src=${COO_OMARCHY_GIT:-$REPO_ROOT/build/omarchy}
stage=$COO_TEST_SANDBOX/pkg
script=$REPO_ROOT/packages/cachy-omarchy-shell/stage-upstream.sh

assert_file_exists "$src/shell/shell.qml" "clone has shell.qml"
assert_file_exists "$script" "stage-upstream.sh"

defaults=$REPO_ROOT/overlay/defaults
bash "$script" "$src" "$stage" "$defaults"

root=$stage/usr/share/cachy-omarchy/upstream
assert_file_exists "$root/shell/shell.qml" "P05 shell.qml packaged"
assert_file_exists "$root/shell/plugins/menu/manifest.json" "P06 omarchy.menu packaged"
assert_file_exists "$root/default/omarchy/omarchy-menu.jsonc" "menu jsonc packaged"
assert_file_exists "$root/version" "version packaged"
assert_file_exists "$root/config/omarchy/shell.json" "upstream shell.json packaged"
assert_file_exists "$stage/usr/share/licenses/cachy-omarchy-shell/LICENSE" "MIT license"

# Must not stage excluded trees
if [[ -e $root/install || -e $root/migrations || -e $root/themes ]]; then
  printf 'FAIL: excluded upstream trees were staged\n'
  ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
else
  printf 'ok:   excluded install/migrations/themes\n'
fi

id=$(grep -E '"id"' "$root/shell/plugins/menu/manifest.json" | head -1)
assert_contains "$id" "omarchy.menu" "menu plugin id"

# 스테이징된 shell.json 은 업스트림 기본값 그대로여야 한다 — 억제 계층 1
# (빈 bar.layout + disabledPlugins) 은 M8 원칙 0 에 따라 제거됐다. 내용 자체의
# 드리프트는 tests/runtime/test_shell_config.sh 가 핀 커밋과 대조해서 잡는다.
if command -v jq >/dev/null; then
  staged_shell_json=$root/config/omarchy/shell.json
  assert_eq "$(jq -r '.version' "$staged_shell_json")" "1" "staged shell.json version: 1"
  total=$(jq -r '[.bar.layout.left, .bar.layout.center, .bar.layout.right]
                 | map(length) | add' "$staged_shell_json")
  assert_eq "$total" "14" "staged shell.json ships the upstream 14-widget layout"
  assert_eq "$(jq -r 'has("disabledPlugins")' "$staged_shell_json")" "false" \
    "staged shell.json disables no plugins"
  assert_eq "$(jq -r '.bar.layout.left[0].id' "$staged_shell_json")" "omarchy.menu" \
    "staged shell.json keeps omarchy.menu enabled"
else
  echo "skip: jq missing — cannot inspect staged shell.json contents"
fi

[[ $ASSERT_FAILURES -eq 0 ]]
