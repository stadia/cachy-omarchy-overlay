# Upstream

기계 핀은 `upstream.lock`을 본다. 아래 Version/Tag/Commit 표는 사람이 유지하는
스냅샷이며 `update-upstream` 뒤에는 release date·실측 환경 확인 전까지 stale일 수 있다.
자동화와 패키징의 권위는 항상 `upstream.lock`이다.

| 항목 | 값 |
| --- | --- |
| Repository | https://github.com/basecamp/omarchy.git |
| Version | 4.0.0 |
| Tag | v4.0.0 |
| Commit | `f0020448ca87329199de7cb12f2015ebc4a3e5e7` |
| Channel | stable |
| Release date | 2026-08-14 |
| Source license | MIT (Copyright David Heinemeier Hansson) |
| Packaging recipes | https://github.com/omacom-io/omarchy-pkgs (`pkgbuilds/omarchy`, `pkgbuilds/omarchy-settings`) @ `7e448b90313fea4fb78da9a78607287691d3b241` |
| Known compatibility patches | none |
| Last tested CachyOS environment | CachyOS, kernel 7.1.8-1-cachyos, Hyprland 0.56.2, Quickshell 0.3.0. `omarchy`/`omarchy-settings` 미설치. **M2** R01·R02. **M3** R03–R06 (`omarchy.menu` 토글·Escape·더미 앱 실행). **2026-08-17** 실 시스템 승인 검증: 실제 `pacman -U` 설치, `cachy-omarchy-init` 을 사용자 실제 Hyprland 설정에 실행(충돌 감지·주입 거부), 실제 rollback `4.0.0-2 → 4.0.0-1`, `devtools` chroot 에서 clean build 성공. 상세는 `docs/RUNTIME_STARTUP.md` §12. 패치 수 none. |

체크아웃 `version` 파일은 `4.0.0.alpha`다. 공식 패키지 `pkgver`와 태그 `v4.0.0`을 권위로 쓴다.

## Components packaged (M1–M5; `pacman -U` 실설치는 2026-08-17 검증됨 — `docs/RUNTIME_STARTUP.md` §12)

두 패키지로 나뉜다. `cachy-omarchy-shell` 은 핀된 업스트림 트리를, `cachy-omarchy-overlay`
는 CachyOS 통합(공개 명령·compat 적응 카피·기본값·uwsm 세션 드롭인)을 소유한다. 서로 다른 산출물이며
`cachy-omarchy-overlay` 가 `depends=('cachy-omarchy-shell' 'bash')` 로 전자에 의존한다.
실측: `tests/runtime/test_installed_tree.sh` (M5) — 두 아티팩트를 겹쳐 추출해 설치된
것처럼 동작함을 검증. `docs/RUNTIME_STARTUP.md` §9 참조.

### `cachy-omarchy-shell` (`packages/cachy-omarchy-shell/stage-upstream.sh`)

- `shell/` 전체 (Quickshell 셸 트리) → `/usr/share/cachy-omarchy/upstream/shell/`
- `themes/` + `default/themed/` (M9) — 테마 런타임. `colors.toml` 과 `*.tpl` 은
  같이 진화하는 한 쌍이라 반드시 셸과 같은 핀 커밋에서 온다.
- `bin/omarchy-theme-*` + 연쇄 helper (M9) — Tier A(코어 체인)·Tier B(post 훅)만
  스테이징. Tier C(네트워크 설치·/etc 쓰기·하드웨어 전용)는 제외하고, 그중
  `omarchy-theme-set-browser`·`-keyboard` 는 오버레이의 no-op compat shim 이
  대신 메운다(SPEC "Milestone 9 — Theme Runtime").
