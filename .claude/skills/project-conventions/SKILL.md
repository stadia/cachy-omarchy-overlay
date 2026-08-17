---
name: project-conventions
description: quarto_overlay(cachy-omarchy-overlay)의 비자명 관례와 안전 규칙. 코드·문서·커밋 작성 전, 또는 세션 시작 시 적용.
user-invocable: false
---

이 프로젝트는 CachyOS 위 Hyprland + Quickshell 오버레이(런처·커맨드 메뉴·키바인딩 뷰어)를 만드는 Bash + QML 패키지다. 관례가 코드에서 바로 보이지 않으므로 아래를 작업 전 적용한다.

## 안전 규칙 (절대) — 다른 무엇보다 먼저 읽는다
- `~/.config/hypr/**` 직접 편집 금지(어떤 수단으로도 — `cp`/`>`/`sed -i` 포함). 프로젝트가 소유하는 것은
  `~/.config/cachy-omarchy/hypr/bindings.{conf,lua}` 뿐이고, 사용자의 실제 `hyprland.lua`/`hyprland.conf`는
  `overlay/bin/cachy-omarchy-bindings`가 주입하는 관리 source 블록(`>>> cachy-omarchy >>>` ... `<<< cachy-omarchy <<<`)
  으로만 건드리며 본문은 절대 고치지 않는다. 테스트에서는 `tests/fixtures/` 또는 샌드박스 HOME만 쓴다.
- `bindings.conf`/`bindings.lua`는 SPEC §6.6 상 "사용자 라이브 설정"이다 — 이미 존재하면 기본적으로
  덮어쓰지 않는다. `--force`를 명시적으로 줄 때만 정본(`/usr/share/cachy-omarchy/hypr/`)으로 새로고침한다.
- Lua에서 `#`는 주석이 아니라 길이 연산자 → 마커는 Lua에 `--`를 쓴다. 무방비 `dofile` 금지 — `pcall` 가드
  필수(누락 시 사용자 설정 전체가 깨짐, SPEC §5.1 위배).
- 사용자 세션 Hyprland에 무격리 `hyprctl reload/dispatch/keyword` 나 `pkill`/`killall` 금지. 중첩
  Hyprland는 `env -u HYPRLAND_INSTANCE_SIGNATURE`로 격리.
- `~/.config/cachy-omarchy/`, `~/.local/state/omarchy/`를 실제 HOME에 만들지 않는다 — `cachy-omarchy-init`/
  `cachy-omarchy-bindings`를 실행/테스트할 때는 항상 `COO_CONFIG_DIR`/`COO_STATE_DIR`/`COO_HYPR_DIR`를
  임시 디렉터리로 돌린다.
- 서브에이전트 `sudo` 금지. `pacman -U`/`makepkg -i` 도 금지 — 읽기 전용 `systemctl --user`만.
- 라이브 바인딩(`--force`)을 실제 세션에 적용하기 전 사용자에게 한 줄 고지.
- `commit.gpgsign` 꺼져 있음 — 다시 켜지 말 것.

## 현재 아키텍처 (경로/명령)
- 공개 명령 5개, 모두 `overlay/bin/`에 있고 설치되면 `/usr/bin/`으로 간다:
  `cachy-omarchy-shell`, `cachy-omarchy-launcher`, `cachy-omarchy-keybindings`,
  `cachy-omarchy-bindings`, `cachy-omarchy-init`.
- 사용자 라이브 설정: `~/.config/cachy-omarchy/`(hypr/bindings.{conf,lua}). `shell.json` 은
  셸이 읽지 않는 dead file 이므로 init 가 만들지 않는다.
- 패키지 정본/기본값: `/usr/share/cachy-omarchy/`(defaults/shell.json, hypr/bindings.{conf,lua}).
- compat shim: `/usr/lib/cachy-omarchy/compat/bin/`(예: `omarchy-shell`, `uwsm-app`) — `/usr/bin`으로
  새면 안 되고, 이는 `tests/runtime/test_installed_tree.sh`가 양방향으로 검사한다.
- systemd 유저 유닛: `cachy-omarchy-shell.service`(`overlay/systemd/`에 정본).
- 두 패키지 산출물: `cachy-omarchy-shell-*.pkg.tar.zst`, `cachy-omarchy-overlay-*.pkg.tar.zst`
  (`build/`). `lib/runtime.sh`의 `coo_extract_pkg`/`coo_extract_overlay`가 이 아티팩트를 임시
  디렉터리에 추출해 "설치된 것처럼" 배치하는 헬퍼다 — 어느 쪽도 `sudo`/`pacman -U`를 쓰지 않는다.
  `coo_extract_overlay`는 dest를 먼저 `rm -rf`로 비우므로, 슬래시 없는 값이나
  `$COO_TEST_SANDBOX` 자체를 넘기면 거부하도록 가드돼 있다 — 그 가드를 우회하지 않는다.

