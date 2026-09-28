#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/assert.sh"

readme=$REPO_ROOT/packages/cachy-omarchy-shell/patches/README.md
assert_file_exists "$readme" "patches README"

mapfile -t patches < <(find "$REPO_ROOT/packages/cachy-omarchy-shell/patches" -name '*.patch' -type f -printf '%f\n' | sort)
assert_eq "${patches[*]}" \
  "0001-stop-plugin-watcher-on-shell-exit.patch 0002-cancel-polkit-flow-before-session-lock.patch" \
  "runtime patch inventory"
# Every maintained patch must carry a documented reason and removal condition.
readme_text=$(cat "$readme")
for p in "${patches[@]}"; do
  assert_contains "$readme_text" "$p" "README documents $p"
done

[[ $ASSERT_FAILURES -eq 0 ]]
