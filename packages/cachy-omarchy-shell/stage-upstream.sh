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
# 스피커 튜닝 템플릿. omarchy-audio-tuning on 이 $OMARCHY_PATH/default/audio 와
# default/systemd/user/omarchy-speaker-tuning.service 를 읽는다. 패키지는
# 사용자 ~/.config/pipewire 나 systemd --user 유닛을 만들지 않는다 — 헬퍼가
# 사용자가 on 을 실행할 때만 복사한다. crash-watch 등 다른 unit 은 올리지 않는다.
cp -a "$src/default/audio" "$dest/usr/share/cachy-omarchy/upstream/default/"
install -D -m644 "$src/default/systemd/user/omarchy-speaker-tuning.service" \
  "$dest/usr/share/cachy-omarchy/upstream/default/systemd/user/omarchy-speaker-tuning.service"
# 하이프랜드 토글 스니펫 (0.8.0): omarchy-hyprland-toggle 의 on() 경로가
# $OMARCHY_PATH/default/hypr/toggles/$FLAG.lua 를 사용자 hypr 설정으로 복사한다
# (bin/omarchy-hyprland-toggle:18 FLAG_SOURCE). 정적 lua 조각 3개 —
# flags.lua / single-window-aspect-ratio.lua / window-no-gaps.lua. default/hypr
# 전체가 아니라 이 디렉터리만 올린다 (나머지 hypr 설정은 CachyOS 소유).
install -d "$dest/usr/share/cachy-omarchy/upstream/default/hypr"
cp -a "$src/default/hypr/toggles" \
  "$dest/usr/share/cachy-omarchy/upstream/default/hypr/toggles"
