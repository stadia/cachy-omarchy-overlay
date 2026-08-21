#!/usr/bin/env bash
set -euo pipefail
src=${1:?overlay dir}
dest=${2:?pkgdir}

install -d "$dest/usr/bin"
for b in shell launcher keybindings bindings init doctor; do
  install -D -m755 "$src/bin/cachy-omarchy-$b" "$dest/usr/bin/cachy-omarchy-$b"
done

# 적응 카피의 실체는 통제 경로에만 둔다 — "업스트림 verbatim"(셸 패키지)과
# "우리 적응 카피"를 물리적으로 갈라두는 것이 감사 가치다. /usr/bin 은 두
# 계층의 평평한 뷰이며 상대 심링크만 놓는다 (SPEC §45).
# uwsm-app 은 여기에 없다: /usr/bin/uwsm-app 은 uwsm 패키지 소유이고,
# cachy-omarchy-shell 이 uwsm 을 depends 로 끌어온다.
install -d "$dest/usr/lib/cachy-omarchy/compat/bin"
install -d "$dest/usr/bin"
for c in omarchy-shell omarchy-update-available \
         omarchy-theme-set-browser omarchy-theme-set-keyboard \
         omarchy-menu-keybindings; do
  install -D -m755 "$src/compat/bin/$c" "$dest/usr/lib/cachy-omarchy/compat/bin/$c"
  ln -sf "../lib/cachy-omarchy/compat/bin/$c" "$dest/usr/bin/$c"
done

install -D -m644 "$src/defaults/shell.json" \
  "$dest/usr/share/cachy-omarchy/defaults/shell.json"

install -D -m644 "$src/hypr/bindings.conf" \
  "$dest/usr/share/cachy-omarchy/hypr/bindings.conf"
install -D -m644 "$src/hypr/bindings.lua" \
  "$dest/usr/share/cachy-omarchy/hypr/bindings.lua"

# uwsm 세션 환경 (SPEC §45). desktop 무관한 env.d 가 아니라 env-hyprland.d 를
# 쓴다 — Quattro 전용 변수를 sway·niri 세션까지 흘리지 않는다.
install -D -m644 "$src/uwsm/10-cachy-omarchy" \
  "$dest/usr/share/uwsm/env-hyprland.d/10-cachy-omarchy"
