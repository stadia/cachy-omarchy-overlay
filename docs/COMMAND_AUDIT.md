# 헬퍼 명령 감사

시작점: `bin/omarchy-shell`, `bin/omarchy-launch-shell`, `shell/`, `default/omarchy/omarchy-menu.jsonc`.

분류: `SAFE` | `ADAPTED` | `DISABLED`  
조치: `package` | `copy` | `wrapper` | `disable`

감사되지 않은 업스트림 `bin/` 을 `/usr/bin`에 대량 설치하지 말 것. 노출 집합은
`stage-upstream.sh` 가 스테이징하는 감사 완료 부분집합과 정확히 일치한다
(SPEC §44–45).

---

## 기동·IPC (v0.1 핵심)

| command | called from | purpose | deps | class | action |
| --- | --- | --- | --- | --- | --- |
| `omarchy-launch-shell` | 세션/유닛 | `quickshell -n -p $OMARCHY_PATH/shell` + journal + hyprctl 재시도 | quickshell, hyprctl, systemd-cat | ADAPTED | wrapper — `cachy-omarchy-shell --run`. 로직 재사용 가능, 이름/경로만 우리 것 |
| `omarchy-shell` | 핫키, 메뉴, 플러그인 | 기동하지 않음. `qs ipc` 전달 | OMARCHY_PATH, qs, timeout | ADAPTED | wrapper — `cachy-omarchy-launcher`가 `shell toggle omarchy.menu` 호출 |
| `omarchy-restart-shell` | 업데이트/디버그 | 기존 qs 인스턴스 kill 후 재기동 | quickshell kill | ADAPTED | wrapper later (`cachy-omarchy-reload`). M0에서 구현 없음 |
| `quickshell` / `qs` | 위 두 명령 | 엔진 | CachyOS 패키지 | SAFE | package (의존) |

---

## 메뉴·런처

| command | called from | purpose | class | action |
| --- | --- | --- | --- | --- |
| `uwsm-app -- gtk-launch` | `AppLibrary.qml` | 앱 실행 | SAFE | package — uwsm 패키지(`cachy-omarchy-shell` hard depends)의 실제 바이너리. compat shim 삭제됨 |
| `omarchy-remove-launcher-entry` | `AppLibrary.remove` | 숨김 항목 | OPTIONAL / ADAPTED | copy into compat if hide-from-menu를 살릴 때 |
| 메뉴 `action` 문자열 전반 | `omarchy-menu.jsonc` | 테마/락/캡처/네트워크/업데이트 등 | 혼재 | 0.8.0 감사 실측이 "전체 OS 가정" 분류를 뒤집어 캡처·토글·파워프로파일·기본앱·웹앱·DNS·폰트·재시작·테마 설치 등 self-contained 명령을 verbatim 스테이징했다(스테이징 전수·메뉴 전수 표 참조). 남은 DISABLED 는 아래 대표 목록 |

대표 `DISABLED` (전체 OS 가정 — 감사 실측 후에도 verbatim 불가):

```text
omarchy-plymouth-*
omarchy-launch-screensaver / -about / -floating-terminal-with-presentation
omarchy-reinstall-configs
omarchy-update / omarchy-update-firmware / omarchy-pkg-*
omarchy-install-* / omarchy-remove-*
omarchy-channel-* / omarchy-setup-security-* / omarchy-system-factory-reset
omarchy-branding-* / omarchy-theme-bg-install / omarchy-plymouth-*
```

`systemctl suspend|hibernate` 등 표준 명령은 SAFE. `omarchy-system-lock|logout|reboot|shutdown` 은 메뉴 세션 경로로 스테이징한다. `omarchy-system-factory-reset` 은 Omarchy ISO `@factory` 전제라 올리지 않는다. `omarchy-system-lock` 은 `omarchy-apply-lock` 없이는 아무것도 잠그지 않으므로 둘을 같이 올린다 — 업스트림은 후자를 `install/config/lockscreen-pam.sh` 로 한 번 돌리는데 우리는 업스트림 설치 스크립트를 쓰지 않아 그 자리가 비어 있었다.

---

## 키바인딩 UI

| command | called from | purpose | class | action |
| --- | --- | --- | --- | --- |
| `omarchy-menu-keybindings` | 메뉴 `learn.keybindings` | `hyprctl binds` + Lua 캐시 + 검색 메뉴 | ADAPTED | **SUPER+K / `cachy-omarchy-keybindings` 전용** wrapper — 적응 카피 + compat `omarchy-shell` + 스테이징 `omarchy-menu-select`/`omarchy-cmd-present`. 메뉴의 동명 action 은 compat shim 이 없어 여전히 실패(전수 표 참조). **M4 실측 완료**(아래). 데이터 수집만 CachyOS Hyprland 설정에 맞춘다 |
| `omarchy-menu-tmux-keybindings` | 메뉴 | Tmux 전용 | SAFE | package — 0.8.0 verbatim stage. tmux(opt) 바인딩 검색. config/tmux 폴백 미출시지만 사용자 설정 없으면 exit 1 로 degrade |
| `omarchy-menu-herdr-keybindings` | 메뉴 | Herdr 전용 | DISABLED | disable |

별도 QML 키바인드 플러그인은 없다. UI는 이 헬퍼(+ 메뉴 오버레이)다.

### M4 실측 (핀 @ f0020448, 호스트 hyprland 0.56.2-1)

호출 그래프 (핀된 스크립트 줄 단위 정독 + 호스트 실행으로 확인):

- `omarchy-menu-keybindings`
  - 동적 수집: **plain `hyprctl binds`** (`-j` 아님 — 업스트림 주석: Hyprland
    0.56.0 의 binds JSON 은 필드 정렬이 깨진다). awk 파싱.
  - Lua 캐시: `omarchy-cmd-present lua` 가드 → `lua` heredoc 이
    `~/.config/hypr/hyprland.lua` 를 가짜 `hl` 샌드박스로 `pcall(dofile)`.
    **`opts.description` 이 있는 bind 만 기록.** 조인 키 `modmask,description`.
  - `code:NNN` 해석: `xkbcli compile-keymap` (+ 하드코딩 폴백 테이블).
  - 정적 행: SHIFT ALT L/D (web app copy/download) 2개 하드코딩.
  - 캐시: `${XDG_CACHE_HOME:-~/.cache}/omarchy/keybindings-<sha256>.records`.
    dynamic 이 비면 refresh 실패 → 캐시 파일을 남기지 않는다.
  - 선택 후 dispatch: `hyprctl dispatch` (exec/sendshortcut 경로는 `jq -Rnr @json`
    으로 Lua 문자열 인용 — `lua_string()`).
  - `--print`/`-p`: 메뉴 없이 목록만 출력.
- `omarchy-menu-select` — payload 는 `perl -MJSON::PP` (2회 호출),
  `omarchy-shell shell summon omarchy.menu "$payload"`, doneFile 0.05s 폴링,
  selectionFile 출력 또는 exit 1.
- `omarchy-cmd-present` — `command -v` 루프뿐.
- **gum 미사용** — 세 스크립트에 `gum` 0 매치(grep 실측). 이 경로의 선택 UI 는
  TUI 가 아니라 메뉴 오버레이(`summon omarchy.menu` select mode)다.

호스트 실측 (CachyOS, `~/.config/hypr/hyprland.lua` 만 사용):

- 호스트 설정은 hyprland.lua 뿐. `hl.bind` 30개, **description 0개**.
- `hyprctl binds` 는 48개 bind 를 전부 `dispatcher: __lua` + 빈 description +
  숫자 arg 로 보고.
