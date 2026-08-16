#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/assert.sh"

artifact=$(ls -1 "$REPO_ROOT"/build/cachy-omarchy-shell-4.0.0-1-any.pkg.tar.zst 2>/dev/null | head -1 || true)
assert_file_exists "${artifact:-/missing/cachy-omarchy-shell.pkg.tar.zst}" "makepkg artifact"

if [[ -n ${artifact:-} && -f $artifact ]]; then
  list=$(bsdtar -tf "$artifact")
  assert_contains "$list" "usr/share/cachy-omarchy/upstream/shell/shell.qml" "artifact has shell.qml"
  assert_contains "$list" "usr/share/cachy-omarchy/upstream/shell/plugins/menu/manifest.json" "artifact has menu plugin"
  if [[ $list == *etc/os-release* || $list == *etc/sddm* || $list == *boot/* ]]; then
    printf 'FAIL: artifact contains forbidden paths\n'
    ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
  else
    printf 'ok:   artifact has no forbidden paths\n'
  fi
fi

[[ $ASSERT_FAILURES -eq 0 ]]
