#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/assert.sh"

src=${COO_OMARCHY_GIT:-$REPO_ROOT/build/omarchy}
stage=$COO_TEST_SANDBOX/pkg
script=$REPO_ROOT/packages/cachy-omarchy-shell/stage-upstream.sh

assert_file_exists "$src/shell/shell.qml" "clone has shell.qml"
assert_file_exists "$script" "stage-upstream.sh"

bash "$script" "$src" "$stage"

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

[[ $ASSERT_FAILURES -eq 0 ]]
