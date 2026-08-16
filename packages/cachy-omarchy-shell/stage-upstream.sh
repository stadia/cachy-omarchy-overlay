#!/usr/bin/env bash
set -euo pipefail
src=${1:?source tree}
dest=${2:?pkgdir}

install -d "$dest/usr/share/cachy-omarchy/upstream"
cp -a "$src/shell" "$dest/usr/share/cachy-omarchy/upstream/"
install -D -m644 "$src/version" "$dest/usr/share/cachy-omarchy/upstream/version"
install -D -m644 "$src/default/omarchy/omarchy-menu.jsonc" \
  "$dest/usr/share/cachy-omarchy/upstream/default/omarchy/omarchy-menu.jsonc"
install -D -m644 "$src/config/omarchy/shell.json" \
  "$dest/usr/share/cachy-omarchy/upstream/config/omarchy/shell.json"
install -D -m644 "$src/LICENSE" "$dest/usr/share/licenses/cachy-omarchy-shell/LICENSE"
