# v1.0 Acceptance 인벤토리

1.0 선언의 게이트를 소유하는 문서. `docs/RC_GAP_INVENTORY.md` 는 M7 시점
SPEC §61 의 역사적 기록으로 남으며, 이 문서가 그보다 넓은 목록(하드웨어·
업그레이드·polkit)을 다룬다.

## 게이트 규칙

- **핵심** 항목이 하나라도 미측정이거나 실패면 1.0 을 선언하지 않는다.
- **주변** 항목 — 이 머신에 물리적으로 없는 하드웨어에 종속된 것 — 은
  `미검증` 으로 명시하고 통과시킨다.
- 측정해서 **실패한** 것은 등급과 무관하게 수정 대상이다. "알려진 버그로
  1.0 출고"는 하지 않는다.

증거 등급: `측정됨` = 실제 관측, `추론됨` = 코드/정적 검사만, `미검증` =
관측 없음. `추론됨` 과 `미검증` 은 핵심 항목의 통과 판정이 아니다.

## lane

| lane | 담당 | 범위 |
| --- | --- | --- |
| `container` | CI (`.github/workflows/ci.yml`) | 설치·의존 해석·init 헤드리스 |
| `auto-live` | `COO_RUN_LIVE=1 tests/test.sh` | 런처/키바인딩 토글, 앱 실행, 앱 스코프 격리 |
| `vm` | 깨끗한 VM | init → UWSM 로그인 완주, 업그레이드·롤백·상태 보존 |
| `host` | 실기기 | 하드웨어, 세션 라이프사이클, polkit |

## 알려진 편차

- **ISA 레벨.** 개발 머신은 znver4 저장소를 쓰지만 CI 컨테이너는 다른 최적화
  레벨의 저장소로 떨어진다(실측 command 의 stdout(저장소 섹션과 loader 지원 ISA 출력)을 증거 칸에 전문으로 인용). 의존 **선언**의
  충분성 증명에는 영향이 없다 — 패키지 이름과 provides 는 ISA 레벨과
  무관하다. 조용히 넘어가지 않기 위해 기록한다.

## 측정 순서

위험도 오름차순으로 측정한다: 읽기 전용 관측 → 되돌릴 수 있는 조작(런처,
알림, 클립보드) → 세션을 건드리는 것(reload, lock, idle) → 세션을 끝내는
것(logout, suspend, reboot). 이 저장소는 라이브 측정 중 uwsm Wayland 기동
레이스와 xremap 크래시 루프로 물린 전례가 있다.

## 핵심 — 측정됨 필수

아래 "도구" 항목의 헬퍼는 `overlay/bin/` 에 없다. 그곳에는 우리가 소유한
7 개만 있고, 스크린샷·녹화·프레젠테이션은 스테이징된 upstream 헬퍼다.
측정 대상은 설치 트리의 그 헬퍼이지 우리 래퍼가 아니다. 스크린샷은 핵심이지만,
녹화와 프레젠테이션은 제공자가 선택 의존성이므로 주변 항목이다.

