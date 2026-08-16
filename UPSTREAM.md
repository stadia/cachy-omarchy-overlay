# Upstream

기계 핀은 `upstream.lock`을 본다.

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
| Last tested CachyOS environment | CachyOS, kernel 7.1.8-1-cachyos, Hyprland 0.56.2, Quickshell 0.3.0. `omarchy`/`omarchy-settings` 미설치. **M2** R01·R02. **M3** R03–R06 (`omarchy.menu` 토글·Escape·더미 앱 실행). 패치 수 none. |

체크아웃 `version` 파일은 `4.0.0.alpha`다. 공식 패키지 `pkgver`와 태그 `v4.0.0`을 권위로 쓴다.

## Components packaged (M1 빌드·M2 기동 검증, 설치하지 않음)

`packages/cachy-omarchy-shell/stage-upstream.sh` 가 실제로 설치하는 것:

- `shell/` 전체 (Quickshell 셸 트리)
- `version` (핀 표시·doctor)
- `default/omarchy/omarchy-menu.jsonc` (메뉴 정의)
- `config/omarchy/shell.json` — **업스트림 것이 아니라 우리 기본값**(`overlay/defaults/shell.json`).
  업스트림 기본값은 바 레이아웃 전체 + `disabledPlugins` 없음이어서, 그대로 쓰면
  사용자 Waybar 위에 Omarchy 바가 뜬다(§4.3). `applyShellConfig()` 가 딥머지하지 않으므로
  이 파일을 우리 것으로 교체하는 것이 무패치 바 억제 수단. 단, `disabledPlugins` 는
  내장 바를 끄지 못한다 — `RUNTIME_STARTUP.md` §3 한계 참조.
- `LICENSE` (MIT)

## Components intentionally excluded

- 공식 `omarchy` / `omarchy-settings` 패키지 자체
- `install/`, `migrations/`, libalpm hooks, `/etc/skel` 마커
- Limine / Snapper / SDDM / Plymouth / `/etc/os-release` 오버라이드
- 공식 `bin/` 전체의 `/usr/bin` 설치
- 테마 워크플로, 락/OSD/바/알림의 기본 활성

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
