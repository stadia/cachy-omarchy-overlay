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
# 테마 런타임 (M9): colors.toml 과 default/themed/*.tpl 은 같이 진화하는 한
# 쌍이므로 셸과 같은 핀 커밋에서 함께 스테이징한다. omarchy-theme-set 은
# $OMARCHY_PATH/themes 와 $OMARCHY_PATH/default/themed 를 참조한다.
# upstream/default/ 는 바로 위 omarchy-menu.jsonc install -D 가 만든다 —
# 이 블록은 그 뒤에 있어야 한다.
cp -a "$src/themes" "$dest/usr/share/cachy-omarchy/upstream/"
cp -a "$src/default/themed" "$dest/usr/share/cachy-omarchy/upstream/default/"
# 바·패널 위젯이 bare name 으로 부르는 업스트림 helper 를 verbatim 으로
# 스테이징한다 (셸 래퍼가 $OMARCHY_PATH/bin 을 셸 프로세스 PATH 에 붙인다).
# 목록은 위젯 실측에서 나왔다 — M8 평가 문서 "helper 처리 방침" Tier A·B.
# 앞의 두 개는 M4 키바인딩 UI (cachy-omarchy-keybindings) 도 쓴다.
# reminder/agent-usage 묶음(Tier B)은 기능 단위로 함께 있어야 성립한다:
# omarchy-reminder 는 omarchy-notification-send 를 부르고, agents 패널은
# omarchy-agent-usage-update 가 CLI 별 수집기를 부른다. 수집기는 해당 CLI 가
# 없으면 조용히 빈다.
# 밝기 체인(omarchy-brightness-display*, omarchy-hw-display)은 의존 명령이
# CachyOS 에 없어 넣지 않는다 — omarchy-monitor-state 가 가드한다.
# omarchy-menu-keybindings 도 넣지 않는다: 데이터 수집을 CachyOS 에 맞춘
# 우리 적응 카피가 overlay/bin 에 있다. 나머지 업스트림 bin/ 은 전체 OS
# 가정이라 여전히 넣지 않는다 (docs/COMMAND_AUDIT.md).
# 테마 체인 (M9): omarchy-theme-set 의 critical path + 배경 묶음 + 메뉴 UI
# 프론트(omarchy-menu-images). yq 는 핀 커밋에서 불필요 (감사 실측).
# browser/keyboard/install/update/remove 는 제외 — M9 설계 문서 D3·Tier C.
for helper in \
  omarchy-menu-select \
  omarchy-cmd-present \
  omarchy-audio-output-sink \
  omarchy-network-status \
  omarchy-network-band \
  omarchy-monitor-state \
  omarchy-hyprland-monitor-scaling \
  omarchy-reminder \
  omarchy-notification-send \
  omarchy-agent-usage-update \
  omarchy-agent-usage-claude \
  omarchy-agent-usage-codex \
  omarchy-agent-usage-fireworks \
  omarchy-theme-set \
  omarchy-theme-set-templates \
  omarchy-theme-color \
  omarchy-theme-list \
  omarchy-theme-current \
  omarchy-theme-osc \
  omarchy-theme-colors-from-alacritty \
  omarchy-hook \
  omarchy-restart-terminal \
  omarchy-restart-hyprctl \
  omarchy-restart-btop \
  omarchy-restart-opencode \
  omarchy-restart-helix \
  omarchy-menu-images \
  omarchy-theme-switcher \
  omarchy-theme-bg-set \
  omarchy-theme-bg-next \
  omarchy-theme-bg-current \
  omarchy-theme-bg-switcher \
  omarchy-theme-bg-cache ; do
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