- 스크립트의 `[[ -z $description && $dispatcher == "__lua" ]] && continue` 가
  이 48개를 **전부 drop**.
- 재현: `XDG_CACHE_HOME=$(mktemp -d) PATH=<pin>/bin:$PATH omarchy-menu-keybindings --print`
  → **정적 2행만** 출력, 캐시 파일 없음, exit 0.
- 결론: 업스트림은 description 달린 Omarchy lua 설정을 가정한다 (SPEC §57).
  시각/런타임(`omarchy-menu-select` + `summon omarchy.menu`)은 유지하고
  **데이터 수집만 적응**하는 `cachy-omarchy-keybindings` 가 M4 Task 2 의 산출물.
- 보안: 적응 카피의 사용자 `hyprland.lua` 스캔은 `dofile` 하지 않는다.
  `loadfile(config, "t", env)` 제한 환경에서 `pcall(chunk)`만 실행하며, config에는
  fake `hl`, 순수 Lua 기본 기능, 읽기 전용 `string`/`table`/`math`, `os.getenv`만
  보인다. `io`/`package`/`require`/`debug`/`dofile`/`loadfile` 및 `os.execute` 등은
  config 환경에 없다. 회귀 테스트는 `os.execute("touch ...")`가 실행되지 않으며
  그 앞 bind는 계속 수집됨을 확인한다.

호스트 도구 실측: `hyprctl` `lua` `jq` `xkbcli` `perl`(JSON::PP) `awk` `sort`
`sha256sum` 모두 존재. `gum` 도 설치돼 있으나 이 경로는 부르지 않는다.

---

## 셸 인프라 (기본 활성 플러그인이 부름)

idle/lock/osd/battery가 켜져 있으면 아래가  invok된다. v0.1은 플러그인 DISABLE이 우선.
아래 `omarchy-system-lock` 행은 **idle 플러그인 정책**이다. 메뉴 `system.lock` 헬퍼는 전수 표에서 SAFE/package 다.

| command | plugin | class | action |
| --- | --- | --- | --- |
| `omarchy-launch-screensaver` | idle | DISABLED | disable plugin |
| `omarchy-system-lock` | idle | DISABLED | disable plugin |
| `omarchy-system-wake` | idle | DISABLED (idle) / **미스테이징 (lock)** | lock 플러그인의 `runWake()` 도 이름으로 부른다. 미스테이징이라 127 — 순수 기능 손실(잠금 중 화면 깨우기 없음), 위험은 없음. 후속 verbatim 후보 (RUNTIME_STARTUP §22.5) |
| `omarchy-hyprland-session-locked` | lock | **DISABLED — 공존 위험** | **의도적 미스테이징.** `strandedLockCheckProc` 가 이걸 불러 exit 0 이면 세션 잠금을 회수하려 하는데, hyprlock 이 이미 쥔 상태면 ext-session-lock 거부로 **quickshell 이 죽는다**(실측 §22.4). 헬퍼가 없으면 127 → 복구 경로가 조용히 비활성 = fail-safe. `test_staged_session_helpers.sh` 가 고정 |
| `omarchy-brightness-keyboard` | lock | 미스테이징 | lock 의 `runBlank()` 가 부른다. 127 — 키보드 백라이트 안 꺼짐. 위험 없음, 후속 verbatim 후보 |
| `omarchy-battery-low` / `omarchy-powerprofiles-set` | battery | DISABLED | disable plugin |
| `omarchy-notification-send` | 여러 패널 | SAFE | package — M8 Tier B. `omarchy-reminder` 와 `omarchy-theme-set` 이 부른다(실측). 알림 표시 자체는 셸 플러그인 정책이지 이 helper 의 스테이징 여부와 별개다 |
| `omarchy-shell osd ...` | AppLibrary 런치 OSD | OPTIONAL | osd 플러그인 정책에 따름 |
| `omarchy-osd` | osd 패널 | M10: stage | `omarchy-shell -q osd show <jq payload>` 얇은 프런트. volume/mic-mute helper 와 함께 채택. display brightness 체인은 이후 verbatim 확장에서 채택 |

### M10 스테이징 목록 (verbatim, `$OMARCHY_PATH/bin`)

`packages/cachy-omarchy-shell/stage-upstream.sh` 의 M10 슬라이스 — 회귀는
`tests/package/test_staged_plugin_helpers.sh` + `test_makepkg.sh` 가 단언한다.
전체 스테이징 집합은 아래 전수 표가 권위다.

| helper | plugin | class | note |
| --- | --- | --- | --- |
| `omarchy-menu-clipboard` | clipboard | SAFE | `shell toggle omarchy.clipboard` 얇은 프런트 |
| `omarchy-clipboard-paste-text` / `-paste-file` | clipboard | SAFE | 선택 시에만 `wl-copy`/`wtype` (D4). `wtype || true` 는 선언된 upstream 예외 (P08 범위 밖) |
| `omarchy-clipboard-open` | clipboard | SAFE | URL→launch-browser, text→launch-editor, image→`tensaku-edit`(미설치 시 명시적 127) |
| `omarchy-launch-browser` / `-editor` / `-tui` / `omarchy-hyprland-focus-app` | clipboard 전이 closure | SAFE | xdg-utils(hard depends) + uwsm-app(uwsm 패키지) 사용 |
| `omarchy-menu-emoji` / `-emoji-insert` | emojis | SAFE | 선택 시 copy+type 1회, 취소 무부작용 |
| `omarchy-osd` | osd | SAFE | 직접 IPC 프런트. shell 실패는 non-zero 전파 |
| `omarchy-audio-output-volume` / `-input-mute` | osd audio bridge | SAFE | pactl(pipewire-pulse)/wpctl(wireplumber). debounce 파일은 runtime dir |
| `omarchy-brightness-keyboard-mute` | input-mute closure | SAFE | mic-mute LED 가드. LED/brightnessctl 부재 시 no-op |
| `omarchy-audio-output-switch` / `-set-default` / `-tuning` | osd audio bridge | SAFE | 출력 순환 + 전이. tuning `on` 만 사용자 pipewire/systemd --user 템플릿을 복사한다. `restart-audio` 는 stale daemon drop-in 경로 |
| `omarchy-brightness-display*` / `omarchy-hw-display` | monitor | SAFE | 내부 `brightnessctl`(optdepend) · 외부 `ddcutil` · Apple `asdcontrol`. `omarchy-monitor-state` 가 이미 부름 |
| `omarchy-hw-touchpad` / `-touchscreen` + toggle | hardware | SAFE | 메뉴 `when` 가드 + `hyprctl eval` 즉시 토글. `hw-laptop`/모니터 체인은 0.8.0 에서 verbatim 으로 회수(아래) |

### 0.8.0 verbatim 확장 (감사 실측 회수)

`stage-upstream.sh` helpers 배열에 55개 helper 를 추가한 슬라이스. 출처는
감사 에이전트가 업스트림 `bin/` 본문을 정독해 "공식 omarchy 전체 OS 가정"
분류를 뒤집은 실측이다. 전부 업스트림 원본 그대로(verbatim) 올리며
`/usr/bin` 노출 집합은 스테이징 집합과 같다(SPEC §45). 회귀는
`tests/package/test_staged_theme_helpers.sh`·`test_staged_session_helpers.sh`·
`test_staged_audio_brightness_helpers.sh`·`test_makepkg.sh`·
`test_usr_bin_helpers.sh` 가 단언하고, 감사 일관성은
`tests/runtime/test_command_audit.sh` 가 단언한다. 전체 집합은 아래 전수 표이고,
메뉴 가시 행은 메뉴 전수 표에서 SAFE 로 재분류됐다.

