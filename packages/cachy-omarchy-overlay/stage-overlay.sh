#!/usr/bin/env bash
set -euo pipefail
src=${1:?overlay dir}
dest=${2:?pkgdir}

install -d "$dest/usr/bin"
for b in shell launcher keybindings bindings init doctor; do
  install -D -m755 "$src/bin/cachy-omarchy-$b" "$dest/usr/bin/cachy-omarchy-$b"
done

# compat shim 은 통제된 경로에만 둔다. /usr/bin 에 두면 사용자의 일반 PATH 를
# 오염시키고 SPEC 44 를 위반한다. 셸 프로세스만 이 디렉터리를 PATH 에 붙인다.
install -d "$dest/usr/lib/cachy-omarchy/compat/bin"
for c in omarchy-shell uwsm-app; do
  install -D -m755 "$src/compat/bin/$c" "$dest/usr/lib/cachy-omarchy/compat/bin/$c"
done

install -D -m644 "$src/systemd/cachy-omarchy-shell.service" \
  "$dest/usr/lib/systemd/user/cachy-omarchy-shell.service"

install -D -m644 "$src/defaults/shell.json" \
  "$dest/usr/share/cachy-omarchy/defaults/shell.json"

install -D -m644 "$src/hypr/bindings.conf" \
  "$dest/usr/share/cachy-omarchy/hypr/bindings.conf"
install -D -m644 "$src/hypr/bindings.lua" \
  "$dest/usr/share/cachy-omarchy/hypr/bindings.lua"
