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
# 바·패널 위젯이 bare name 으로 부르는 업스트림 helper 를 verbatim 으로
# 스테이징한다 (셸 래퍼가 $OMARCHY_PATH/bin 을 셸 프로세스 PATH 에 붙인다).
# 목록은 위젯 실측에서 나왔다 — M8 평가 문서 "helper 처리 방침" Tier A.
# 앞의 두 개는 M4 키바인딩 UI (cachy-omarchy-keybindings) 도 쓴다.
# 밝기 체인(omarchy-brightness-display*, omarchy-hw-display)은 의존 명령이
# CachyOS 에 없어 넣지 않는다 — omarchy-monitor-state 가 가드한다.
# omarchy-menu-keybindings 도 넣지 않는다: 데이터 수집을 CachyOS 에 맞춘
# 우리 적응 카피가 overlay/bin 에 있다. 나머지 업스트림 bin/ 은 전체 OS
# 가정이라 여전히 넣지 않는다 (docs/COMMAND_AUDIT.md).
for helper in \
  omarchy-menu-select \
  omarchy-cmd-present \
  omarchy-audio-output-sink \
  omarchy-network-status \
  omarchy-network-band \
  omarchy-monitor-state \
  omarchy-hyprland-monitor-scaling ; do
  install -D -m755 "$src/bin/$helper" \
    "$dest/usr/share/cachy-omarchy/upstream/bin/$helper"
done
# 정본 shell.json 은 overlay/defaults 에 있고 핀 커밋 업스트림 원본과 동일하다
# (M8 원칙 0: 억제는 실측 충돌이 있을 때만). 그래도 업스트림 파일을 그냥 두지
# 않고 우리 정본에서 설치한다 — 그래야 리베이스로 기본값이 조용히 바뀌면
# tests/runtime/test_shell_config.sh 의 핀 커밋 대조가 그것을 잡는다.
install -D -m644 "$defaults/shell.json" \
  "$dest/usr/share/cachy-omarchy/upstream/config/omarchy/shell.json"
install -D -m644 "$src/LICENSE" "$dest/usr/share/licenses/cachy-omarchy-shell/LICENSE"
