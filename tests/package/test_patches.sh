#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/assert.sh"

readme=$REPO_ROOT/packages/cachy-omarchy-shell/PATCHES.md
assert_file_exists "$readme" "patches README"

mapfile -t patches < <(find "$REPO_ROOT/packages/cachy-omarchy-shell" -maxdepth 1 -name '*.patch' -type f -printf '%f\n' | sort)
assert_eq "${patches[*]}" \
  "0001-stop-plugin-watcher-on-shell-exit.patch 0002-cancel-polkit-flow-before-session-lock.patch 0003-adapt-menu-keybindings-to-cachy-hyprland.patch" \
  "runtime patch inventory"
# Every maintained patch must carry a documented reason and removal condition.
readme_text=$(cat "$readme")
for p in "${patches[@]}"; do
  assert_contains "$readme_text" "$p" "README documents $p"
done

# PKGBUILD 가 적용하는 패치 목록이 디렉터리와 같아야 한다. _patches 에서 0003 이
# 빠지면 다른 테스트는 모두 녹색인 채 패치 안 된 헬퍼가 배포된다.
pkgbuild=$REPO_ROOT/packages/cachy-omarchy-shell/PKGBUILD
mapfile -t listed < <(sed -n '/^_patches=(/,/^)/p' "$pkgbuild" | grep -o "[0-9][0-9][0-9][0-9]-[^']*\.patch")
assert_eq "${listed[*]}" "${patches[*]}" "PKGBUILD _patches 가 디렉터리의 패치와 같다"

[[ $ASSERT_FAILURES -eq 0 ]]
