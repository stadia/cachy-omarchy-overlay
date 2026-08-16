---
name: project-conventions
description: quarto_overlay(cachy-omarchy-overlay)의 비자명 관례와 안전 규칙. 코드·문서·커밋 작성 전, 또는 세션 시작 시 적용.
user-invocable: false
---

이 프로젝트는 CachyOS 위 Hyprland + Quickshell 오버레이(런처·커맨드 메뉴·키바인딩 뷰어)를 만드는 Bash + QML 패키지다. 관례가 코드에서 바로 보이지 않으므로 아래를 작업 전 적용한다.

## 언어 규칙
- **산출물 문서는 한국어.** `docs/*.md`, README의 본문, 핸드오프·원장.
- **코드·식별자·커밋 메시지·테스트가 검사하는 리터럴은 영어.** 플랜의 코드 블록은 그대로 전사 대상이며 `tests/installer/test_layout.sh`가 `^Commit: <40-hex>$` 등을 grep한다 — 번역하면 테스트가 어긋난다.
- 이미 커밋된 영어 docs(UPSTREAM.md, README, docs/QUATTRO_PORT_MAP.md)는 소급 번역하지 않는다("앞으로"만 적용).

## 안전 규칙 (절대)
- `~/.config/hypr/**` 직접 편집 금지. 프로젝트 소유 경로(`~/.config/cachy-omarchy-overlay/hypr/overlay.*`)와 테스트 픽스처(`tests/fixtures/hypr/`)만 쓴다. 사용자 `hyprland.lua`는 관리 블록(`coo_hypr_overlay_snippet`) 주입으로만 건드리고, 본문을 고치지 않는다.
- Lua에서 `#`는 주석이 아니라 길이 연산자 → 마커는 Lua에 `--`를 쓴다(`coo_hypr_marker_*`). 무방비 `dofile` 금지 — `pcall` 가드 필수(누락 시 사용자 설정 전체가 깨짐, SPEC §5.1 위배).
- 사용자 세션 Hyprland에 무격리 `hyprctl reload/dispatch exit` / `pkill Hyprland` 금지. 중첩 Hyprland는 `env -u HYPRLAND_INSTANCE_SIGNATURE`로 격리.
- 서브에이전트 `sudo` 금지.
- 라이브 `--force-bindings` 적용 전 사용자에게 한 줄 고지.
- `commit.gpgsign` 꺼져 있음 — 다시 켜지 말 것.

## 워크플로 (Subagent-Driven Development)
- 한 번에 한 구현 에이전트만 브랜치에서 실행.
- TDD: 실패 테스트 작성 → 실측 실패 → 구현 → 통과 → 전체 스위트 → 커밋.
- 플랜이 지정한 커밋 메시지를 그대로 쓴다.
- `SPEC.md`가 최종 권위. 플랜은 `docs/superpowers/plans/`, SDD 워크스페이스는 `.superpowers/sdd/`(git-ignored). 재개 시 `HANDOFF.md → progress.md → 플랜 → SPEC.md` 순서로 읽는다.
- 원장에서 `Task <N>: complete`인 태스크는 다시 디스패치하지 않는다.

## 테스트
- `./tests/test.sh [filter]` — 각 `tests/**/test_*.sh`를 격리된 샌드박스 HOME에서 실행. exit 0 = 전부 green.
- `tests/lib/assert.sh`: `assert_eq` / `assert_contains` / `assert_file_exists`.
- 라이브 셸 테스트는 `COO_SHELL_PATH=$PWD/shell` 필수. 기본값 `~/.local/share/cachy-omarchy-overlay/shell`은 M7 설치 전이라 없음.
- 라이브 테스트는 `coo-test`/`coo-launcher` 네임스페이스를 `hyprctl layers`로 실측 + shell.log QML 에러 grep. 불린 IPC만으로 "렌더됨"을 주장하지 말 것(M1 Task 6 교훈).

## 환경 (재측정 금지, 이미 확정)
- CachyOS, Hyprland 0.56.2(사용자 설정 = `hyprland.lua`만), Quickshell 0.3.0(`/usr/bin/qs`).
- `coo-shell.service`는 개발용으로 enabled일 수 있음. ExecStart가 레포 `bin/coo-shell-daemon`을 가리킴(M7 설치 경로 아님).

## 검증 원칙
- 증거 없이 완료 주장 금지. "should/probably" 금지.
- **문서 < 설치된 `.qmltypes`·실측.** Quickshell/Hyprland API는 버전마다 달라 문서 신뢰보다 직접 잰다.
- IPC 특이점: booting ≡ not running(exit 255, §9 — "not ready" 구분 불가); IPC 레벨 오류는 stdout + exit 0 → `bin/coo-shell`이 nonzero로 변환(§11).
- `timeout` 없는 무한 대기 금지(SPEC §19.3, bounded retry).

## 메모리
사용자 지시(계속 유효): 산출물 한국어 · Subagent-Driven 유지 · `hyprland.lua`는 사용자 직접 편집 — 변경 시 사용자 확인.