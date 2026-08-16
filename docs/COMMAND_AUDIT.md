# 헬퍼 명령 감사

시작점: `bin/omarchy-shell`, `bin/omarchy-launch-shell`, `shell/`, `default/omarchy/omarchy-menu.jsonc`.

분류: `SAFE` | `ADAPTED` | `DISABLED`  
조치: `package` | `copy` | `wrapper` | `disable`

전역 `/usr/bin`에 가짜 `omarchy-*`를 대량 설치하지 말 것. 필요 시 `PATH=/usr/lib/cachy-omarchy/compat/bin:...` (SPEC §44–45).

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
| `uwsm-app -- gtk-launch` | `AppLibrary.qml` | 앱 실행 | ADAPTED | wrapper — uwsm 없으면 `gtk-launch` |
| `omarchy-remove-launcher-entry` | `AppLibrary.remove` | 숨김 항목 | OPTIONAL / ADAPTED | copy into compat if hide-from-menu를 살릴 때 |
| 메뉴 `action` 문자열 전반 | `omarchy-menu.jsonc` | 테마/락/캡처/네트워크/업데이트 등 | 대부분 DISABLED | disable — 항목은 JSONC에 남아도 실행 시 실패. v0.1은 앱 목록 + 안전 항목만 남기거나 `when`으로 숨김 |

대표 `DISABLED` (전체 OS 가정):

```text
omarchy-theme-set / omarchy-theme-switcher
omarchy-plymouth-*
omarchy-system-lock / omarchy-launch-screensaver
omarchy-refresh-config / omarchy-reinstall-configs
omarchy-update* / omarchy-pkg-*
omarchy-launch-about (브랜딩/os-release)
```

`systemctl suspend|hibernate` 등 표준 명령은 SAFE. `omarchy-system-logout|reboot|shutdown`은 감사 후 ADAPTED 또는 disable.

---

## 키바인딩 UI

| command | called from | purpose | class | action |
| --- | --- | --- | --- | --- |
| `omarchy-menu-keybindings` | 메뉴 `learn.keybindings` | `hyprctl binds` + Lua 캐시 + 검색 메뉴 | ADAPTED | copy+adapt — SUPER+K가 이 명령을 부르게. **M4 실측 완료**(아래). 데이터 수집만 CachyOS Hyprland 설정에 맞춘다 |
| `omarchy-menu-tmux-keybindings` | 메뉴 | Tmux 전용 | DISABLED | disable |
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
  - 선택 후 dispatch: `hyprctl dispatch` (exec 경로는 `jq -Rnr @json` 으로 Lua
    문자열 인용 — `lua_string()`).
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

호스트 도구 실측: `hyprctl` `lua` `jq` `xkbcli` `perl`(JSON::PP) `awk` `sort`
`sha256sum` 모두 존재. `gum` 도 설치돼 있으나 이 경로는 부르지 않는다.

---

## 셸 인프라 (기본 활성 플러그인이 부름)

idle/lock/osd/battery가 켜져 있으면 아래가  invok된다. v0.1은 플러그인 DISABLE이 우선.

| command | plugin | class | action |
| --- | --- | --- | --- |
| `omarchy-launch-screensaver` | idle | DISABLED | disable plugin |
| `omarchy-system-lock` | idle | DISABLED | disable plugin |
| `omarchy-system-wake` | idle | DISABLED | disable plugin |
| `omarchy-battery-low` / `omarchy-powerprofiles-set` | battery | DISABLED | disable plugin |
| `omarchy-notification-send` | 여러 패널 | DISABLED until notifications ENABLE | disable |
| `omarchy-shell osd ...` | AppLibrary 런치 OSD | OPTIONAL | osd 플러그인 정책에 따름 |

---

## 정책

1. 기동·IPC·앱 실행만 래퍼로 살린다.
2. 메뉴 JSONC의 Omarchy-OS 액션은 끄거나 실패해도 셸이 죽지 않게 둔다(업스트림이 이미 명령 실패를 어떻게 다루는지는 M3에서 실측).
3. `omarchy-settings`가 제공하는 `omarchy-debug*`는 패키징하지 않는다.
4. 공식 `bin/` 전체를 `/usr/bin`에 설치하지 않는다.

---

## 메뉴 노출 전수 (M3)

