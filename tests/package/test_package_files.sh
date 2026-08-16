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

# Task 2: the staged shell.json must be OUR bar-free default, not upstream's
# full bar layout — otherwise the shell draws a bar over the user's Waybar
# and starts notifications/lock/idle services (SPEC 4.3 / 17).
if command -v jq >/dev/null; then
  staged_shell_json=$root/config/omarchy/shell.json
  assert_eq "$(jq -r '.version' "$staged_shell_json")" "1" "staged shell.json version: 1"
  for w in left center right; do
    assert_eq "$(jq -r ".bar.layout.$w | length" "$staged_shell_json")" "0" \
      "staged shell.json bar.layout.$w empty"
  done
  for p in omarchy.bar omarchy.notifications omarchy.lock omarchy.osd \
           omarchy.idle omarchy.polkit omarchy.background; do
    has=$(jq -r --arg p "$p" '.disabledPlugins | index($p) != null' "$staged_shell_json")
    assert_eq "$has" "true" "staged shell.json disables $p"
  done
  has_menu=$(jq -r '.disabledPlugins | index("omarchy.menu") != null' "$staged_shell_json")
  assert_eq "$has_menu" "false" "staged shell.json keeps omarchy.menu enabled"
else
  echo "skip: jq missing — cannot inspect staged shell.json contents"
fi

[[ $ASSERT_FAILURES -eq 0 ]]
