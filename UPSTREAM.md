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
| Last tested CachyOS environment | CachyOS, kernel 7.1.8-1-cachyos, Hyprland 0.56.2, Quickshell 0.3.0. `omarchy`/`omarchy-settings` 미설치. |

체크아웃 `version` 파일은 `4.0.0.alpha`다. 공식 패키지 `pkgver`와 태그 `v4.0.0`을 권위로 쓴다.

## Components packaged (M1 예정, 설치하지 않음)

- `shell/` 전체
- `default/omarchy/omarchy-menu.jsonc`
- `version`
- 권장: 최소 `config/omarchy/shell.json` (`disabledPlugins`)

## Components intentionally excluded

- 공식 `omarchy` / `omarchy-settings` 패키지 자체
- `install/`, `migrations/`, libalpm hooks, `/etc/skel` 마커
- Limine / Snapper / SDDM / Plymouth / `/etc/os-release` 오버라이드
- 공식 `bin/` 전체의 `/usr/bin` 설치
- 테마 워크플로, 락/OSD/바/알림의 기본 활성

## Minimum safe subset

CachyOS에서 `omarchy.menu`를 쓰려면 공식 OS가 아니라 **핀된 런타임 트리 + Quickshell + `OMARCHY_PATH` + IPC 래퍼**면 된다. 공식 `omarchy` 패키지는 그 트리에 `omarchy-settings`·부트로더·SDDM을 묶으므로 설치하지 않는다.