출처: 핀된 `default/omarchy/omarchy-menu.jsonc` 의 `action`/`when`/`checked` 와
`shell/plugins/menu/Menu.qml` 하드코딩 `omarchy-*` (fonts/powerprofiles provider).
앱 목록(`provider: apps`)은 데스크톱 엔트리이지 `omarchy-*`가 아니다 — R06.

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
`omarchy-*`가 아니라 이 표에 없다. `uwsm-app`은 Task 3 WRAPPER.

<!-- MENU_AUDIT_BEGIN -->
| command | class | action | note |
| --- | --- | --- | --- |
| `omarchy-bar` | DISABLED | disable | 바/토글. 내장 바는 M5. 플러그인 disable이 우선 |
| `omarchy-branding-about` | DISABLED | disable | 테마/plymouth/브랜딩. settings 패키지 가정 |
| `omarchy-branding-screensaver` | DISABLED | disable | 테마/plymouth/브랜딩. settings 패키지 가정 |
| `omarchy-capture-qr` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-capture-screenrecording` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-capture-screenrecording-with-webcam` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-capture-screenshot` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-capture-text` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-channel-current` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-channel-set` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-cmd-present` | DISABLED | disable | when/checked 가드. 바이너리 없으면 행이 숨겨짐 |
| `omarchy-default-agent` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-default-browser` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-default-editor` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-default-terminal` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-dns` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-drive-password` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-emacs` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-font-current` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-font-list` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-font-set` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-games-retro-install` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-hibernation-available` | DISABLED | disable | when/checked 가드. 바이너리 없으면 행이 숨겨짐 |
| `omarchy-hw-dell-xps-haptic-touchpad` | DISABLED | disable | when/checked 가드. 바이너리 없으면 행이 숨겨짐 |
| `omarchy-hw-fingerprint` | DISABLED | disable | when/checked 가드. 바이너리 없으면 행이 숨겨짐 |
| `omarchy-hw-hybrid-gpu` | DISABLED | disable | when/checked 가드. 바이너리 없으면 행이 숨겨짐 |
| `omarchy-hw-laptop` | DISABLED | disable | when/checked 가드. 바이너리 없으면 행이 숨겨짐 |
| `omarchy-hw-touchpad` | DISABLED | disable | when/checked 가드. 바이너리 없으면 행이 숨겨짐 |
| `omarchy-hw-touchscreen` | DISABLED | disable | when/checked 가드. 바이너리 없으면 행이 숨겨짐 |
| `omarchy-hw-webcam` | DISABLED | disable | when/checked 가드. 바이너리 없으면 행이 숨겨짐 |
| `omarchy-hyprland-monitor-internal` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-hyprland-monitor-internal-mirror` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-hyprland-window-gaps-toggle` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-hyprland-window-single-square-aspect-toggle` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-hyprland-workspace-layout-toggle` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
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
| `omarchy-launch-config-editor` | DISABLED | disable | 공식 런처/웹앱/플로팅 터미널 |
| `omarchy-launch-discord-community` | DISABLED | disable | 공식 런처/웹앱/플로팅 터미널 |
| `omarchy-launch-floating-terminal-with-presentation` | DISABLED | disable | 공식 런처/웹앱/플로팅 터미널 |
| `omarchy-launch-screensaver` | DISABLED | disable | 공식 런처/웹앱/플로팅 터미널 |
| `omarchy-launch-webapp` | DISABLED | disable | 공식 런처/웹앱/플로팅 터미널 |
| `omarchy-menu` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-menu-emoji` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-menu-herdr-keybindings` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-menu-keybindings` | ADAPTED | wrapper | M4 SUPER+K. 지금은 바이너리 부재로 행 실행 실패 |
| `omarchy-menu-plugin` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-menu-share` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-menu-timezone` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-menu-tmux-keybindings` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-network-status` | DISABLED | disable | when/checked 가드. 바이너리 없으면 행이 숨겨짐 |
| `omarchy-pkg-aur-install` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-pkg-install` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-pkg-present` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-pkg-remove` | DISABLED | disable | 패키지/설치 경로. 공식 omarchy 가정 |
| `omarchy-plugin-add` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-plymouth-reset` | DISABLED | disable | 테마/plymouth/브랜딩. settings 패키지 가정 |
| `omarchy-plymouth-set-by-theme` | DISABLED | disable | 테마/plymouth/브랜딩. settings 패키지 가정 |
| `omarchy-plymouth-switcher` | DISABLED | disable | 테마/plymouth/브랜딩. settings 패키지 가정 |
| `omarchy-powerprofiles-list` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-powerprofiles-set` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-refresh-hyprland` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-refresh-hyprsunset` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-refresh-plymouth` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-refresh-shell` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-refresh-tmux` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-reminder` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
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
| `omarchy-restart-audio` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-restart-bluetooth` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-restart-hyprsunset` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-restart-shell` | ADAPTED | wrapper | later `cachy-omarchy-reload`. M3 미구현 |
| `omarchy-restart-trackpad` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-restart-wifi` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-restart-xcompose` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-setup-direct-boot` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-setup-security-fido2` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-setup-security-fingerprint` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-setup-security-sshd` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-shell` | ADAPTED | wrapper | M2 `cachy-omarchy-shell --ipc`. 메뉴의 summon/toggle 경로 |
| `omarchy-sudo-passwordless` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-system-factory-reset` | DISABLED | disable | 세션/전원/팩토리리셋. 전체 OS 헬퍼 |
| `omarchy-system-lock` | DISABLED | disable | 세션/전원/팩토리리셋. 전체 OS 헬퍼 |
| `omarchy-system-logout` | DISABLED | disable | 세션/전원/팩토리리셋. 전체 OS 헬퍼 |
| `omarchy-system-reboot` | DISABLED | disable | 세션/전원/팩토리리셋. 전체 OS 헬퍼 |
| `omarchy-system-shutdown` | DISABLED | disable | 세션/전원/팩토리리셋. 전체 OS 헬퍼 |
| `omarchy-theme-bg-install` | DISABLED | disable | 테마/plymouth/브랜딩. settings 패키지 가정 |
| `omarchy-theme-bg-set` | DISABLED | disable | 테마/plymouth/브랜딩. settings 패키지 가정 |
| `omarchy-theme-bg-switcher` | DISABLED | disable | 테마/plymouth/브랜딩. settings 패키지 가정 |
| `omarchy-theme-install` | DISABLED | disable | 테마/plymouth/브랜딩. settings 패키지 가정 |
| `omarchy-theme-remove` | DISABLED | disable | 테마/plymouth/브랜딩. settings 패키지 가정 |
| `omarchy-theme-set` | DISABLED | disable | 테마/plymouth/브랜딩. settings 패키지 가정 |
| `omarchy-theme-switcher` | DISABLED | disable | 테마/plymouth/브랜딩. settings 패키지 가정 |
| `omarchy-theme-update` | DISABLED | disable | 테마/plymouth/브랜딩. settings 패키지 가정 |
| `omarchy-toggle-bar` | DISABLED | disable | 바/토글. 내장 바는 M5. 플러그인 disable이 우선 |
| `omarchy-toggle-crash-capture` | DISABLED | disable | 바/토글. 내장 바는 M5. 플러그인 disable이 우선 |
| `omarchy-toggle-enabled` | DISABLED | disable | when/checked 가드. 바이너리 없으면 행이 숨겨짐 |
| `omarchy-toggle-hybrid-gpu` | DISABLED | disable | 바/토글. 내장 바는 M5. 플러그인 disable이 우선 |
| `omarchy-toggle-idle` | DISABLED | disable | 바/토글. 내장 바는 M5. 플러그인 disable이 우선 |
| `omarchy-toggle-nightlight` | DISABLED | disable | 바/토글. 내장 바는 M5. 플러그인 disable이 우선 |
| `omarchy-toggle-notification-silencing` | DISABLED | disable | 바/토글. 내장 바는 M5. 플러그인 disable이 우선 |
| `omarchy-toggle-screensaver` | DISABLED | disable | 바/토글. 내장 바는 M5. 플러그인 disable이 우선 |
| `omarchy-toggle-touchpad` | DISABLED | disable | 바/토글. 내장 바는 M5. 플러그인 disable이 우선 |
| `omarchy-toggle-touchscreen` | DISABLED | disable | 바/토글. 내장 바는 M5. 플러그인 disable이 우선 |
| `omarchy-transcode` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-tui-install` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-tui-remove` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-update` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-update-firmware` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-update-time` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-voxtype-install` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-voxtype-remove` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-webapp-handler` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-webapp-install` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-webapp-remove` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
| `omarchy-windows-vm` | DISABLED | disable | 공식 omarchy 전체 OS 가정. 바이너리 미설치 |
<!-- MENU_AUDIT_END -->
