#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/assert.sh"

lock=$REPO_ROOT/upstream.lock
# shellcheck disable=SC1090
source "$lock"
shell_pkg=$REPO_ROOT/packages/cachy-omarchy-shell/PKGBUILD
overlay_pkg=$REPO_ROOT/packages/cachy-omarchy-overlay/PKGBUILD
field() { grep -m1 -E "^$2=" "$1" | cut -d= -f2- | tr -d "'\""; }
shell_rel=$(field "$shell_pkg" pkgrel)
overlay_ver=$(field "$overlay_pkg" pkgver)
overlay_rel=$(field "$overlay_pkg" pkgrel)
shell_artifact="$REPO_ROOT/build/cachy-omarchy-shell-${OMARCHY_VERSION}-${shell_rel}-any.pkg.tar.zst"
overlay_artifact="$REPO_ROOT/build/cachy-omarchy-overlay-${overlay_ver}-${overlay_rel}-any.pkg.tar.zst"

assert_file_exists "$shell_artifact" "shell makepkg artifact"
assert_file_exists "$overlay_artifact" "overlay makepkg artifact"

if [[ -f $shell_artifact ]]; then
  list=$(bsdtar -tf "$shell_artifact")
  assert_contains "$list" "usr/share/cachy-omarchy/upstream/shell/shell.qml" "shell artifact has shell.qml"
  assert_contains "$list" "usr/share/cachy-omarchy/upstream/shell/plugins/menu/manifest.json" "shell artifact has menu plugin"
  # M10: 스테이징 스크립트 단언만으로는 부족하다 — 실제 아티팩트에도 들어갔는지 단언한다.
  for h in omarchy-menu-clipboard omarchy-clipboard-open omarchy-clipboard-paste-text \
           omarchy-clipboard-paste-file omarchy-launch-browser omarchy-launch-editor \
           omarchy-launch-tui omarchy-hyprland-focus-app omarchy-menu-emoji \
           omarchy-menu-emoji-insert omarchy-osd omarchy-audio-output-volume \
           omarchy-audio-input-mute omarchy-brightness-keyboard-mute \
           omarchy-bar omarchy-shell-config omarchy-plugin-catalog \
           omarchy-system-lock omarchy-apply-lock omarchy-system-logout omarchy-system-reboot \
           omarchy-system-shutdown omarchy-hyprland-window-close-all omarchy-state \
           omarchy-audio-output-switch omarchy-audio-output-set-default \
           omarchy-audio-tuning omarchy-hw-match omarchy-restart-audio \
           omarchy-brightness-display omarchy-brightness-display-ddc \
           omarchy-brightness-display-apple omarchy-hw-display \
           omarchy-hyprland-monitor-focused omarchy-hyprland-monitor-focused-apple \
           omarchy-hw-touchpad omarchy-hw-touchscreen omarchy-toggle-touchpad \
           omarchy-toggle-touchscreen omarchy-toggle-input-device \
           omarchy-theme-install omarchy-theme-update omarchy-theme-remove \
           omarchy-toggle-bar omarchy-hw-laptop omarchy-hyprland-monitor-internal \
           omarchy-hyprland-toggle omarchy-capture-screenshot omarchy-capture-region \
           omarchy-powerprofiles-set omarchy-launch-webapp omarchy-sudo-passwordless \
           omarchy-menu omarchy-dns; do
    assert_contains "$list" "usr/share/cachy-omarchy/upstream/bin/$h" "shell artifact has helper: $h"
  done
  assert_contains "$list" "usr/share/cachy-omarchy/upstream/default/audio/filter-chain-host.conf" \
    "shell artifact has audio tuning host config"
  assert_contains "$list" "usr/share/cachy-omarchy/upstream/default/systemd/user/omarchy-speaker-tuning.service" \
    "shell artifact has speaker-tuning unit template"
  for f in flags.lua single-window-aspect-ratio.lua window-no-gaps.lua; do
    assert_contains "$list" "usr/share/cachy-omarchy/upstream/default/hypr/toggles/$f" \
      "shell artifact has toggle snippet: $f"
  done
  for h in omarchy-system-factory-reset omarchy-system-factory-reset-finish; do
    if [[ $list == *"upstream/bin/$h"* ]]; then
      printf 'FAIL: excluded helper leaked into artifact: %s\n' "$h"
      ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
    fi
  done
  if [[ $list == *"omarchy-crash-watch.service"* ]]; then
    printf 'FAIL: excluded user unit leaked into artifact: omarchy-crash-watch.service\n'
    ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
  fi
  printf 'ok:   excluded helpers/units absent from artifact (if no FAIL above)\n'
fi
if [[ -f $overlay_artifact ]]; then
  list=$(bsdtar -tf "$overlay_artifact")
  assert_contains "$list" "usr/bin/cachy-omarchy-init" "overlay artifact has init"
  assert_contains "$list" "usr/share/cachy-omarchy/hypr/bindings.lua" "overlay artifact has autostart bindings"
fi

for artifact in "$shell_artifact" "$overlay_artifact"; do
  [[ -f $artifact ]] || continue
  list=$(bsdtar -tf "$artifact")
  if [[ $list == *etc/os-release* || $list == *etc/sddm* || $list == *boot/* || $list == *efi/* ]]; then
    printf 'FAIL: artifact contains forbidden paths: %s\n' "$artifact"
    ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
  else
    printf 'ok:   artifact has no forbidden paths: %s\n' "${artifact##*/}"
  fi
done

[[ $ASSERT_FAILURES -eq 0 ]]