| 묶음 | helper | class | note |
| --- | --- | --- | --- |
| 캡처 | `omarchy-capture-qr`/`-text`/`-screenshot`/`-screenrecording`/`-with-webcam` + `-region`/`-webcam-list`/`-webcam-resize` 전이 | SAFE | hyprpicker/slurp/grim + wl-copy. gpu-screen-recorder/tesseract/zbarimg/mpv/ffmpeg(opt) 부재 시 조용히 빈 결과·exit 1 |
| 하이프랜드 토글 | `omarchy-hyprland-window-gaps-toggle`/`-single-square-aspect-toggle`/`-workspace-layout-toggle`/`-monitor-internal`/`-internal-mirror` + `omarchy-hyprland-toggle`/`-toggle-enabled`/`-toggle-disabled`/`-monitor-laptop`/`-monitor-external-active` 전이 | SAFE | `omarchy-hyprland-toggle` 의 on() 이 `$OMARCHY_PATH/default/hypr/toggles/$FLAG.lua` 를 복사 — 같은 배치에서 `default/hypr/toggles/`(flags·window-no-gaps·single-window-aspect-ratio) 를 ship. `workspace-layout-toggle` 은 `hyprctl keyword` 폴백이라 토글 helper 미사용 |
| 가시성/잠금 토글 | `omarchy-toggle-bar`/`-screensaver` + `omarchy-toggle` 디스패처; `omarchy-toggle-idle`/`-nightlight`/`-notification-silencing` | SAFE | `omarchy-toggle` 은 `~/.local/state/omarchy/toggles/$FLAG` 파일 플립(순수 사용자 상태). `toggle-crash-capture` 는 미출시 user unit 이 필요해 제외, `toggle-hybrid-gpu` 는 `omarchy-pkg-add` cascade 로 제외 |
| 파워프로파일 | `omarchy-powerprofiles-list`/`-set` | SAFE | powerprofilesctl + busctl(UPower). `-set` 이 `-list` 전이 |
| 기본 앱 | `omarchy-default-browser`/`-editor`/`-terminal` | SAFE | xdg-settings/xdg-terminal-exec + 사용자 상태. omarchy-* 의존 0 |
| 웹앱/TUI 런치 | `omarchy-launch-webapp`(keystone)/`-config-editor`/`-discord-community` + `omarchy-webapp-install`/`-remove`/`omarchy-tui-install`/`-remove` | SAFE | `launch-webapp` 가 .desktop Exec 추출 → `uwsm-app --app=$url`. `webapp-install`·`tui-install` 이 gum(런타임 불변)+curl+gtk-update-icon-cache |
| 하드웨어 탐지 | `omarchy-hw-laptop`/`-webcam`/`-dell-xps-haptic-touchpad` | SAFE | sysfs/DMI/hyprctl 읽기 전용 when/checked 프로브. `hw-laptop` 행 action 은 monitor-internal 스크립트(스테이징됨) — cascade 정합. `hw-fingerprint`/`-hybrid-gpu` 는 action 이 미스테이지드 설치 스크립트라 제외 |
| 단독 self-contained | `omarchy-menu`/`-timezone`/`-tmux-keybindings`, `omarchy-dns`, `omarchy-font-current`/`-list`, `omarchy-hibernation-available`, `omarchy-refresh-config`, `omarchy-restart-bluetooth`/`-wifi`/`-trackpad`, `omarchy-update-time`, `omarchy-sudo-passwordless` | SAFE | 표준 도구 + 이미 staged helper 만. `sudo-passwordless` 는 self-contained 이고 패스워드리스 sudo 를 부여하는 보안 민감 토글. `hibernation-available` 은 `omarchy_resume.conf` 부재 시 exit 1 로 행 숨김(기능 caveat) |
| 테마 사용자 설치 | `omarchy-theme-install`/`-remove`/`-update` | SAFE | git clone/pull + `omarchy-theme-set`(staged). SPEC §44 Tier C "network installs" 제외에서 회수 — 스크립트는 self-contained, channel/pkg 인프라 미사용 |

정책 참고: `omarchy-pkg-present` 는 `pacman -Q` 루프 자체는 동작하지만, 가드
통과 시 미스테이지드 `omarchy-pkg-install`/`-remove` 행이 드러나 cascade 실패하는
`omarchy-hw-laptop` 반증과 동일 패턴이라 올리지 않는다(메뉴 전수 표 참조).

---

## 정책

1. 기동·IPC·앱 실행만 래퍼로 살린다.
2. 메뉴 JSONC의 Omarchy-OS 액션은 끄거나 실패해도 셸이 죽지 않게 둔다(업스트림이 이미 명령 실패를 어떻게 다루는지는 M3에서 실측).
3. `omarchy-settings`가 제공하는 `omarchy-debug*`는 패키징하지 않는다.
4. 공식 `bin/` 전체를 `/usr/bin`에 설치하지 않는다.
5. `omarchy-launch-tui`/`omarchy-default-terminal`/`omarchy-launch-floating-terminal-with-presentation`
   는 스테이징돼 배포되지만 `xdg-terminal-exec` 없이는 전부 실패한다 — 그 패키지는
   AUR 전용이라 `depends` 에 못 두고 `optdepends` 로만 선언돼 있다(v0.9 클로저 스캐너,
   fix round 1). 이 실행 환경은 실측 시점에 `xdg-terminal-exec` 미설치였고 세 헬퍼
   모두 실제로 깨져 있었다 — 스캐너가 없었으면 안 드러났을 라이브 간극.

---

## 스테이징 전수 (`$OMARCHY_PATH/bin` + `/usr/bin` 심링크)

아래 표가 **스테이징 집합의 권위**다. 출처는 `packages/cachy-omarchy-shell/stage-upstream.sh`
의 `helpers=(` 배열 하나이며, 그 배열이 스테이징과 `/usr/bin` 노출을 동시에 정의한다
(SPEC §45). 즉 이 표의 명령은 전부 사용자 PATH 에 실제로 올라간다.

바로 아래 "메뉴 노출 전수" 와는 목적이 다르다. 그쪽은 *메뉴에 보이는* 이름을 빠짐없이
분류하고(대부분 DISABLED — 바이너리를 안 올리므로 실행 시 실패한다), 이쪽은 *우리가
올린* 것을 빠짐없이 분류한다. 두 집합은 일부만 겹치며, 겹치는 행의 분류는 서로 같아야
한다. 세 조건 모두 `tests/runtime/test_command_audit.sh` 가 단언한다.

전부 업스트림 원본을 그대로(verbatim) 올리므로 분류는 `SAFE` / `package` 다 — 적응
카피(`ADAPTED` / `wrapper`)는 이 배열이 아니라 `overlay/bin` 과
`/usr/lib/cachy-omarchy/compat/bin` 에 있다.

