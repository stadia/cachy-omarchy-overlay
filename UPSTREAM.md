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
는 CachyOS 통합(공개 명령·compat shim·유저 유닛·기본값)을 소유한다. 서로 다른 산출물이며
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
  mic-LED 가드 `omarchy-brightness-keyboard-mute`). `omarchy-audio-output-switch`/
  `omarchy-audio-tuning`(pipewire·wireplumber 사용자 설정/서비스 정책)과 display
  brightness 체인은 Tier C — 넣지 않는다 (SPEC "Milestone 10 — Utility Plugin
  Runtime", 설계 문서 §3).
- `version` (핀 표시·doctor)
- `default/omarchy/omarchy-menu.jsonc` (메뉴 정의)
- `config/omarchy/shell.json` — **업스트림 것이 아니라 우리 기본값**(`overlay/defaults/shell.json`).
  업스트림 기본값은 바 레이아웃 전체 + `disabledPlugins` 없음이어서, 그대로 쓰면
  사용자 Waybar 위에 Omarchy 바가 뜬다(§4.3). `applyShellConfig()` 가 딥머지하지 않으므로
  이 파일을 우리 것으로 교체하는 것이 무패치 바 억제 수단. 단, `disabledPlugins` 는
  내장 바를 끄지 못한다 — `RUNTIME_STARTUP.md` §3·§9.3 한계 참조.
- `LICENSE` (MIT)

### `cachy-omarchy-overlay` (`packages/cachy-omarchy-overlay/stage-overlay.sh`)

업스트림 소스가 아니라 이 레포에서 새로 작성한 CachyOS 통합 레이어. 실측 소유 경로
11개(`docs/RUNTIME_STARTUP.md` §9.1)는 다음 다섯 범주다:

- `usr/bin/cachy-omarchy-{shell,launcher,keybindings,bindings,init}` — 공개 명령 5개.
- `usr/lib/cachy-omarchy/compat/bin/{omarchy-shell,uwsm-app}` — compat shim. `/usr/bin`
  에는 절대 설치하지 않는다(§44).
- `usr/lib/systemd/user/cachy-omarchy-shell.service` — 유저 유닛. system 유닛은 소유하지
  않는다.
- `usr/share/cachy-omarchy/defaults/shell.json` — `cachy-omarchy-init` 가 최초 실행 시
  사용자 설정으로 복사하는 정본. `cachy-omarchy-shell` 패키지의 스테이징된 기본값과
  내용이 동일하다(`test_installed_tree.sh` 가 `jq -S` 로 비교).
- `usr/share/cachy-omarchy/hypr/{bindings.conf,bindings.lua}` — `cachy-omarchy-bindings`
  가 사용자 `~/.config/cachy-omarchy/hypr/` 로 복사하는 소스.

`cachy-omarchy-init` 는 post-install 훅이 아니라 사용자가 직접 실행하는 유저 레벨
헬퍼다(SPEC §38) — 상세 계약은 `docs/RUNTIME_STARTUP.md` §9.2.

## Components intentionally excluded

- 공식 `omarchy` / `omarchy-settings` 패키지 자체
- `install/`, `migrations/`, libalpm hooks, `/etc/skel` 마커
- Limine / Snapper / SDDM / Plymouth / `/etc/os-release` 오버라이드
- 공식 `bin/` 전체의 `/usr/bin` 설치
- 테마 Tier C helper(`omarchy-theme-install/update/remove`, plymouth/browser/
  keyboard 훅)의 스테이징 — M9 부터 나머지 테마 워크플로는 채택했다
- M10 Tier C helper(`omarchy-audio-output-switch`, `omarchy-audio-tuning`,
  `omarchy-brightness-display*`, `omarchy-hw-display`, power/system helper)의
  스테이징과 XF86 media 키의 자동 주입
- 락/알림의 기본 활성 (OSD 패널은 M10 에서 채택 — direct CLI/audio helper 경로만)

## Minimum safe subset

CachyOS에서 `omarchy.menu`를 쓰려면 공식 OS가 아니라 **핀된 런타임 트리 + Quickshell + `OMARCHY_PATH` + IPC 래퍼**면 된다. 공식 `omarchy` 패키지는 그 트리에 `omarchy-settings`·부트로더·SDDM을 묶으므로 설치하지 않는다.

## Known limitations (M2·M3, 미해결)

상세와 실측 근거는 `docs/RUNTIME_STARTUP.md` §6.

- **바 억제 미충족 (§4.3)** — `disabledPlugins` 로 내장 바를 못 끈다. 패키징 기본값만
  쓰면 사용자 Waybar 위에 `omarchy-bar` 가 뜸. M5 `cachy-omarchy-init` 가 `bar-off`
  토글을 사용자 상태로 생성하거나 패치 필요. §61 "Existing Waybar preserved" 미충족.
- **`inotify-tools` 미감사 의존** — `PluginRegistry.qml:638` 이 `inotifywait` 호출.
  미설치 시 1초마다 WARN 반복. `PKGBUILD depends` 누락(§28).
- **`graphical-session.target` 비활성** — `uwsm` 부재로 유닛 자동 시작 안 함(§17 미검증).
- **패키지 미설치 상태에서만 검증** — 실설치 경로(`/usr/share/cachy-omarchy/upstream`)는 M5.
- **M3 런처** — 원본 `omarchy.menu` IPC. `uwsm-app` WRAPPER 있음. SUPER+K 는 M4.