# 바·패널 위젯이 bare name 으로 부르는 업스트림 helper 를 verbatim 으로
# 스테이징한다 (셸 래퍼가 $OMARCHY_PATH/bin 을 셸 프로세스 PATH 에 붙인다).
# 목록은 위젯 실측에서 나왔다 — M8 평가 문서 "helper 처리 방침" Tier A·B.
# 앞의 두 개는 M4 키바인딩 UI (cachy-omarchy-keybindings) 도 쓴다.
# reminder/agent-usage 묶음(Tier B)은 기능 단위로 함께 있어야 성립한다:
# omarchy-reminder 는 omarchy-notification-send 를 부르고, agents 패널은
# omarchy-agent-usage-update 가 CLI 별 수집기를 부른다. 수집기는 해당 CLI 가
# 없으면 조용히 빈다.
# omarchy-menu-keybindings 도 넣지 않는다: 데이터 수집을 CachyOS 에 맞춘
# 우리 적응 카피가 overlay/bin 에 있다. 나머지 업스트림 bin/ 은 전체 OS
# 가정이라 여전히 넣지 않는다 (docs/COMMAND_AUDIT.md).
# 테마 체인 (M9): omarchy-theme-set 의 critical path + 배경 묶음 + 메뉴 UI
# 프론트(omarchy-menu-images). yq 는 핀 커밋에서 불필요 (감사 실측).
# browser/keyboard/install/update/remove 는 제외 — M9 설계 문서 D3·Tier C.
# omarchy-toggle-enabled 는 theme-set-vscode 의 skip 토글 게이트 — 사용자
# 상태의 존재만 읽는 1행 테스트라 shim 없이 원본을 둔다 (M9 라이브 실측에서
# 누락 확인, RUNTIME_STARTUP §18.6).
# 유틸리티 플러그인 체인 (M10, 설계 문서 §3 Tier A): clipboard/emojis/OSD
# 오버레이는 이미 기본 로드되고 QML 이 $OMARCHY_PATH/bin 의 helper 를 부른다.
# clipboard-open 의 launch-browser/editor/tui/hyprland-focus-app 은 전이
# closure 다. brightness-keyboard-mute 는 이름과 달리 mic-mute LED no-op
# 가드 helper — audio-input-mute 가 무조건 부르므로 빼면 command not found 가
# 샌다 (D7). 이후 확장에서 audio-output-switch/audio-tuning 과
# brightness-display 체인, touchpad/touchscreen 가드를 verbatim 으로 올렸다.
# omarchy-hw-laptop 과 monitor-internal 체인은 CachyOS 가 toggles/hypr 를
# source 하지 않아 래퍼가 필요하므로 넣지 않는다. XF86 키는 여전히 주입하지
# 않는다 (M10 D6).
# 노출 집합 = 스테이징 집합 (SPEC §45). 이 배열이 단일 정의다 — 아래 두 루프가
# 같은 배열을 돌기 때문에 스테이징 목록과 /usr/bin 노출 목록이 갈라질 수 없다.
# tests/package/test_usr_bin_helpers.sh 가 `helpers=(` 로 이 블록을 파싱한다.
# 메뉴 style.bar + 세션 lock/logout/reboot/shutdown. factory-reset 은
# Omarchy ISO @factory 전제라 PATH 에 올리지 않는다. 전이는 메뉴 exec 가
# 극장 실패하지 않도록 기능 단위로 묶는다: omarchy-bar 는 source
# omarchy-shell-config 후 omarchy-plugin-catalog / omarchy-shell IPC 를
# 부르고, logout/reboot/shutdown 은 omarchy-osd(이미 위) +
# omarchy-hyprland-window-close-all + omarchy-state 를 부른다.
# omarchy-apply-lock 은 omarchy-system-lock 의 전제라 같이 온다. 업스트림은
# 이것을 install/config/lockscreen-pam.sh 에서 한 번 돌려
# /etc/pam.d/omarchy-lock-password 를 만드는데, 우리는 업스트림 설치
# 스크립트를 쓰지 않으므로 그 파일이 생길 자리가 없었다. 없으면 lock 플러그인
# (shell/plugins/lock/Service.qml:485 FileView)이 passwordPamConfigured=false
# 로 남고 IPC lock.lock 이 "missing-pam" 을 돌려주는데, omarchy-system-lock 은
# 그 출력을 >/dev/null 로 버려서 exit 0 으로 아무 일도 안 한다. 전이는
# omarchy-cmd-present + omarchy-shell 뿐이라 둘 다 이미 있다.
# 스탠자 자체는 우리가 복사하지 않는다 — 업스트림 소유다.
helpers=(
  omarchy-menu-select
  omarchy-cmd-present
  omarchy-audio-output-sink
  omarchy-network-status
  omarchy-network-band
  omarchy-monitor-state
  omarchy-hyprland-monitor-scaling
  omarchy-reminder
  omarchy-notification-send
  omarchy-agent-usage-update
  omarchy-agent-usage-claude
  omarchy-agent-usage-codex
  omarchy-agent-usage-fireworks
  omarchy-theme-set
  omarchy-theme-set-templates
  omarchy-theme-color
  omarchy-theme-list
  omarchy-theme-current
  omarchy-theme-osc
  omarchy-theme-colors-from-alacritty
  omarchy-hook
  omarchy-restart-terminal
  omarchy-restart-hyprctl
  omarchy-restart-btop
  omarchy-restart-opencode
  omarchy-restart-helix
  omarchy-menu-images
  omarchy-theme-switcher
  omarchy-theme-bg-set
  omarchy-theme-bg-next
  omarchy-theme-bg-current
  omarchy-theme-bg-switcher
  omarchy-theme-bg-cache
  omarchy-theme-set-foot
  omarchy-theme-set-tmux
  omarchy-theme-set-gnome
  omarchy-theme-set-pi
  omarchy-theme-set-claude
  omarchy-theme-set-vscode
  omarchy-theme-set-obsidian
  omarchy-toggle-enabled
  omarchy-menu-clipboard
  omarchy-clipboard-open
  omarchy-clipboard-paste-text
  omarchy-clipboard-paste-file
  omarchy-launch-browser
  omarchy-launch-editor
  omarchy-launch-tui
  omarchy-hyprland-focus-app
  omarchy-menu-emoji
  omarchy-menu-emoji-insert
  omarchy-osd
  omarchy-audio-output-volume
  omarchy-audio-input-mute
  omarchy-brightness-keyboard-mute
  omarchy-bar
  omarchy-shell-config
  omarchy-plugin-catalog
  omarchy-system-lock
  omarchy-apply-lock
  omarchy-system-logout
  omarchy-system-reboot
  omarchy-system-shutdown
  omarchy-hyprland-window-close-all
  omarchy-state
  omarchy-audio-output-switch
  omarchy-audio-output-set-default
  omarchy-audio-tuning
  omarchy-hw-match
  omarchy-restart-audio
  omarchy-brightness-display
  omarchy-brightness-display-ddc
  omarchy-brightness-display-apple
  omarchy-hw-display
  omarchy-hyprland-monitor-focused
  omarchy-hyprland-monitor-focused-apple
  omarchy-hw-touchpad
  omarchy-hw-touchscreen
  omarchy-toggle-touchpad
  omarchy-toggle-touchscreen
  omarchy-toggle-input-device
  # ── verbatim 확장 (0.8.0): 감사 실측이 "공식 omarchy 전체 OS 가정" 분류를
  # 뒤집은 명령들. 전부 업스트림 원본 그대로 올린다 — 래퍼/적응 카피 없음.
  # docs/COMMAND_AUDIT.md 의 감사 실측과 테스트 전수가 근거다.
  #
  # 캡처 묶음: screenshot/screenrecording/-with-webcam/qr/text 는
  # omarchy-capture-region/-webcam-list/-webcam-resize 전이 closure 다.
  # 중하드웨어 도구(gpu-screen-recorder/tesseract/zbarimg/mpv)는 optdepend —
  # 부재 시 조용히 빈 결과/exit 1, 셸을 죽이지 않는다.
  omarchy-capture-qr
  omarchy-capture-text
  omarchy-capture-screenshot
  omarchy-capture-screenrecording
  omarchy-capture-screenrecording-with-webcam
  omarchy-capture-region
  omarchy-capture-webcam-list
  omarchy-capture-webcam-resize
  # 하이프랜드 토글 묶음: window/monitor/workspace 토글 본체 + 그 전이
  # 디스패처(toggle/-toggle-enabled/-toggle-disabled/-monitor-laptop/
  # -monitor-external-active). on() 경로가 $OMARCHY_PATH/default/hypr/toggles
  # 의 정적 lua 스니펫을 복사한다 — 아래 데이터 cp 로 같이 올린다.
  omarchy-hyprland-window-gaps-toggle
  omarchy-hyprland-window-single-square-aspect-toggle
  omarchy-hyprland-workspace-layout-toggle
  omarchy-hyprland-monitor-internal
  omarchy-hyprland-monitor-internal-mirror
  omarchy-hyprland-toggle
  omarchy-hyprland-toggle-enabled
  omarchy-hyprland-toggle-disabled
  omarchy-hyprland-monitor-laptop
  omarchy-hyprland-monitor-external-active
  # 가시성/잠금화면 토글: 본체가 `omarchy-toggle <flag>-off` 디스패처를 부른다.
  # omarchy-toggle 은 ~/.local/state/omarchy/toggles/<flag> 파일을 뒤집는 순수
  # 사용자 상태 플리퍼(omarchy-toggle-enabled 와 동일 티어). crash-capture 는
  # 미출시 user unit 이 필요해 제외. nightlight/idle/notification-silencing 는
  # IPC 또는 사용자 상태 파일만 건드린다.
  omarchy-toggle-bar
  omarchy-toggle-screensaver
  omarchy-toggle
  omarchy-toggle-idle
  omarchy-toggle-nightlight
  omarchy-toggle-notification-silencing
  # 파워프로파일: powerprofilesctl + busctl(UPower). -set 이 -list 를 부른다.
  omarchy-powerprofiles-list
  omarchy-powerprofiles-set
  # 기본 앱 설정: xdg-settings/xdg-terminal-exec + 사용자 상태. omarchy-* 의존 0.
  omarchy-default-browser
  omarchy-default-editor
  omarchy-default-terminal
  # 웹앱/TUI 런치 묶음: launch-webapp 가 keystone — .desktop Exec 추출 후
  # uwsm-app --app=$url. discord-community 와 webapp-install(.desktop 가
  # launch-webapp 를 가리킴) 이 전이. webapp-remove/tui-remove 는 메뉴 선택으로
  # 삭제. tui-install/webapp-install 은 gum(이미 다른 staged helper 의 런타임
  # 불변) + curl + gtk-update-icon-cache.
  omarchy-launch-webapp
  omarchy-launch-config-editor
  omarchy-launch-discord-community
  omarchy-webapp-install
  omarchy-webapp-remove
  omarchy-tui-install
  omarchy-tui-remove
  # 하드웨어 탐지 가드: sysfs/DMI/hyprctl 만 읽는 when/checked 프로브.
  # hw-laptop 은 laptop-display/mirror 행을 드러내는데 그 action 이 위
  # monitor-internal 스크립트로 라우팅된다(스테이징됨). hw-webcam 은
  # capture-webcam-list 전이. haptic-touchpad 행은 cmd-present 가드로 opt-in.
  omarchy-hw-laptop
  omarchy-hw-webcam
  omarchy-hw-dell-xps-haptic-touchpad
  # 단독 self-contained: 표준 도구 + 이미 staged helper 만.
  omarchy-battery-low
  omarchy-menu
  omarchy-menu-timezone
  omarchy-menu-tmux-keybindings
  omarchy-dns
  omarchy-font-current
  omarchy-font-list
  omarchy-hibernation-available
  omarchy-refresh-config
  omarchy-restart-bluetooth
  omarchy-restart-wifi
  omarchy-restart-trackpad
  omarchy-update-time
  omarchy-sudo-passwordless
  # 테마 사용자 설치/갱신/삭제: git clone/pull + rm -rf ~/.config/omarchy/themes.
  # SPEC §44 Tier C "network installs" 제외에서 회수 — 스크립트는 self-contained
  # 이고 omarchy-theme-set(staged) 만 부른다. channel/pkg 인프라 미사용.
  omarchy-theme-install
  omarchy-theme-remove
  omarchy-theme-update
)

