#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/assert.sh"

src=${COO_OMARCHY_GIT:-$REPO_ROOT/build/omarchy}
stage=$COO_TEST_SANDBOX/pkg
bash "$REPO_ROOT/packages/cachy-omarchy-shell/stage-upstream.sh" "$src" "$stage" \
  "$REPO_ROOT/overlay/defaults"

mapfile -t files < <(find "$stage" -type f -o -type l | sed "s|^$stage||" | sort)

forbidden_regex='^/(etc|boot|efi)(/|$)'
for f in "${files[@]}"; do
  if [[ $f =~ $forbidden_regex ]]; then
    printf 'FAIL: P01 forbidden path %s\n' "$f"
    ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
  fi
done
if [[ $ASSERT_FAILURES -eq 0 ]]; then
  printf 'ok:   P01 no /etc /boot /efi paths\n'
fi

allowed_regex='^/usr/share/(cachy-omarchy|licenses/cachy-omarchy-shell)/'
for f in "${files[@]}"; do
  if [[ ! $f =~ $allowed_regex ]]; then
    printf 'FAIL: P10 unowned path %s\n' "$f"
    ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
  fi
done
if [[ $ASSERT_FAILURES -eq 0 ]]; then
  printf 'ok:   P10 all files under owned prefixes\n'
fi

pkgbuild=$REPO_ROOT/packages/cachy-omarchy-shell/PKGBUILD
deps=$(grep -E '^depends=' "$pkgbuild")
for bad in omarchy-settings limine snapper sddm plymouth omarchy-keyring perl; do
  if [[ $deps == *"$bad"* ]]; then
    printf 'FAIL: forbidden dependency %s in %s\n' "$bad" "$deps"
    ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
  fi
done
assert_contains "$deps" "quickshell" "depends quickshell"
assert_contains "$deps" "hyprland" "depends hyprland"
assert_contains "$deps" "inotify-tools" "depends inotify-tools (§28 실측)"
assert_contains "$deps" "libvips" "depends libvips (menu-images 썸네일, M9)"
assert_contains "$deps" "procps-ng" "depends procps-ng (pgrep/pkill, M9)"
assert_contains "$deps" "psmisc" "depends psmisc (killall, M9)"
printf 'ok:   P02-P04 unsafe deps absent (if no FAIL above)\n'

[[ $ASSERT_FAILURES -eq 0 ]]
