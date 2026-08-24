#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/assert.sh"

readme=$REPO_ROOT/packages/cachy-omarchy-shell/patches/README.md
assert_file_exists "$readme" "patches README"

mapfile -t patches < <(find "$REPO_ROOT/packages/cachy-omarchy-shell/patches" -name '*.patch' -type f -printf '%f\n' | sort)
assert_eq "${patches[*]}" \
  "0001-stop-plugin-watcher-on-shell-exit.patch 0002-cancel-polkit-flow-before-session-lock.patch" \
  "runtime patch inventory"
readme_text=$(cat "$readme")
assert_contains "$readme_text" "Plugin watcher cleanup" "README documents watcher patch"
assert_contains "$readme_text" "Polkit cancellation before session lock" "README documents polkit patch"
assert_contains "$readme_text" "maintained runtime patches" "README documents maintained patch contract"

[[ $ASSERT_FAILURES -eq 0 ]]