<!-- STAGED_AUDIT_BEGIN -->
| command | class | action | 왜 올렸나 |
| --- | --- | --- | --- |
| `omarchy-agent-usage-claude` | SAFE | package | agents 패널 수집기. 해당 CLI 부재 시 조용히 빈다 |
| `omarchy-agent-usage-codex` | SAFE | package | agents 패널 수집기. 해당 CLI 부재 시 조용히 빈다 |
| `omarchy-agent-usage-fireworks` | SAFE | package | agents 패널 수집기. 해당 CLI 부재 시 조용히 빈다 |
| `omarchy-agent-usage-update` | SAFE | package | agents 패널 (M8 Tier B). CLI 별 수집기를 부른다 |
| `omarchy-apply-lock` | SAFE | package | 잠금 화면 PAM 서비스를 만든다 (`requires-sudo`). `omarchy-system-lock` 의 전제 — 없으면 lock IPC 가 `missing-pam` 으로 물러난다. `cachy-omarchy-init` 이 파일 부재 시에만 부른다 |
| `omarchy-audio-input-mute` | SAFE | package | M10 OSD audio bridge. `brightness-keyboard-mute` 를 무조건 부른다 (D7) |
| `omarchy-audio-output-set-default` | SAFE | package | audio-output-switch 전이. wpctl/pactl 로 default + 앱 스트림만 이동 |
| `omarchy-audio-output-sink` | SAFE | package | 바 audio 위젯이 bare name 으로 부름 (M8 Tier A) |
| `omarchy-audio-output-switch` | SAFE | package | 출력 순환. `audio-tuning fronted-sink` 로 튜닝 물리 싱크를 목록에서 뺀다 |
| `omarchy-audio-output-volume` | SAFE | package | M10 OSD audio bridge. pactl/wpctl. debounce 파일은 runtime dir |
| `omarchy-audio-tuning` | SAFE | package | 노트북 스피커 튜닝. `on` 만 `~/.config/pipewire` + user unit 템플릿을 복사. 데이터는 `$OMARCHY_PATH/default/audio` |
| `omarchy-bar` | SAFE | package | 메뉴 `style.bar` position/transparent. layer-shell 네임스페이스 `omarchy-bar` 와 동명·별개 |
| `omarchy-brightness-display` | SAFE | package | 포커스 모니터 밝기. 내부 backlight / DDC / Apple 로 분기. 바 `omarchy-monitor-state` 가 부름 |
| `omarchy-brightness-display-apple` | SAFE | package | brightness-display Apple 분기. `sudo asdcontrol`(부재 시 실패) |
| `omarchy-brightness-display-ddc` | SAFE | package | brightness-display 외부 모니터 분기. `ddcutil` optdepend |
| `omarchy-brightness-keyboard-mute` | SAFE | package | M10 mic-mute LED 가드. LED/brightnessctl 부재 시 no-op |
| `omarchy-capture-qr` | SAFE | package | 0.8.0 캡처. hyprpicker/slurp/grim + wl-copy. zbarimg(opt) 부재 시 빈 결과 |
| `omarchy-capture-region` | SAFE | package | 0.8.0 캡처 전이. hyprctl/jq/slurp/grim 영역 선택 |
| `omarchy-capture-screenrecording` | SAFE | package | 0.8.0 캡처. gpu-screen-recorder/mpv/ffmpeg(opt) 부재 시 조용히 빈다 |
| `omarchy-capture-screenrecording-with-webcam` | SAFE | package | 0.8.0 캡처. capture-webcam-list + capture-screenrecording 얇은 프런트 |
| `omarchy-capture-screenshot` | SAFE | package | 0.8.0 캡처. capture-region 전이. grim + wl-copy |
| `omarchy-capture-text` | SAFE | package | 0.8.0 캡처. slurp/grim + tesseract(opt) 부재 시 exit 1 |
| `omarchy-capture-webcam-list` | SAFE | package | 0.8.0 캡처 전이. v4l2-ctl(opt) 웹캠 목록 |
| `omarchy-capture-webcam-resize` | SAFE | package | 0.8.0 캡처 전이. ffmpeg/opt 웹캠 해상도 |
| `omarchy-clipboard-open` | SAFE | package | M10 clipboard. URL→browser, text→editor, image→`tensaku-edit`(부재 시 127) |
| `omarchy-clipboard-paste-file` | SAFE | package | M10 clipboard. 선택 시에만 `wl-copy`/`wtype` (D4) |
| `omarchy-clipboard-paste-text` | SAFE | package | M10 clipboard. 선택 시에만 `wl-copy`/`wtype` (D4) |
| `omarchy-cmd-present` | SAFE | package | `command -v` 루프뿐인 가드. 여러 helper 와 메뉴 `when` 이 부른다 |
| `omarchy-default-browser` | SAFE | package | 0.8.0 기본 앱. xdg-settings default-web-browser. omarchy-* 의존 0 |
| `omarchy-default-editor` | SAFE | package | 0.8.0 기본 앱. ~/.local/state/omarchy/defaults/editor 사용자 상태 |
| `omarchy-default-terminal` | SAFE | package | 0.8.0 기본 앱. xdg-terminal-exec + ~/.config/xdg-terminals.list |
| `omarchy-dns` | SAFE | package | 0.8.0. nmcli/systemctl/resolved DNS 설정. Omarchy 의존 0 |
| `omarchy-font-current` | SAFE | package | 0.8.0. fc-match 단일 호출 |
| `omarchy-font-list` | SAFE | package | 0.8.0. fc-list 단일 호출 |
| `omarchy-hibernation-available` | SAFE | package | 0.8.0. /proc/swaps + /sys 읽기 전용 프로브. omarchy_resume.conf 부재 시 exit 1 |
| `omarchy-hook` | SAFE | package | M9 theme-set post 훅 디스패처 (실측: theme-set 이 부름) |
| `omarchy-hw-dell-xps-haptic-touchpad` | SAFE | package | 0.8.0 hw 가드. omarchy-hw-match + /sys/bus/i2c. 행 action 은 cmd-present opt-in |
| `omarchy-hw-display` | SAFE | package | `/sys/class/backlight` 에서 패널 장치 이름. brightness-display 내부 경로 |
| `omarchy-hw-laptop` | SAFE | package | 0.8.0 hw 가드. /proc/acpi + DMI sysfs. laptop-display/mirror 행 action 은 monitor-internal 스크립트(스테이징됨) |
| `omarchy-hw-match` | SAFE | package | DMI product name/family 부분 일치. audio-tuning match 가 부름 |
| `omarchy-hw-touchpad` | SAFE | package | `hyprctl devices -j` + jq. 메뉴 `when` 과 toggle-input-device 가 부름 |
| `omarchy-hw-touchscreen` | SAFE | package | `hyprctl devices -j` + jq. 메뉴 `when` 과 toggle-input-device 가 부름 |
| `omarchy-hw-webcam` | SAFE | package | 0.8.0 hw 가드. capture-webcam-list 전이 1행 |
| `omarchy-hyprland-focus-app` | SAFE | package | M10 clipboard 전이 closure |
| `omarchy-hyprland-monitor-external-active` | SAFE | package | 0.8.0 하이프랜드 토글 전이. hyprctl monitors -j 외부 활성 검사 |
| `omarchy-hyprland-monitor-focused` | SAFE | package | brightness-display 가 포커스 모니터 이름을 얻을 때 부름 |
| `omarchy-hyprland-monitor-focused-apple` | SAFE | package | brightness-display Apple 분기 가드 |
| `omarchy-hyprland-monitor-internal` | SAFE | package | 0.8.0 하이프랜드 토글. 내부 모니터 on/off. hyprland-toggle + monitor-laptop/-external-active 전이 |
| `omarchy-hyprland-monitor-internal-mirror` | SAFE | package | 0.8.0 하이프랜드 토글. 내부 미러. 동일 전이 체인 |
| `omarchy-hyprland-monitor-laptop` | SAFE | package | 0.8.0 하이프랜드 토글 전이. hyprctl 로 내부 패널 이름 |
| `omarchy-hyprland-monitor-scaling` | SAFE | package | 바 monitor 위젯 (M8 Tier A) |
| `omarchy-hyprland-toggle` | SAFE | package | 0.8.0 하이프랜드 토글 디스패처. $OMARCHY_PATH/default/hypr/toggles/$FLAG.lua 복사. 순수 사용자 상태 |
| `omarchy-hyprland-toggle-disabled` | SAFE | package | 0.8.0 하이프랜드 토글 전이. 토글 플래그 부재 검사 |
| `omarchy-hyprland-toggle-enabled` | SAFE | package | 0.8.0 하이프랜드 토글 전이. 토글 플래그 존재 검사 |
| `omarchy-hyprland-window-close-all` | SAFE | package | logout/reboot/shutdown 전이 |
| `omarchy-hyprland-window-gaps-toggle` | SAFE | package | 0.8.0 하이프랜드 토글. hyprland-toggle window-no-gaps 전이. toggles/window-no-gaps.lua 데이터 |
| `omarchy-hyprland-window-single-square-aspect-toggle` | SAFE | package | 0.8.0 하이프랜드 토글. hyprland-toggle 전이 + notification. toggles/single-window-aspect-ratio.lua |
| `omarchy-hyprland-workspace-layout-toggle` | SAFE | package | 0.8.0 하이프랜드 토글. hyprctl keyword layout 폴백. 토글 helper 미사용이라 가장 깔끔 |
| `omarchy-launch-browser` | SAFE | package | M10 clipboard 전이 closure. xdg-utils + uwsm-app |
| `omarchy-launch-config-editor` | SAFE | package | 0.8.0 런처. launch-editor(staged) 3행 래퍼 |
| `omarchy-launch-discord-community` | SAFE | package | 0.8.0 런처. cmd-present discord 가드 후 launch-webapp 전이 |
| `omarchy-launch-editor` | SAFE | package | M10 clipboard 전이 closure |
| `omarchy-launch-tui` | SAFE | package | M10 clipboard 전이 closure |
| `omarchy-launch-webapp` | SAFE | package | 0.8.0 런처 keystone. .desktop Exec 추출 → uwsm-app --app=$url. omarchy-* 의존 0 |
| `omarchy-menu` | SAFE | package | 0.8.0. 순수 IPC 래퍼 — omarchy-shell shell toggle/summon/hide/call 만 호출 |
| `omarchy-menu-clipboard` | SAFE | package | M10 clipboard. `shell toggle omarchy.clipboard` 얇은 프런트 |
| `omarchy-menu-emoji` | SAFE | package | M10 emojis. 선택 시 copy+type 1회, 취소 무부작용 |
| `omarchy-menu-emoji-insert` | SAFE | package | M10 emojis closure |
| `omarchy-menu-images` | SAFE | package | M9 테마 메뉴 UI 프론트. `omarchy-shell` IPC 만 부른다 |
| `omarchy-menu-select` | SAFE | package | M4 키바인딩 UI + 메뉴 select mode. payload → `omarchy-shell shell summon omarchy.menu` |
| `omarchy-menu-timezone` | SAFE | package | 0.8.0. timedatectl list-timezones + menu-select + sudo set-timezone(대화형) |
| `omarchy-menu-tmux-keybindings` | SAFE | package | 0.8.0. tmux(opt) 바인딩 검색. config/tmux/tmux.conf 폴백 미출시지만 사용자 설정 없으면 exit 1 로 degrade |
| `omarchy-monitor-state` | SAFE | package | 바 monitor 위젯 (M8 Tier A). 첫 줄이 `omarchy-brightness-display` |
| `omarchy-network-band` | SAFE | package | 바 network 위젯 (M8 Tier A) |
| `omarchy-network-status` | SAFE | package | 바 network 위젯 (M8 Tier A). 메뉴 `when` 가드로도 쓰임 |
| `omarchy-notification-send` | SAFE | package | M8 Tier B 묶음. `omarchy-reminder` 와 `omarchy-theme-set` 이 부른다 (실측) |
| `omarchy-osd` | SAFE | package | M10 OSD. 직접 IPC 프런트, shell 실패는 non-zero 전파 |
| `omarchy-plugin-catalog` | SAFE | package | `omarchy-bar` 전이 |
| `omarchy-powerprofiles-list` | SAFE | package | 0.8.0. powerprofilesctl list 파싱 |
| `omarchy-powerprofiles-set` | SAFE | package | 0.8.0. busctl UPower OnBattery + 사용자 상태. powerprofiles-list 전이 |
| `omarchy-refresh-config` | SAFE | package | 0.8.0. $OMARCHY_PATH/config/* → ~/.config 복사 유틸. 파일 부재 시 exit 1 |
| `omarchy-reminder` | SAFE | package | M8 Tier B. user systemd timer + ${XDG_RUNTIME_DIR}/omarchy-reminders metadata 만 사용 |
| `omarchy-restart-audio` | SAFE | package | audio-tuning stale daemon drop-in 제거 경로. pipewire/wireplumber user 서비스. USB 복구는 `usbreset` 가드 |
| `omarchy-restart-bluetooth` | SAFE | package | 0.8.0. rfkill unblock/list bluetooth. Omarchy 의존 0 |
| `omarchy-restart-btop` | SAFE | package | M9 theme-set post 훅 |
| `omarchy-restart-helix` | SAFE | package | M9 theme-set post 훅 |
| `omarchy-restart-hyprctl` | SAFE | package | M9 theme-set post 훅 |
| `omarchy-restart-opencode` | SAFE | package | M9 theme-set post 훅 |
| `omarchy-restart-terminal` | SAFE | package | M9 theme-set post 훅 — 새 팔레트 반영 |
| `omarchy-restart-trackpad` | SAFE | package | 0.8.0. i2c_hid_acpi 언바인드/바인드 + modprobe. 표준 sysfs/sudo |
| `omarchy-restart-wifi` | SAFE | package | 0.8.0. rfkill unblock wifi + nmcli radio. 표준 도구 |
| `omarchy-shell-config` | SAFE | package | `omarchy-bar` 가 source 하는 설정 헬퍼 |
| `omarchy-state` | SAFE | package | reboot/shutdown 전이 |
| `omarchy-sudo-passwordless` | SAFE | package | 0.8.0. /etc/sudoers.d/99-omarchy-nopasswd-$USER 작성 + systemd-run 자동 만료. self-contained |
| `omarchy-system-lock` | SAFE | package | 메뉴 `system.lock`. `omarchy-shell lock lock`. `omarchy-apply-lock` 이 만든 PAM 서비스가 있어야 실제로 잠긴다 |
| `omarchy-system-logout` | SAFE | package | 메뉴 `system.logout`. `uwsm stop` + osd/close-all 전이 |
| `omarchy-system-reboot` | SAFE | package | 메뉴 `system.reboot`. osd/state/close-all 전이 |
| `omarchy-system-shutdown` | SAFE | package | 메뉴 `system.shutdown`. osd/state/close-all 전이 |
| `omarchy-theme-bg-cache` | SAFE | package | M9 배경 묶음 (theme-set 이 부름) |
| `omarchy-theme-bg-current` | SAFE | package | M9 배경 묶음 |
| `omarchy-theme-bg-next` | SAFE | package | M9 배경 묶음 |
| `omarchy-theme-bg-set` | SAFE | package | M9 배경 묶음 |
| `omarchy-theme-bg-switcher` | SAFE | package | M9 배경 묶음 |
| `omarchy-theme-color` | SAFE | package | M9 테마 코어 |
| `omarchy-theme-colors-from-alacritty` | SAFE | package | M9 theme-set 코어 체인 |
| `omarchy-theme-current` | SAFE | package | M9 테마 코어 |
| `omarchy-theme-install` | SAFE | package | 0.8.0. git clone + omarchy-theme-set. SPEC §44 Tier C 에서 회수 — channel/pkg 인프라 미사용 |
| `omarchy-theme-list` | SAFE | package | M9 테마 코어 |
| `omarchy-theme-osc` | SAFE | package | M9 테마 코어 |
| `omarchy-theme-remove` | SAFE | package | 0.8.0. ~/.config/omarchy/themes rm -rf + menu-select. SPEC §44 Tier C 에서 회수 |
| `omarchy-theme-set` | SAFE | package | M9 테마 코어. $OMARCHY_PATH/themes + default/themed 참조 |
| `omarchy-theme-set-claude` | SAFE | package | M9 앱별 테마 적용 |
| `omarchy-theme-set-foot` | SAFE | package | M9 앱별 테마 적용 |
| `omarchy-theme-set-gnome` | SAFE | package | M9 앱별 테마 적용 |
| `omarchy-theme-set-obsidian` | SAFE | package | M9 앱별 테마 적용 |
| `omarchy-theme-set-pi` | SAFE | package | M9 앱별 테마 적용 |
| `omarchy-theme-set-templates` | SAFE | package | M9 theme-set 코어 체인 |
| `omarchy-theme-set-tmux` | SAFE | package | M9 앱별 테마 적용 |
| `omarchy-theme-set-vscode` | SAFE | package | M9 앱별 테마 적용 |
| `omarchy-theme-switcher` | SAFE | package | M9 테마 전환 UI |
| `omarchy-theme-update` | SAFE | package | 0.8.0. 사용자 테마 git 디르 git pull. SPEC §44 Tier C 에서 회수 |
| `omarchy-toggle` | SAFE | package | 0.8.0 토글 디스패처. ~/.local/state/omarchy/toggles/$FLAG 파일 플립. toggle-enabled 과 동일 티어 |
| `omarchy-toggle-bar` | SAFE | package | 0.8.0. omarchy-toggle bar-off 전이. 바 플러그인이 플래그 읽음 |
| `omarchy-toggle-enabled` | SAFE | package | `theme-set-vscode` 의 skip 토글 게이트. 사용자 상태 존재만 읽는 1행 테스트 (RUNTIME_STARTUP §18.6) |
| `omarchy-toggle-idle` | SAFE | package | 0.8.0. ~/.local/state/omarchy/indicators/stay-awake 토글. 외부 의존 0 |
| `omarchy-toggle-input-device` | SAFE | package | touchpad/touchscreen 토글 실체. `hyprctl eval` 즉시 적용. hypr toggles lua 지속은 CachyOS 에서 best-effort |
| `omarchy-toggle-nightlight` | SAFE | package | 0.8.0. hyprsunset 온도 토글 + uwsm-app 기동 보장 + shell IPC |
| `omarchy-toggle-notification-silencing` | SAFE | package | 0.8.0. omarchy-shell notifications toggleDnd 2행 IPC |
| `omarchy-toggle-screensaver` | SAFE | package | 0.8.0. omarchy-toggle screensaver-off 전이. 잠금 플러그인이 플래그 읽음 |
| `omarchy-toggle-touchpad` | SAFE | package | `omarchy-toggle-input-device touchpad` 프런트. 메뉴 Hardware > Touchpad |
| `omarchy-toggle-touchscreen` | SAFE | package | `omarchy-toggle-input-device touchscreen` 프런트. 메뉴 Hardware > Touchscreen |
| `omarchy-tui-install` | SAFE | package | 0.8.0. ~/.local/share/applications TUI .desktop 작성. gum/curl/gtk-update-icon-cache |
| `omarchy-tui-remove` | SAFE | package | 0.8.0. xdg-terminal-exec TUI .desktop 스캔/삭제. menu-select 전이 |
| `omarchy-update-time` | SAFE | package | 0.8.0. sudo systemctl restart systemd-timesyncd |
| `omarchy-webapp-install` | SAFE | package | 0.8.0. ~/.local/share/applications webapp .desktop + 아이콘. launch-webapp 가 Exec |
| `omarchy-webapp-remove` | SAFE | package | 0.8.0. launch-webapp Exec .desktop 스캔/삭제. menu-select + update-desktop-database |
<!-- STAGED_AUDIT_END -->

---

## 메뉴 노출 전수 (M3)

출처: 핀된 `default/omarchy/omarchy-menu.jsonc` 의 `action`/`when`/`checked` 와
`shell/plugins/menu/Menu.qml` 하드코딩 `omarchy-*` (fonts/powerprofiles provider).
앱 목록(`provider: apps`)은 데스크톱 엔트리이지 `omarchy-*`가 아니다 — R06.

전수는 `\bomarchy-[a-z0-9-]+\b` 토큰 추출이라, 메뉴 action
`omarchy-bar position top` / `omarchy-bar transparent toggle` 의 첫 단어가
명령 이름으로 잡힌다. 그 행은 업스트림 바 설정 헬퍼(`bin/omarchy-bar`,
공개 경로 `omarchy bar`)의 분류다. `hyprctl layers` 의 layer-shell
네임스페이스 `omarchy-bar` 는 실행 가능한 명령이 아니며 이 표의 대상이
아니다. 가시성 토글은 `omarchy-toggle-bar` 다.

### 비활성 경로

REIMPLEMENT 아님. 업스트림 JSONC를 패치하거나 행을 지우지 않는다.

1. **바이너리 부재** — 공식 `omarchy`/`omarchy-settings` `bin/`을 `/usr/bin`에
   설치하지 않는다. 메뉴 `runAction`은 `Util.execDetached`라 없는 명령은
   실패하고 셸은 유지된다.
2. **`when`/`checked` 가드** — `omarchy-cmd-present` / `omarchy-hw-*` /
   `omarchy-pkg-present` 가 없으면 조건이 실패해 해당 행이 숨겨진다.
3. **M5** — 사용자 메뉴 오버레이 또는 `cachy-omarchy-init`가 위험 항목을
   더 숨길 수 있다. M3는 패치 수 0을 유지한다.

표준 명령(`systemctl suspend|hibernate`, `hyprpicker`, `passwd`)은 SAFE이며
`omarchy-*`가 아니라 이 표에 없다. `uwsm-app`은 uwsm 패키지 소유 실제
바이너리다(구 Task 3 WRAPPER shim 은 삭제됨).

<!-- MENU_AUDIT_BEGIN -->
| command | class | action | note |
| --- | --- | --- | --- |
| `omarchy-bar` | SAFE | package | 업스트림 `bin/omarchy-bar` (`omarchy bar`). 메뉴 `style.bar` position/transparent. 전이 `omarchy-shell-config` + `omarchy-plugin-catalog`. layer-shell 네임스페이스 `omarchy-bar` 와 동명·별개. 가시성 토글은 `omarchy-toggle-bar` |
| `omarchy-branding-about` | DISABLED | disable | 테마/plymouth/브랜딩. settings 패키지 가정 |
| `omarchy-branding-screensaver` | DISABLED | disable | 테마/plymouth/브랜딩. settings 패키지 가정 |
| `omarchy-capture-qr` | SAFE | package | 0.8.0 verbatim stage. hyprpicker/slurp/grim + zbarimg(opt) |
| `omarchy-capture-screenrecording` | SAFE | package | 0.8.0 verbatim stage. capture-region/-webcam-* 전이. gpu-screen-recorder 등 opt |
| `omarchy-capture-screenrecording-with-webcam` | SAFE | package | 0.8.0 verbatim stage. capture-webcam-list + capture-screenrecording 프런트 |
| `omarchy-capture-screenshot` | SAFE | package | 0.8.0 verbatim stage. capture-region 전이 + grim |
| `omarchy-capture-text` | SAFE | package | 0.8.0 verbatim stage. slurp/grim + tesseract(opt) 부재 시 exit 1 |
| `omarchy-channel-current` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-channel-set` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-cmd-present` | SAFE | package | `command -v` 루프뿐인 가드. M9·M10 체인과 메뉴 `when` 이 함께 쓰므로 스테이징한다 (스테이징 전수 참조) |
| `omarchy-default-agent` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-default-browser` | SAFE | package | 0.8.0 verbatim stage. xdg-settings default-web-browser |
| `omarchy-default-editor` | SAFE | package | 0.8.0 verbatim stage. ~/.local/state/omarchy/defaults/editor 사용자 상태 |
| `omarchy-default-terminal` | SAFE | package | 0.8.0 verbatim stage. xdg-terminal-exec + xdg-terminals.list |
| `omarchy-dns` | SAFE | package | 0.8.0 verbatim stage. nmcli/systemctl/resolved. Omarchy 의존 0 |
| `omarchy-drive-password` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-emacs` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-font-current` | SAFE | package | 0.8.0 verbatim stage. fc-match |
| `omarchy-font-list` | SAFE | package | 0.8.0 verbatim stage. fc-list |
| `omarchy-font-set` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-games-retro-install` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-hibernation-available` | SAFE | package | 0.8.0 verbatim stage. /proc/swaps·/sys 읽기 전용 프로브. omarchy_resume.conf 부재 시 exit 1 로 행 숨김(기능 caveat: CachyOS resume 이 다른 경로면 행이 계속 숨음) |
| `omarchy-hw-dell-xps-haptic-touchpad` | SAFE | package | 0.8.0 verbatim stage. omarchy-hw-match + /sys/bus/i2c. 행 action 은 cmd-present dell-xps-touchpad-haptics opt-in |
| `omarchy-hw-fingerprint` | DISABLED | disable | when/checked 가드. 바이너리 없으면 행이 숨겨짐 |
| `omarchy-hw-hybrid-gpu` | DISABLED | disable | when/checked 가드. 바이너리 없으면 행이 숨겨짐 |
| `omarchy-hw-laptop` | SAFE | package | 0.8.0 verbatim stage. /proc/acpi + DMI sysfs. laptop-display/mirror 행 action 은 monitor-internal 스크립트(스테이징됨) — cascade 정합 |
| `omarchy-hw-touchpad` | SAFE | package | `hyprctl devices -j` 읽기. 메뉴 Hardware > Touchpad `when` |
| `omarchy-hw-touchscreen` | SAFE | package | `hyprctl devices -j` 읽기. 메뉴 Hardware > Touchscreen `when` |
| `omarchy-hw-webcam` | SAFE | package | 0.8.0 verbatim stage. capture-webcam-list 전이. 행 action 은 capture-screenrecording-with-webcam(스테이징됨) |
| `omarchy-hyprland-monitor-internal` | SAFE | package | 0.8.0 verbatim stage. hyprland-toggle + monitor-laptop/-external-active 전이. toggles/*.lua 데이터 함께 ship |
| `omarchy-hyprland-monitor-internal-mirror` | SAFE | package | 0.8.0 verbatim stage. 동일 hyprland-toggle/monitor 전이 체인 |
| `omarchy-hyprland-window-gaps-toggle` | SAFE | package | 0.8.0 verbatim stage. hyprland-toggle window-no-gaps 전이 + toggles/window-no-gaps.lua |
| `omarchy-hyprland-window-single-square-aspect-toggle` | SAFE | package | 0.8.0 verbatim stage. hyprland-toggle 전이 + toggles/single-window-aspect-ratio.lua |
| `omarchy-hyprland-workspace-layout-toggle` | SAFE | package | 0.8.0 verbatim stage. hyprctl keyword layout 폴백. 토글 helper 미사용 |
| `omarchy-install-ai-chatgpt` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-install-and-launch` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-install-app` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-install-browser` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-install-chromium-google-account` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-install-dev-env` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-install-docker-dbs` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-install-editor-emacs` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-install-editor-helix` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-install-editor-vscode` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-install-editor-zed` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-install-font` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-install-gaming-battlenet` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-install-gaming-geforce-now` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-install-gaming-heroic` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-install-gaming-lutris` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-install-gaming-retroarch` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-install-gaming-steam` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-install-gaming-xbox-cloud` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-install-gaming-xbox-controllers` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-install-preinstalls` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-install-service-1password` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-install-service-dropbox` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-install-service-nordvpn` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-install-service-once` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-install-service-signal` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-install-service-spotify` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-install-service-tailscale` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-install-terminal` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-launch-about` | DISABLED | disable | 공식 런처/웹앱/플로팅 터미널 |
| `omarchy-launch-config-editor` | SAFE | package | 0.8.0 verbatim stage. launch-editor(staged) 3행 래퍼 |
| `omarchy-launch-discord-community` | SAFE | package | 0.8.0 verbatim stage. cmd-present discord 후 launch-webapp 전이 |
| `omarchy-launch-floating-terminal-with-presentation` | DISABLED | disable | 공식 런처/웹앱/플로팅 터미널 |
| `omarchy-launch-screensaver` | DISABLED | disable | 공식 런처/웹앱/플로팅 터미널 |
| `omarchy-launch-webapp` | SAFE | package | 0.8.0 verbatim stage. .desktop Exec 추출 → uwsm-app --app=$url. keystone |
| `omarchy-menu` | SAFE | package | 0.8.0 verbatim stage. 순수 IPC 래퍼 — omarchy-shell toggle/summon/hide/call |
| `omarchy-menu-emoji` | SAFE | package | M10: verbatim stage (`shell toggle omarchy.emojis`) + `omarchy-menu-emoji-insert` closure. wtype/wl-copy 는 hard depends |
| `omarchy-menu-herdr-keybindings` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-menu-keybindings` | ADAPTED | wrapper | M4 SUPER+K → `cachy-omarchy-keybindings`. compat 에 같은 이름의 shim 을 두지 않으므로 메뉴 행 실행은 여전히 실패(범위는 SUPER+K 만) |
| `omarchy-menu-plugin` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-menu-share` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-menu-timezone` | SAFE | package | 0.8.0 verbatim stage. timedatectl + menu-select + 대화형 sudo set-timezone |
| `omarchy-menu-tmux-keybindings` | SAFE | package | 0.8.0 verbatim stage. tmux(opt) 바인딩 검색. config/tmux 폴백 미출시지만 exit 1 로 degrade |
| `omarchy-network-status` | SAFE | package | 바 network 위젯 (M8 Tier A). 메뉴 `when` 가드로도 쓰인다 |
| `omarchy-pkg-aur-install` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-pkg-install` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-pkg-present` | DISABLED | disable | pacman -Q 루프 자체는 동작하나, 가드 통과 시 미스테이지드 omarchy-pkg-install/-remove 행이 드러나 cascade 실패 — omarchy-hw-laptop 반증과 동일 패턴이라 올리지 않는다 |
| `omarchy-pkg-remove` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-plugin-add` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-plymouth-reset` | DISABLED | disable | 테마/plymouth/브랜딩. settings 패키지 가정 |
| `omarchy-plymouth-set-by-theme` | DISABLED | disable | 테마/plymouth/브랜딩. settings 패키지 가정 |
| `omarchy-plymouth-switcher` | DISABLED | disable | 테마/plymouth/브랜딩. settings 패키지 가정 |
| `omarchy-powerprofiles-list` | SAFE | package | 0.8.0 verbatim stage. powerprofilesctl list 파싱 |
| `omarchy-powerprofiles-set` | SAFE | package | 0.8.0 verbatim stage. busctl UPower + 사용자 상태. powerprofiles-list 전이 |
| `omarchy-refresh-hyprland` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-refresh-hyprsunset` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-refresh-plymouth` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-refresh-shell` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-refresh-tmux` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-reminder` | SAFE | package | M8 부터 stage. user systemd timer + `${XDG_RUNTIME_DIR:-/tmp}/omarchy-reminders` metadata 만 사용 (M10 계약 고정) |
| `omarchy-remove-browser` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-remove-dev-env` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-remove-gaming-battlenet` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-remove-gaming-geforce-now` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-remove-gaming-heroic` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-remove-gaming-lutris` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-remove-gaming-minecraft` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-remove-gaming-retroarch` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-remove-gaming-steam` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-remove-gaming-xbox-cloud` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-remove-gaming-xbox-controllers` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-remove-preinstalls` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-remove-security-fido2` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-remove-security-fingerprint` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-remove-security-sshd` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-remove-service-dropbox` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-remove-service-tailscale` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-restart-audio` | SAFE | package | audio-tuning 전이. 메뉴 `update.hardware.audio` 는 여전히 `omarchy-launch-floating-terminal-with-presentation` 뒤에 붙어 그 런처가 없으면 행 실행은 실패 |
| `omarchy-restart-bluetooth` | SAFE | package | 0.8.0 verbatim stage. rfkill unblock/list bluetooth |
| `omarchy-restart-hyprsunset` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-restart-shell` | ADAPTED | wrapper | later `cachy-omarchy-reload`. M3 미구현 |
| `omarchy-restart-trackpad` | SAFE | package | 0.8.0 verbatim stage. i2c_hid_acpi 언바인드/바인드 + modprobe |
| `omarchy-restart-wifi` | SAFE | package | 0.8.0 verbatim stage. rfkill + nmcli radio |
| `omarchy-restart-xcompose` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-setup-direct-boot` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-setup-security-fido2` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-setup-security-fingerprint` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-setup-security-sshd` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-shell` | ADAPTED | wrapper | M2 `cachy-omarchy-shell --ipc`. 메뉴의 summon/toggle 경로 |
| `omarchy-sudo-passwordless` | SAFE | package | 0.8.0 verbatim stage. /etc/sudoers.d/99-omarchy-nopasswd-$USER + systemd-run 자동 만료. self-contained 이고 패스워드리스 sudo 를 부여하는 보안 민감 토글 |
| `omarchy-system-factory-reset` | DISABLED | disable | Omarchy ISO `@factory` 전제. CachyOS PATH 에 올리지 않음. lock/logout/reboot/shutdown 과 별개 |
| `omarchy-system-lock` | SAFE | package | 메뉴 `system.lock`. `omarchy-shell lock lock` + 이미 스테이징된 `omarchy-cmd-present` |
| `omarchy-system-logout` | SAFE | package | 메뉴 `system.logout`. 전이 `omarchy-osd` + `omarchy-hyprland-window-close-all`. `uwsm stop` |
| `omarchy-system-reboot` | SAFE | package | 메뉴 `system.reboot`. 전이 `omarchy-osd` + `omarchy-state` + `omarchy-hyprland-window-close-all` |
| `omarchy-system-shutdown` | SAFE | package | 메뉴 `system.shutdown`. 전이 `omarchy-osd` + `omarchy-state` + `omarchy-hyprland-window-close-all` |
| `omarchy-theme-bg-install` | DISABLED | disable | 테마/plymouth/브랜딩. settings 패키지 가정 |
| `omarchy-theme-bg-set` | SAFE | package | M9 배경 묶음 |
| `omarchy-theme-bg-switcher` | SAFE | package | M9 배경 묶음 |
| `omarchy-theme-install` | SAFE | package | 0.8.0 verbatim stage. git clone + omarchy-theme-set. SPEC §44 Tier C 에서 회수 — channel/pkg 미사용 |
| `omarchy-theme-remove` | SAFE | package | 0.8.0 verbatim stage. ~/.config/omarchy/themes rm + menu-select. SPEC §44 Tier C 회수 |
| `omarchy-theme-set` | SAFE | package | M9 테마 코어. `$OMARCHY_PATH/themes` + `default/themed` 참조 |
| `omarchy-theme-switcher` | SAFE | package | M9 테마 전환 UI |
| `omarchy-theme-update` | SAFE | package | 0.8.0 verbatim stage. 사용자 테마 git 디르 git pull. SPEC §44 Tier C 회수 |
| `omarchy-toggle-bar` | SAFE | package | 0.8.0 verbatim stage. omarchy-toggle bar-off 전이(디스패처 동반 스테이징). 바 플러그인이 플래그 읽음 |
| `omarchy-toggle-crash-capture` | DISABLED | disable | 바/토글. 내장 바는 M5. 플러그인 disable이 우선 |
| `omarchy-toggle-enabled` | SAFE | package | `omarchy-theme-set-vscode` 의 skip 토글 게이트 (RUNTIME_STARTUP §18.6) |
| `omarchy-toggle-hybrid-gpu` | DISABLED | disable | 바/토글. 내장 바는 M5. 플러그인 disable이 우선 |
| `omarchy-toggle-idle` | SAFE | package | 0.8.0 verbatim stage. ~/.local/state/omarchy/indicators/stay-awake 토글. 외부 의존 0 |
| `omarchy-toggle-nightlight` | SAFE | package | 0.8.0 verbatim stage. hyprsunset 온도 토글 + shell IPC |
| `omarchy-toggle-notification-silencing` | SAFE | package | 0.8.0 verbatim stage. omarchy-shell notifications toggleDnd 2행 IPC |
| `omarchy-toggle-screensaver` | SAFE | package | 0.8.0 verbatim stage. omarchy-toggle screensaver-off 전이. 잠금 플러그인이 플래그 읽음 |
| `omarchy-toggle-touchpad` | SAFE | package | 메뉴 Hardware > Touchpad. `hyprctl eval` 즉시 토글. hypr lua 지속은 CachyOS 에서 best-effort |
| `omarchy-toggle-touchscreen` | SAFE | package | 메뉴 Hardware > Touchscreen. `hyprctl eval` 즉시 토글 |
| `omarchy-transcode` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-tui-install` | SAFE | package | 0.8.0 verbatim stage. ~/.local/share/applications TUI .desktop + 아이콘 |
| `omarchy-tui-remove` | SAFE | package | 0.8.0 verbatim stage. xdg-terminal-exec TUI .desktop 스캔/삭제 |
| `omarchy-update` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-update-firmware` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-update-time` | SAFE | package | 0.8.0 verbatim stage. sudo systemctl restart systemd-timesyncd |
| `omarchy-voxtype-install` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-voxtype-remove` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-webapp-handler` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-webapp-install` | SAFE | package | 0.8.0 verbatim stage. ~/.local/share/applications webapp .desktop + 아이콘. launch-webapp 가 Exec |
| `omarchy-webapp-remove` | SAFE | package | 0.8.0 verbatim stage. launch-webapp Exec .desktop 스캔/삭제 |
| `omarchy-windows-vm` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
<!-- MENU_AUDIT_END -->