## 언어 규칙
- **산출물 문서는 한국어.** `docs/*.md`, 핸드오프·원장.
- **README 는 예외 — 영어가 정본이다** (2026-08-18, 저장소 public 전환 후 결정).
  `README.md` = 영어, `README.ko-KR.md` = 한국어이며 둘은 서로 링크한다.
  **둘 중 하나를 고치면 반드시 나머지도 같이 고친다** — 내용이 갈라지면 안 된다.
  README.md 를 한국어로 되돌리지 말 것.
- **코드·식별자·커밋 메시지·테스트가 검사하는 리터럴은 영어.** 테스트가 특정 영어 문자열을
  `grep`/`assert_contains`로 검사하는 경우가 흔하다 — 그런 리터럴을 번역하면 테스트가 어긋난다.
- 이미 커밋된 영어 docs(UPSTREAM.md, docs/QUATTRO_PORT_MAP.md)는 소급 번역하지 않는다("앞으로"만 적용).

## 워크플로 (Subagent-Driven Development)
- 한 번에 한 구현 에이전트만 브랜치에서 실행.
- TDD: 실패 테스트 작성 → 실측 실패 → 구현 → 통과 → 전체 스위트 → 커밋.
- 플랜이 지정한 커밋 메시지를 그대로 쓴다.
- `SPEC.md`가 최종 권위. 플랜은 `docs/superpowers/plans/`, SDD 워크스페이스는 `.superpowers/sdd/`(git-ignored). 재개 시 `HANDOFF.md → progress.md → 플랜 → SPEC.md` 순서로 읽는다.
- 원장에서 `Task <N>: complete`인 태스크는 다시 디스패치하지 않는다.

## 테스트
- `./tests/test.sh [filter]` — `tests/**/test_*.sh` 각각을 격리된 샌드박스 HOME(`COO_TEST_SANDBOX`,
  `mktemp -d`)에서 실행한다. exit 0 = 전부 green. 실제 HOME은 손대지 않는다.
- `tests/lib/assert.sh`: `assert_eq` / `assert_contains` / `assert_file_exists` / `assert_exit`.
- 라이브 셸/키 주입 테스트(`test_shell_smoke.sh`, `test_app_launch.sh`, `test_launcher_toggle.sh`,
  `test_keybindings_toggle.sh`)는 빌드된 `build/*.pkg.tar.zst`가 있어야 뜬다(없으면 skip-as-PASS —
  M6까지는 의도된 동작, `docs/RUNTIME_STARTUP.md`에 문서화됨). `COO_RUN_LIVE=1`을 줘야 실제 키
  주입까지 실행한다.
- 라이브 테스트는 `hyprctl layers`로 우리 표면을 실측 + shell.log QML 에러 grep. 불린 IPC만으로
  "렌더됨"을 주장하지 말 것(M1 Task 6 교훈).
- **패키징에 닿는 변경(`overlay/**`, `packages/**/stage-*.sh`, `overlay/defaults/**`) 뒤에는
  `./tests/test.sh` 전에 반드시 `bin/build-packages`를 먼저 돌린다.** 스테이징 단언은 아티팩트가
  없으면 `note: 아티팩트 없음 — 스테이징 검증 생략`만 찍고 **통과한다.** 실패 모드가 "빨개짐"이
  아니라 "틀린 것을 통과시킴"이라 눈치채기 어렵다 — 그 note가 보이면 그 실행은 완전한 green이
  아니다. `build/`는 릴리스마다 아티팩트를 누적하므로, 거기서 아티팩트를 고르는 코드는 mtime
  최신을 쓰거나 모호성을 명시적으로 거부해야 한다(M8에서 `test_update_pipeline`이 낡은 패키지를
  검증하다 실행마다 다른 단언이 깨졌다).

## 환경 (재측정 금지, 이미 확정)
- CachyOS, Hyprland 0.56.2(사용자 설정 = `hyprland.lua`만), Quickshell 0.3.0(`/usr/bin/qs`).

## 검증 원칙
- 증거 없이 완료 주장 금지. "should/probably" 금지.
- **문서 < 설치된 `.qmltypes`·실측.** Quickshell/Hyprland API는 버전마다 달라 문서 신뢰보다 직접 잰다.
- IPC 특이점: booting ≡ not running(exit 255, §9 — "not ready" 구분 불가); IPC 레벨 오류는 stdout + exit 0 → 래퍼가 nonzero로 변환(§11).
- `timeout` 없는 무한 대기 금지(SPEC §19.3, bounded retry).

## 메모리
사용자 지시(계속 유효): 산출물 한국어 · Subagent-Driven 유지 · `hyprland.lua`는 사용자 직접 편집 — 변경 시 사용자 확인.