| 항목 | 등급 | lane | 상태 | 증거 |
| --- | --- | --- | --- | --- |
| 설치 — 의존 자동 해결 | 핵심 | container | 미검증 | |
| 공식 omarchy 부재 | 핵심 | container | 미검증 | |
| 폐쇄 스캐너 (실설치 트리) | 핵심 | container | 미검증 | |
| init 헤드리스 완주 | 핵심 | container | 미검증 | |
| 런처 토글 | 핵심 | auto-live | 측정됨 | 2026-08-23 `COO_RUN_LIVE=1 ./tests/test.sh test_launcher_toggle` PASS: `omarchy-menu` layer 표시·화면 기하 확인, Escape 뒤 layer 제거, journal QML 오류/`ERROR` 없음; `inotifywait` 6→6. |
| 키바인딩 토글 | 핵심 | auto-live | 측정됨 | 2026-08-23 `COO_RUN_LIVE=1 ./tests/test.sh test_keybindings_toggle` PASS: `omarchy-menu` layer 표시·화면 기하 확인, v13 관리 source 포함 Lua cache 49행, Escape 뒤 layer 제거 및 helper exit 0, journal QML 오류/`ERROR` 없음; `inotifywait` 6→6. |
| 앱 실행 | 핵심 | auto-live | 측정됨 | 2026-08-23 `COO_RUN_LIVE=1 ./tests/test.sh test_app_launch` PASS: test-owned extracted shell의 Apps menu에서 sandbox `.desktop` probe를 선택해 marker 생성, menu layer 제거 확인; `inotifywait` 6→6. |
| 앱 스코프 격리 | 핵심 | auto-live | 측정됨 | 2026-08-23 `COO_RUN_LIVE=1 ./tests/test.sh test_app_scope` PASS: probe가 `app-graphical.slice`의 독립 scope에 있고 extracted shell 재시작 뒤에도 생존; `inotifywait` 6→6. |
| init → UWSM 로그인 | 핵심 | vm | 미검증 | |
| 패키지 업그레이드 | 핵심 | vm | 미검증 | |
| 롤백 | 핵심 | vm | 미검증 | |
| 사용자 상태 보존 | 핵심 | vm | 미검증 | |
| login / logout | 핵심 | host | 미검증 | |
| reboot / shutdown | 핵심 | host | 미검증 | |
| shell reload | 핵심 | host | 미검증 | |
| lock 중 reload 거부 | 핵심 | host | 미검증 | |
| idle → screensaver → lock → wake | 핵심 | host | 미검증 | |
| suspend → resume | 핵심 | host | 미검증 | |
| 테마 / 배경 | 핵심 | host | 미검증 | |
| 투명 바 대비 | 핵심 | host | 미검증 | |
| 클립보드 / 이모지 | 핵심 | host | 미검증 | |
| 알림 | 핵심 | host | 미검증 | |
| 날씨 | 핵심 | host | 미검증 | |
| 오디오 입출력 | 핵심 | host | 미검증 | |
| 블루투스 | 핵심 | host | 미검증 | |
| NetworkManager | 핵심 | host | 미검증 | |
| 전원 프로파일 | 핵심 | host | 미검증 | |
| 스크린샷 | 핵심 | host | 미검증 | |
| polkit (아래 §polkit) | 핵심 | host | 미검증 | |

## 주변 — 미검증 문서화 허용

| 항목 | 등급 | lane | 상태 | 증거 |
| --- | --- | --- | --- | --- |
| 노트북 배터리 | 주변 | host | 미검증 | 이 머신에 배터리가 없다 |
| 외부 모니터 | 주변 | host | 미검증 | 대상 모니터 없음 |
| DDC 밝기 | 주변 | host | 미검증 | DDC 대상 모니터 없음 |
| QR 스캔 / OCR | 주변 | host | 미검증 | `zbar`·`tesseract` 는 OPT 분류(`docs/RUNTIME_DEPENDENCIES.md:200,223`) — hard depends 가 아니라 사용자가 그 기능을 씀으로써 선택하는 경로다. 기본 설치에 없는 것을 핵심 게이트로 둘 수 없다. 두 패키지를 설치한 상태에서 측정되면 그 조건과 함께 기록한다. |
| 화면 녹화 | 주변 | host | 미검증 | `ffmpeg`·`gpu-screen-recorder` 는 OPT(`docs/RUNTIME_DEPENDENCIES.md:134,139`). 둘을 설치한 조건에서 측정되면 패키지명·버전을 함께 기록한다. |
| 플로팅 프레젠테이션 터미널 | 주변 | host | 미검증 | 구동 기계 `xdg-terminal-exec` 는 AUR OPT 이다(`docs/RUNTIME_DEPENDENCIES.md:221`). 설치한 조건에서만 측정하며, 기본 `pacman -S` 성공의 핵심 게이트로 쓰지 않는다. |

## polkit

우려가 가설이 아니다. `docs/RUNTIME_STARTUP.md:1610` 이 저널에 "polkit
에이전트 중복 등록 WARN" 이 실제로 남는다고 기록하고 있고,
`docs/PLUGIN_AUDIT.md:38` 은 `omarchy.polkit` 을 "현재는 활성 — 시스템
polkit 과 충돌 가능하다는 우려는 남아 있음, 재검토 필요" 로 열어둔 상태다.
두 에이전트가 경합 중이고 어느 쪽이 이기는지 모른다.

측정 시퀀스:

| 단계 | 확인 | 결과 |
| --- | --- | --- |
| 0 | 어느 에이전트가 응답하는가 | |
| 1 | GUI 권한 요청 → 프롬프트 등장 | |
| 2 | 취소 → 요청이 거부로 끝나는가 | |
| 3 | 틀린 암호 → 재시도 허용 / 잠금 없음 | |
| 4 | 맞는 암호 → 권한 상승 성공 | |
| 5 | 셸 재시작 후 1~4 반복 — 등록이 살아남는가 | |

**3 단계의 함정:** 이 환경에서 `auth could not identify password` 는 틀린
암호가 아니라 **입력이 도달하지 않은 것**일 수 있다(한글 입력기). 측정 전
한/영 상태를 확인하지 않으면 없는 결함을 만들어낸다.