for helper in "${helpers[@]}"; do
  install -D -m755 "$src/bin/$helper" \
    "$dest/usr/share/cachy-omarchy/upstream/bin/$helper"
done

# 업스트림 프로덕션과 같은 노출 방식이다 (upstream default/bash/env-bootstrap
# 주석: 프로덕션에서는 helper 가 이미 /usr/bin/omarchy-* 로 있다). 실체는
# 옮기지 않는다 — /usr/bin 은 상대 심링크로 만든 평평한 뷰다.
install -d "$dest/usr/bin"
for helper in "${helpers[@]}"; do
  ln -sf "../share/cachy-omarchy/upstream/bin/$helper" "$dest/usr/bin/$helper"
done
# 정본 shell.json 은 overlay/defaults 에 있고 핀 커밋 업스트림 원본과 동일하다
# (M8 원칙 0: 억제는 실측 충돌이 있을 때만). 그래도 업스트림 파일을 그냥 두지
# 않고 우리 정본에서 설치한다 — 그래야 리베이스로 기본값이 조용히 바뀌면
# tests/runtime/test_shell_config.sh 의 핀 커밋 대조가 그것을 잡는다.
install -D -m644 "$defaults/shell.json" \
  "$dest/usr/share/cachy-omarchy/upstream/config/omarchy/shell.json"
install -D -m644 "$src/LICENSE" "$dest/usr/share/licenses/cachy-omarchy-shell/LICENSE"
