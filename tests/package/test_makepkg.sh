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
fi
if [[ -f $overlay_artifact ]]; then
  list=$(bsdtar -tf "$overlay_artifact")
  assert_contains "$list" "usr/bin/cachy-omarchy-init" "overlay artifact has init"
  assert_contains "$list" "usr/lib/systemd/user/cachy-omarchy-shell.service" "overlay artifact has user unit"
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
