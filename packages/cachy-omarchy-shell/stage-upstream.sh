#!/usr/bin/env bash
set -euo pipefail
src=${1:?source tree}
dest=${2:?pkgdir}
defaults=${3:?defaults dir}

install -d "$dest/usr/share/cachy-omarchy/upstream"
cp -a "$src/shell" "$dest/usr/share/cachy-omarchy/upstream/"
install -D -m644 "$src/version" "$dest/usr/share/cachy-omarchy/upstream/version"
install -D -m644 "$src/default/omarchy/omarchy-menu.jsonc" \
  "$dest/usr/share/cachy-omarchy/upstream/default/omarchy/omarchy-menu.jsonc"
# 업스트림 기본값은 바 레이아웃 전체를 담고 있고 disabledPlugins 가 없다.
# shell.qml 의 applyShellConfig() 는 딥머지하지 않으므로, 이 파일을 우리 것으로
# 교체하는 것이 사용자 Waybar 위에 Omarchy 바가 뜨는 것을 막는 무패치 수단이다.
# 정본은 overlay/defaults/shell.json 이며 여기서 defaultsPath 로도 설치한다.
install -D -m644 "$defaults/shell.json" \
  "$dest/usr/share/cachy-omarchy/upstream/config/omarchy/shell.json"
install -D -m644 "$src/LICENSE" "$dest/usr/share/licenses/cachy-omarchy-shell/LICENSE"
