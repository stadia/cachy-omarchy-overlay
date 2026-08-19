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

# /usr/bin/omarchy-* 는 SPEC §45 노출 심링크다 (Task 1) — stage-upstream.sh
# 의 helpers 배열이 소유를 선언하는 것과 같은 이름 규칙이라 여기서도 허용한다.
allowed_regex='^/usr/share/(cachy-omarchy|licenses/cachy-omarchy-shell)/|^/usr/bin/omarchy-[a-z0-9-]+$'
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
# depends= 배열은 여러 줄일 수 있다 — 괄호가 닫힐 때까지 읽는다.
deps=$(sed -n '/^depends=(/,/)/p' "$pkgbuild")
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
assert_contains "$deps" "jq" "depends jq (M10 승격: clipboard/reminders/OSD)"
assert_contains "$deps" "wl-clipboard" "depends wl-clipboard (M10 clipboard watcher)"
assert_contains "$deps" "wtype" "depends wtype (M10 emoji/clipboard paste)"
assert_contains "$deps" "wireplumber" "depends wireplumber (M10 wpctl mic mute)"
assert_contains "$deps" "pipewire-pulse" "depends pipewire-pulse (M10 pactl volume)"
assert_contains "$deps" "xdg-utils" "depends xdg-utils (M10 clipboard-open launch closure)"

# M10: jq 는 hard depends 로 승격됐으므로 optdepends 에 남아 있으면 안 된다.
optdeps=$(sed -n '/^optdepends=(/,/^)/p' "$pkgbuild")
if [[ $optdeps == *"'jq:"* ]]; then
  printf 'FAIL: jq 가 optdepends 에 잔존 (M10 에서 hard depends 로 승격)\n'
  ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
fi
for bad in tensaku brightnessctl ddcutil; do
  if [[ $deps == *"$bad"* ]]; then
    printf 'FAIL: optional-only dependency %s in depends\n' "$bad"
    ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
  fi
done
assert_contains "$optdeps" "brightnessctl" "optdepends brightnessctl (internal backlight)"
assert_contains "$optdeps" "ddcutil" "optdepends ddcutil (DDC brightness)"
assert_contains "$optdeps" "lsp-plugins-lv2" "optdepends lsp-plugins-lv2 (speaker tuning limiter)"
printf 'ok:   P02-P04 unsafe deps absent (if no FAIL above)\n'

[[ $ASSERT_FAILURES -eq 0 ]]