- 유틸리티 플러그인 helper (M10) — clipboard(`omarchy-menu-clipboard`,
  `omarchy-clipboard-{open,paste-text,paste-file}` + launch browser/editor/tui/
  focus-app 전이 closure), emojis(`omarchy-menu-emoji{,-insert}`),
  OSD(`omarchy-osd` + `omarchy-audio-output-volume`/`omarchy-audio-input-mute` +
  mic-LED 가드 `omarchy-brightness-keyboard-mute`). 이후 확장에서
  `omarchy-audio-output-switch`/`omarchy-audio-tuning`(템플릿은
  `$OMARCHY_PATH/default/audio` + speaker-tuning user unit)과 display
  brightness 체인, touchpad/touchscreen 가드를 verbatim 으로 올렸다.
  `omarchy-hw-laptop` 과 monitor-internal 체인은 래퍼가 필요해서 넣지 않는다.
  XF86 media 키는 주입하지 않는다 (SPEC "Milestone 10 — Utility Plugin
  Runtime" 과 이어지는 Helper expansion 절).
- 메뉴 `style.bar` + 세션 lock/logout/reboot/shutdown (`omarchy-bar`,
  `omarchy-system-lock`/`-logout`/`-reboot`/`-shutdown`) 과 전이
  (`omarchy-shell-config`, `omarchy-plugin-catalog`,
  `omarchy-hyprland-window-close-all`, `omarchy-state`). `omarchy-system-factory-reset`
  은 Omarchy ISO `@factory` 전제라 넣지 않는다.
- `version` (핀 표시·doctor)
- `default/omarchy/omarchy-menu.jsonc` (메뉴 정의)
- `config/omarchy/shell.json` — **업스트림 것이 아니라 우리 기본값**(`overlay/defaults/shell.json`).
  업스트림 기본값은 바 레이아웃 전체 + `disabledPlugins` 없음이어서, 그대로 쓰면
  사용자 Waybar 위에 Omarchy 바가 뜬다(§4.3). `applyShellConfig()` 가 딥머지하지 않으므로
  이 파일을 우리 것으로 교체하는 것이 무패치 바 억제 수단. 단, `disabledPlugins` 는
  내장 바를 끄지 못한다 — `RUNTIME_STARTUP.md` §3·§9.3 한계 참조.
- `LICENSE` (MIT)

### `cachy-omarchy-overlay` (`packages/cachy-omarchy-overlay/stage-overlay.sh`)

업스트림 소스가 아니라 이 레포에서 새로 작성한 CachyOS 통합 레이어. 소유 파일은
다음 범주다(정확한 목록은 `tests/package/test_overlay_files.sh` 가 단언한다):

- `usr/bin/cachy-omarchy-{shell,launcher,keybindings,bindings,init,doctor}`
  — 공개 명령 6개.
- `usr/lib/cachy-omarchy/compat/bin/{omarchy-shell,omarchy-update-available,
  omarchy-theme-set-browser,omarchy-theme-set-keyboard}` — compat 적응 카피 4개.
  실체는 이 통제 경로에만 둔다(§44).
- `usr/bin/omarchy-{shell,update-available,theme-set-browser,theme-set-keyboard}`
  — compat 실체를 가리키는 상대 심링크 4개. `/usr/bin` 은 심링크만 놓는 평평한
  뷰이다(§45 개정).
- `usr/share/uwsm/env-hyprland.d/10-cachy-omarchy` — uwsm 세션 환경 드롭인.
  그래픽 세션에 `OMARCHY_PATH=/usr/share/cachy-omarchy/upstream` 을 공급한다(§45).
- `usr/share/cachy-omarchy/defaults/shell.json` — `cachy-omarchy-init` 가 최초 실행 시
  사용자 설정으로 복사하는 정본. `cachy-omarchy-shell` 패키지의 스테이징된 기본값과
  내용이 동일하다(`test_installed_tree.sh` 가 `jq -S` 로 비교).
- `usr/share/cachy-omarchy/hypr/{bindings.conf,bindings.lua}` — `cachy-omarchy-bindings`
  가 사용자 `~/.config/cachy-omarchy/hypr/` 로 복사하는 소스.

`uwsm-app` 은 어느 쪽 패키지도 소유하지 않는다 — `/usr/bin/uwsm-app` 은
uwsm 패키지(`cachy-omarchy-shell` 의 hard depends) 소유다. M3 시절의
`overlay/compat/bin/uwsm-app` shim 은 uwsm 이 필수 의존으로 자리잡으면서 삭제됐다
— shim 이 실제 바이너리를 가리던 문제(`docs/RUNTIME_STARTUP.md` §15.2)의
구조적 해소다.

systemd 유저 유닛은 기동 전환(§"Milestone 8 — Shell Autostart", RUNTIME_STARTUP §16)
으로 제거됐다 — 더 이상 소유하지 않는다. 과거 11개 시점의 실측은
`docs/RUNTIME_STARTUP.md` §9.1 의 역사 기록이다.

`cachy-omarchy-init` 는 post-install 훅이 아니라 사용자가 직접 실행하는 유저 레벨
헬퍼다(SPEC §38) — 상세 계약은 `docs/RUNTIME_STARTUP.md` §9.2.

## Components intentionally excluded

- 공식 `omarchy` / `omarchy-settings` 패키지 자체
- `install/`, `migrations/`, libalpm hooks, `/etc/skel` 마커
- Limine / Snapper / SDDM / Plymouth / `/etc/os-release` 오버라이드
- 공식 `bin/` 전체의 `/usr/bin` 설치
- 테마 Tier C helper(`omarchy-theme-install/update/remove`, plymouth/browser/
  keyboard 훅)의 스테이징 — M9 부터 나머지 테마 워크플로는 채택했다
- XF86 media 키의 자동 주입, `omarchy-hw-laptop` 과 monitor-internal 체인
  (CachyOS 가 hypr toggles lua 를 source 하지 않아 래퍼 필요)
- `omarchy-system-factory-reset` / `-finish` (Omarchy ISO `@factory` 전제)
- 락/알림의 기본 활성 (OSD 패널은 M10 에서 채택 — direct CLI/audio helper 경로만)

## Minimum safe subset

CachyOS에서 `omarchy.menu`를 쓰려면 공식 OS가 아니라 **핀된 런타임 트리 + Quickshell + `OMARCHY_PATH` + IPC 래퍼**면 된다. 공식 `omarchy` 패키지는 그 트리에 `omarchy-settings`·부트로더·SDDM을 묶으므로 설치하지 않는다.

## Known limitations (미해결)

상세와 실측 근거는 `docs/RUNTIME_STARTUP.md` §6.

- **셸 종료 시 `inotifywait` 자식이 남는다** — Quickshell 0.3.0 의 `Io.Process` 는
  종료할 때 자식을 정리하지 않는다(실측: quickshell 은 SIGTERM 에 ~250ms 만에
  정상 종료하고, 자식은 `systemd --user` 로 재부모화된 채 계속 산다). 끄는
  프로퍼티도 없다 — 설치된 `quickshell-io.qmltypes` 의 `Process` 는 `running /
  processId / command / workingDirectory / environment / clearEnvironment /
  stdout / stderr / stdinEnabled` 뿐. 감시 디렉터리를 지워도 해소되지 않는다:
  워치가 전부 제거되면 이벤트가 영영 오지 않아 `select()` 에서 무한 대기한다
  (`/proc/<pid>/fdinfo` 에 워치 0개, `wchan: do_select`). 셸을 재시작할 때마다
  하나씩 쌓인다. 테스트 하네스 쪽은 `tests/lib/sandbox.sh` 가 샌드박스 경로로
  스코프해 회수하지만, **실세션 재시작 누수는 미해결**이다.

### 역사 기록 (해소됨 — 이 목록에 있었으나 더 이상 제한이 아니다)

> **`graphical-session.target` 비활성** (M2·M3) — `uwsm` 부재로 유닛 자동 시작 안 함
> (§17 미검증). 현재는 uwsm 이 `cachy-omarchy-shell` 의 hard depends 이고, systemd
> 유저 유닛 자체가 Hyprland autostart 기동 전환(`docs/RUNTIME_STARTUP.md` §16)으로
> 제거됐다.
>
> **바 억제 미충족 (§4.3)** — 해결이 아니라 **요구사항 폐기**다. v0.2.0(M8) 원칙 0 으로
> 내장 바를 켜서 배포하는 것이 의도된 동작이 됐다(`SPEC.md` "suppression is now the
> opt-out, not the default"). `overlay/defaults/shell.json` 은 `disabledPlugins` 없이
> 업스트림 바 레이아웃을 그대로 싣고, `cachy-omarchy-init` 는 `bar-off` 를 만들지 않으며
> 기존 토글이 있으면 note 만 찍는다(`overlay/bin/cachy-omarchy-init`,
> `tests/runtime/test_init_bar_default.sh`). 이 항목이 달고 있던 "§61 Existing Waybar
> preserved 미충족" 은 2026-08-17 실측으로 뒤집혔다 — waybar 0.15.0 실행 상태에서 바를
> 켠 셸을 띄웠고 waybar 프로세스는 그대로였다. 두 바는 겹치지 않고 쌓인다(예약 36→62px,
> `docs/RUNTIME_STARTUP.md` §17.6). `SPEC.md` §61 해당 항목은 `[x]`.
>
> **`inotify-tools` 미감사 의존** — `PKGBUILD depends` 에 추가됐다
> (`packages/cachy-omarchy-shell/PKGBUILD`). 호출부
> (`PluginRegistry.qml:638`)는 그대로이나 미설치로 인한 WARN 반복은 발생하지 않는다.
>
> **패키지 미설치 상태에서만 검증** — 2026-08-17 실 시스템 `pacman -U` 설치로 해소.
> 위 표의 "Last tested CachyOS environment" 와 `docs/RUNTIME_STARTUP.md` §12 참조.
>
> **M3 런처의 SUPER+K 미구현** — M4 에서 구현됐다. `SPEC.md` §61 "SUPER + K opens
> keybinding UI" 는 `[x]`. 함께 적혀 있던 `uwsm-app` 소유권 서술은 제한이 아니라
> 설명이고, 위 "Components packaged" 에 이미 기록돼 있다.
