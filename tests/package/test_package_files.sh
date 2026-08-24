#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/assert.sh"

src=${COO_OMARCHY_GIT:-$REPO_ROOT/build/omarchy}
# build-packages may leave its exact-pin checkout in makepkg's package srcdir
# rather than build/omarchy. The test always copies this source before applying
# patches, so neither source location is ever mutated.
if [[ ! -d $src && -d $REPO_ROOT/packages/cachy-omarchy-shell/src/omarchy ]]; then
  src=$REPO_ROOT/packages/cachy-omarchy-shell/src/omarchy
fi
stage=$COO_TEST_SANDBOX/pkg
script=$REPO_ROOT/packages/cachy-omarchy-shell/stage-upstream.sh

assert_file_exists "$src/shell/shell.qml" "clone has shell.qml"
assert_file_exists "$script" "stage-upstream.sh"

defaults=$REPO_ROOT/overlay/defaults
patched_src="$COO_TEST_SANDBOX/upstream"
cp -a "$src" "$patched_src"
while IFS= read -r -d '' patch; do
  git -C "$patched_src" apply "$patch"
done < <(find "$REPO_ROOT/packages/cachy-omarchy-shell/patches" -name '*.patch' -type f -print0 | sort -z)
bash "$script" "$patched_src" "$stage" "$defaults"

root=$stage/usr/share/cachy-omarchy/upstream
assert_file_exists "$root/shell/shell.qml" "P05 shell.qml packaged"
assert_file_exists "$root/shell/plugins/menu/manifest.json" "P06 omarchy.menu packaged"
assert_file_exists "$root/default/omarchy/omarchy-menu.jsonc" "menu jsonc packaged"
assert_file_exists "$root/version" "version packaged"
assert_file_exists "$root/config/omarchy/shell.json" "upstream shell.json packaged"
assert_file_exists "$stage/usr/share/licenses/cachy-omarchy-shell/LICENSE" "MIT license"

registry_qml=$(cat "$root/shell/services/PluginRegistry.qml")
assert_contains "$registry_qml" "function stopLocalPluginWatcher()" "staged watcher cleanup function"
assert_contains "$registry_qml" "localPluginWatcher.signal(15)" "staged watcher receives SIGTERM"
assert_contains "$registry_qml" "!registry.localPluginWatcherStopping" "staged watcher restart is shutdown-guarded"
polkit_qml=$(cat "$root/shell/plugins/polkit/PolkitAgent.qml")
assert_contains "$polkit_qml" "function cancelForSessionLock()" "staged polkit lock cancellation API"
lock_qml=$(cat "$root/shell/plugins/lock/Service.qml")
assert_contains "$lock_qml" "cancelPolkitForSessionLock()" "staged lock invokes polkit cancellation"

# Must not stage excluded trees. themes/ 는 M9 부터 스테이징 대상이다 —
# colors.toml 과 default/themed/*.tpl 이 같이 진화하는 한 쌍이라 셸과 같은
# 핀 커밋에서 함께 간다 (M9 설계 문서). 테마 스테이징의 정합성은
# tests/package/test_staged_themes.sh 가 단언한다.
if [[ -e $root/install || -e $root/migrations ]]; then
  printf 'FAIL: excluded upstream trees were staged\n'
  ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
else
  printf 'ok:   excluded install/migrations\n'
fi
assert_file_exists "$root/themes/tokyo-night/colors.toml" "themes staged (M9)"
assert_file_exists "$root/default/themed/shell.toml.tpl" "themed templates staged (M9)"
assert_file_exists "$root/default/audio/filter-chain-host.conf" "audio tuning host config staged"
assert_file_exists "$root/default/systemd/user/omarchy-speaker-tuning.service" \
  "speaker-tuning unit template staged"

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
