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

- **ISA 레벨.** 2026-08-24 개발 머신의 `/etc/pacman.conf`는
  `cachyos-core-znver4`, `cachyos-extra-znver4`, `cachyos-znver4`를 활성화했고
  `Architecture = auto x86_64_v4`를 쓴다. 같은 머신의
  `/lib/ld-linux-x86-64.so.2 --help`는 `x86-64-v4 (supported, searched)`를
  보고했다. CI 컨테이너의 실제 저장소/loader 출력은 아직 인벤토리에 측정되지
  않았다. 의존 **선언**의 충분성 증명에는 ISA 레벨 차이가 영향을 주지 않는다 —
  패키지 이름과 provides 는 ISA 레벨과 무관하다. 조용히 넘어가지 않기 위해
  기록한다.

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
| init → UWSM 로그인 | 핵심 | vm | 측정됨 | 2026-08-24 VM PASS: 깨끗한 CachyOS 설치본에서 cachy-omarchy-init 멱등 재실행 INIT_EXIT=0, hyprland.lua 358행에 pcall(dofile) 관리 블록 주입, `uwsm start -e -D Hyprland hyprland.desktop` 로그인 뒤 세션 안 doctor DOCTOR_EXIT=0 (session OMARCHY_PATH · Quickshell process running · IPC ping ok), `--ipc shell ping` 이 ok 를 반환, hyprctl layers 에 omarchy-background 와 omarchy-bar 실측, virsh screenshot 으로 바 렌더 확인, journal 에 QML 오류 없음. |
| 패키지 업그레이드 | 핵심 | vm | 측정됨 | 2026-08-24 VM PASS: bin/install-packages --install 로 shell 4.0.0-20 을 설치한 뒤 bump-pkgrel 과 재빌드로 4.0.0-21 로 업그레이드 UPGRADE_EXIT=0, 이전 검증 페어가 1건 아카이브됐고 pacman -Q 가 4.0.0-21 을 보고했다. |
| 롤백 | 핵심 | vm | 측정됨 | 2026-08-24 VM PASS: bin/rollback ROLLBACK_EXIT=0 으로 shell 4.0.0-21 에서 4.0.0-20 으로 다운그레이드했고 previous- 아카이브 매니페스트에서 복원했다. 롤백 뒤 세션 안 doctor 가 DOCTOR_EXIT=0 이며 installed artifact/manifest 가 PASS 로 바뀌었다. |
| 사용자 상태 보존 | 핵심 | vm | 측정됨 | 2026-08-24 VM PASS: 업그레이드와 롤백 전후로 bindings.conf · bindings.lua · hyprland.lua · state 프로브 네 파일의 sha256 이 모두 동일했고 사용자가 손으로 넣은 편집 마커와 관리 source 블록이 그대로 남았다. |
| login / logout | 핵심 | host | 측정됨 | 2026-08-24 host PASS: 16:26:59 세션 13 로그아웃에서 `uwsm_env-preloader` 가 세션 변수(`OMARCHY_PATH`·`WAYLAND_DISPLAY`·`XDG_*`)를 systemd user manager 에서 제거하고 초기 env 를 복원한 뒤 `env_pre`·`env_session.conf`·`env_cleanup.list` 를 삭제, "Stopped target Session envelope of hyprland.desktop" 과 `wayland-wm@hyprland.desktop.service`·`app-graphical.slice` 정리를 거쳐 uwsm 이 RC 0 으로 종료. 16:27:05 세션 16(type=wayland, class=user, tty2)으로 재로그인, 셸 PID 873223 이 Configuration Loaded·polkit agent registered·idle service-ready 를 남김. 세션 안 doctor DOCTOR_EXIT=0 (session OMARCHY_PATH · Quickshell process running · IPC ping ok), `hyprctl layers` 에 omarchy-background 3072x1728 과 omarchy-bar 3072x26 실측 — 불린이 아닌 서피스 증거. 재로그인 뒤 셸 journal 에 QML 오류 없음(아이콘 WARN 만), 구 세션의 elephant PID 3834180 은 사라졌고 `inotifywait` 6 으로 기준선과 동일. 유일한 WARN 은 기존 사용자 override `~/.config/omarchy/shell.json`. |
| reboot / shutdown | 핵심 | host | 측정됨 | 2026-08-24 host PASS: 재부팅 직전 기준값(boot_id `608a23ad…`, 셸 PID 926740, `inotifywait` 고아 2개)과 대조해 수습했다. **종료 측(boot -1):** 17:21:25 `uwsm_env-preloader` 가 세션 env 를 걷어낸 뒤 "Stopped target Session envelope of hyprland.desktop" · "Reached target Shutdown graphical session units" · uwsm `PID 873067 exited with RC 0`, 17:21:31 `Reached target Shutdown` 으로 정상 종료. **복귀 측(boot 0):** boot_id 가 `bae43e68…` 로 교체, `uptime -s` = 2026-08-24 17:22:03, 17:22:30 gdm→uwsm 이 `hyprland.desktop` 을 다시 올리고 17:22:31 셸이 새 PID 7545 로 기동해 Configuration Loaded · polkit agent registered · idle service-ready 를 남김. 세션 안 doctor DOCTOR_EXIT=0(PASS 32 + 기존 사용자 override `~/.config/omarchy/shell.json` WARN 1건만), `hyprctl layers` 에 omarchy-background 3072x1728 과 omarchy-bar 3072x26 실측 — 불린이 아닌 서피스 증거, doctor 의 IPC ping ok. 사용자 상태 보존: 테마 `tokyo-night` 과 배경 심링크 `0-winding-road.jpg` 가 그대로. **누수 결함이 부팅 경계를 넘지 않음을 확인:** reload 로 쌓였던 `inotifywait` 고아 2개가 새 부팅에서 사라지고, 살아 있는 `inotifywait` 은 PID 7765 하나뿐이며 그 PPID 가 새 셸 7545 다(리페어런트된 고아 0). journal 에 QML 오류 없음 — `ERROR` 매치 1건은 QML 이 아니라 xdg-portal 앱ID 중복 등록 WARN 이고, `no outputs - creating placeholder screen` 과 그에 딸린 IpcHandler 중복 등록 WARN 40건은 이전 부팅에도 360건 나오던 기존 모니터 슬립/웨이크 패턴이다. |
| shell reload | 핵심 | host | 측정됨 | 2026-08-24 host PASS: 패치된 셸(4.0.0-22, `setpriv --pdeathsig TERM --` 적용)에서 `cachy-omarchy-reload` exit 0 으로 셸 PID 2105554→2107737 교체. **워처 누수 결함 수정 확인:** 옛 셸 소유 `inotifywait` PID 2105674(`~/.config/omarchy/plugins` 감시)가 reload 직후 100ms 내에 종료 — 커널 parent-death signal(SIGTERM)이 작동했다. reload 후 살아 있는 `inotifywait` 는 PID 2107851 하나뿐이며 그 PPID 가 새 셸 2107737 이다 — **고아 0**. 이전 측정(같은 날 16:39)에서 reload 1회당 1개씩 리페어런트돼 누적되던 결함이 패치로 해결됐다. |
| lock 중 reload 거부 | 핵심 | host | 측정됨 | 2026-08-24 host PASS: `lock status` 가 `locked/requested/sessionLocked/secure` 모두 true 인 실제 잠금 상태에서 `cachy-omarchy-reload` 를 실행하니 exit 1 과 `error: Refusing to restart the shell while the session is locked.` 로 거부했고, 셸 PID 893157 이 그대로 살아남았으며(교체 아님) 잠금 상태도 그대로 유지됐다 — 잠긴 세션에서 셸을 죽여 Hyprland failsafe 에 가두는 사고 경로가 실제로 막힌다. 부수 관측: 잠금 중 `grim` 전체 화면 캡처가 순백으로 나온다. 잠금 서피스는 layer-shell 이 아니라 WlSessionLock 이라 `hyprctl layers` 에도 없고 screencopy 로도 내용이 새지 않는다. |
| idle → screensaver → lock → wake | 핵심 | host | 측정됨 | 2026-08-24 host PASS: 다른 측정을 기다리는 동안 실제 idle 사이클이 통째로 돌았다. 17:04:28 `idle-monitor: idle` → `idle-cycle-start: screensaver=150 lock=300`, 17:06:59 `lock-system: lock-timeout` → `omarchy-system-lock` exit 0 → `lock-requested` → `lock-pending: screen-stabilizing` → `secure=true` 로 설정된 타임아웃에 정확히 잠겼다. 17:09:29 잠긴 채 두 번째 사이클이 돌 때 screensaver 가 exitCode=0 으로 즉시 빠지는데, 이는 `[[ $(omarchy-shell lock isLocked) == "true" ]]` 뒤에 붙은 OR 단락 평가가 동작한 것이다 — 앞선 사이클의 exitCode=1 과 달라 보이지만 둘 다 설계된 경로다(1 = AUR 전용 `ttfx` 부재 가드). 17:11:29 입력이 들어오자 `idle-cycle-cancel: activity` → `omarchy-system-wake` exit 0, 17:11:36 `omarchy-lock-password` PAM 세션으로 암호 인증에 성공해 `secure=false` → `unlocked`. 성공한 인증이 `pam_faillock authsucc` 로 실패 집계를 비웠다(faillock 목록이 비워진 것으로 확인). 잔가시: 잠금 해제 시 `pam_faillock(omarchy-lock-password:auth): Error sending audit message: 명령을 허용하지 않음` — 비특권 quickshell 하위 프로세스가 audit 소켓에 쓸 수 없어 남는 경고이며 인증 자체는 성공한다. |
| suspend → resume | 핵심 | host | 측정됨 | 2026-08-24 host PASS (측정을 위해 시스템 정책을 일시 해제함): `systemctl suspend` 17:17:16 → `Reached target Sleep` → `Successfully froze unit 'user.slice'` → `PM: suspend entry (s2idle)` → 사용자 깨움 → 17:17:20 `System returned from sleep operation 'suspend'` → user.slice/session-16.scope thawed → `PM: suspend exit` 로 약 4초짜리 s2idle 사이클이 온전히 돌았다. 복귀 후 우리 표면은 무손상: 셸 PID 926740 이 그대로 살아남았고(재시작 없음) omarchy-background·omarchy-bar 서피스 유지, IPC ping ok, 세션 안 doctor DOCTOR_EXIT=0(기존 사용자 override WARN 1건만), journal 에 QML 오류 없음, NetworkManager 가 wlan0 를 재연결해 `omarchy-network-status` 가 다시 정상 값을 반환했다. **측정 조건 — 이 머신에서 suspend 는 공짜가 아니다.** `/etc/systemd/system/{sleep,suspend,hibernate}.target` 의 `/dev/null` 마스크(2026-07-12 설정)는 실수가 아니라 의도된 정책이다: suspend 중 NetworkManager 가 wlan0 를 내리면서 이 호스트의 k3s 에이전트가 `failed to validate nodeIP: node IP "192.168.1.192" not found in the host's network interfaces` 와 lease 갱신 타임아웃을 냈다(17:17:25~17:17:35). 네트워크가 돌아온 뒤 에이전트는 스스로 회복했지만, 로컬 상주 에이전트·k3s 노드를 돌리는 머신에서는 suspend 가 워크로드를 흔든다. 측정이 끝났으므로 마스크는 원래대로 복원한다. |
| 테마 / 배경 | 핵심 | host | 측정됨 | 2026-08-24 host PASS: `omarchy-theme-list` 가 셸 세션 환경에서 23개 테마를 반환. `omarchy-theme-bg-next` 로 배경이 Winding Road→Quattro 로 바뀌며 `~/.local/state/omarchy/current/background` 심링크가 따라갔고, `omarchy-theme-set Nord` 로 테마가 Tokyo Night→Nord 로 전환되며 배경도 그 테마 기본값(Black Moon)으로 함께 이동했다. 같은 바 영역 전후 `grim` 캡처를 겹쳐 보면 바 배경/구분선 색과 배후 배경이 실제로 바뀌었다 — 셸 재시작 없이 라이브 적용. `omarchy-theme-set "Tokyo Night"` 으로 테마·배경 모두 원상복구 확인. 잔가시: 사용자 테마 디렉터리가 없으면 `omarchy-theme-list` 가 `find: ~/.config/omarchy/themes/ 없음` 을 stderr 로 흘린다(목록 자체는 정상). |
| 투명 바 대비 | 핵심 | host | 측정됨 | 2026-08-24 host PASS: `omarchy-bar-text-color top 26 #a9b1d6 #1a1b26` 가 현재 배경(`Winding Road`)의 상단 26px 스트립을 magick 으로 1x1 샘플링해 WCAG 상대휘도 대비를 계산하고 `#a9b1d6` 을 선택 — fallback 이 아니라 실제 계산 경로. 같은 순간의 `grim` 풀스크린 캡처(3840x2160)에서 상단 바 스트립을 잘라 확인: 좌측 워크스페이스 1~5, 중앙 `Monday 16:33` + 날씨, 우측 트레이 아이콘이 배경 위에서 판독 가능. |
| 클립보드 / 이모지 | 핵심 | host | 측정됨 | 2026-08-24 host PASS: `wl-copy` 로 넣은 마커가 `wl-paste` 로 왕복했고 셸의 클립보드 히스토리가 178→179 로 증가하며 마커가 최상단에 기록됨. `omarchy-menu-clipboard`(= `omarchy-shell shell toggle omarchy.clipboard`) 토글로 `omarchy-clipboard` layer 등장→소멸, 캡처에 검색창·히스토리 목록·미리보기 패널이 한글 항목까지 렌더. `omarchy-menu-emoji` 토글로 `omarchy-emojis` layer 등장→소멸, 캡처에 컬러 이모지 그리드 렌더. |
| 알림 | 핵심 | host | 측정됨 | 2026-08-24 host PASS: `omarchy-notification-send` exit 0 뒤 `hyprctl layers` 에 `omarchy-notifications` 서피스가 등장했고, `grim` 캡처에서 제목 `acceptance probe` 와 한글 본문이 실제로 그려진 토스트를 확인 — 불린이 아닌 렌더 증거. IPC target `notifications` 에 dismiss/dnd/history 함수가 노출됨. |
| 날씨 | 핵심 | host | 측정됨 | 2026-08-24 host PASS: `omarchy-weather-status` 가 `Gwangju · Temp 29°C · Wind →9km/h`, `omarchy-weather-location` 이 `Gwangju` 를 반환. 같은 값이 바 캡처 중앙 위젯에도 렌더됨. |
| 오디오 입출력 | 핵심 | host | 측정됨 | 2026-08-24 host PASS: `omarchy-audio-sink-availability` 가 analog-stereo 와 hdmi-stereo 두 싱크를 가용으로 보고하고 `omarchy-audio-output-sink` 가 현재 hdmi-stereo 를 반환. `omarchy-audio-output-volume -5` → `+5` 로 wpctl 볼륨이 1.00→0.95→1.00 으로 왕복했고 그 순간 `omarchy-osd` layer 가 렌더됨. 입력 소스도 열거됨(현재 사용자 상태는 MUTED). |
| 블루투스 | 핵심 | host | 측정됨 | 2026-08-24 host PASS: `omarchy-bluetooth-power is-on` exit 0(전원 켜짐), 컨트롤러 2C:C6:82:96:4C:88 (cachyos) 가 rfkill 언블록 상태로 보고되고 페어링된 기기 2대(Magic Mouse, Xbox Wireless Controller)가 열거됨. Magic Mouse 는 세션 입력으로 실사용 중. |
| NetworkManager | 핵심 | host | 측정됨 | 2026-08-24 host PASS: `omarchy-network-status` 가 `wifi	Ahch-To_Jedi_Temple	77	5240.0` 를 반환(연결 종류·SSID·신호세기·대역). `nmcli general status` 는 connected:full. |
| 전원 프로파일 | 핵심 | host | 측정됨 | 2026-08-24 host PASS: `omarchy-powerprofiles-list --active-state` 가 power-saver/balanced/performance 세 프로필과 balanced 활성(1)을 반환하고 D-Bus `net.hadess.PowerProfiles.ActiveProfile` 도 balanced. **측정 함정 기록:** 대화형 셸 PATH 로 실행하면 linuxbrew/mise python 이 `/usr/bin/python3` 를 가려 `powerprofilesctl` 이 `No module named 'gi'` 로 죽고, 헬퍼가 `2>/dev/null` 로 stderr 를 삼켜 빈 출력 + exit 0 인 조용한 실패처럼 보인다. 셸 프로세스(`/proc/<quickshell>/environ`)의 uwsm 세션 PATH 에는 linuxbrew/mise 가 없어 정상 동작한다 — 헬퍼 측정은 반드시 세션 PATH 로 한다. |
| 스크린샷 | 핵심 | host | 측정됨 | 2026-08-24 host PASS: `omarchy-capture-screenshot fullscreen save` exit 0 으로 3840x2160 PNG(3.7MB) 생성. 경로는 `hyprshot`/`satty`/`swappy` 가 아니라 hyprpicker 프리즈 + `grim` + `wl-clipboard` + jq 이며 넷 다 설치돼 있다. 헬퍼가 캡처 동안 `cursor:no_hardware_cursors` 를 0 으로 바꿨다가 trap 으로 원복하는 경로까지 실행됐고, 캡처 이미지에 바·배경·창이 모두 담겼다. |
| polkit (아래 §polkit) | 핵심 | host | 측정됨 | 2026-08-24 host PASS: §polkit 0~5 단계 전부 측정 완료. 응답 에이전트는 우리 셸이며 `hyprpolkitagent` 와의 경합은 실제로 일어나지 않았다. 프롬프트 등장·취소·오답 재시도·정답 권한 상승·셸 재시작 후 재등록이 모두 확인됐다. **잠금 중 polkit 취소 결함 수정 확인:** 활성 `pkexec /usr/bin/id` 프롬프트(omarchy-polkit 서피스 PID 2107737)에서 `omarchy-system-lock` 트리거 시 100ms 내 `Request dismissed` + exit 127로 종료, 서피스 소멸(§polkit 참조). 잠금 해제 후 새 `pkexec /usr/bin/id` 정상 인증 exit 0 + `uid=0(root)`, faillock 깨끗. |

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
`omarchy.polkit` 은 "현재는 활성 — 시스템 polkit 과 충돌 가능하다는 우려는
남아 있음, 재검토 필요" 상태로 열어둔 상태다.
두 에이전트가 경합 중이고 어느 쪽이 이기는지 모른다.

측정 시퀀스:

| 단계 | 확인 | 결과 |
| --- | --- | --- |
| 0 | 어느 에이전트가 응답하는가 | 2026-08-24 **우리 셸**. 셸이 기동/reload 마다 `omarchy polkit agent registered` 를 남기고(16:27:07 구 셸, 16:39:20 reload 후 신 셸) 실제 프롬프트도 셸의 `omarchy-polkit` 서피스로 뜬다. `org.hyprland.hyprpolkitagent` 는 유저 버스에 **activatable 로만** 존재하고 이 세션에서 한 번도 활성화되지 않았다 — 경합이 가설이었을 뿐 실제로는 일어나지 않는다. 이 세션 저널에 중복 등록 WARN 없음. |
| 1 | GUI 권한 요청 → 프롬프트 등장 | 2026-08-24 PASS: `pkexec /usr/bin/id`(action `org.freedesktop.policykit.exec`, `auth_admin` — 캐시 없음) 실행 시 `hyprctl layers` 에 `omarchy-polkit` 등장, 캡처에 `Authorize running '/usr/bin/id'` 제목과 자물쇠 + 암호 입력창이 실제로 렌더됨. |
| 2 | 취소 → 요청이 거부로 끝나는가 | 2026-08-24 PASS: Escape 후 `pkexec` 가 exit 126 + `Error executing command as another user: Request dismissed`, 서피스 소멸, polkitd 가 해당 action 에 대해 FAILED to authenticate 를 기록하고 `polkit-agent-helper@…service` 가 Deactivated successfully — 헬퍼 유닛 누수 없음. |
| 3 | 틀린 암호 → 재시도 허용 / 잠금 없음 | 2026-08-24 부분 PASS + **주의 사항**: 틀린 암호에 `pam_unix authentication failure` 뒤 에이전트가 재시도 헬퍼(`helper@9`)를 한 번 더 띄웠으므로 재시도 경로는 있다. 그러나 **잠금은 일어난다** — 시스템 기본 faillock(`/etc/security/faillock.conf` 전부 주석 = `deny=3`, `unlock_time=600`)에 실패가 3건 차면서 sudo·polkit 이 10분간 거부 상태가 됐다. 더 놀라운 것은 **프롬프트 "취소"도 실패로 집계된다**는 점이다(16:49:16 취소, 16:51:05 오답, 16:51:34 재시도 무입력 = 3건) — 취소 3번이면 sudo 가 잠긴다. 이는 배포판 PAM 정책이지 우리 것이 아니다. |
| 4 | 맞는 암호 → 권한 상승 성공 | 2026-08-24 PASS: 프롬프트에 올바른 암호를 넣자 `pkexec /usr/bin/id` 가 rc=0 과 `uid=0(root) gid=0(root) groups=0(root)` 를 반환 — 실제 권한 상승이 우리 셸 에이전트를 통해 이뤄졌다. `pam_unix(polkit-1:session): session opened for user root` 기록, 서피스 소멸, `polkit-agent-helper@…service` Deactivated successfully. 성공한 인증이 `pam_faillock authsucc` 로 실패 집계를 비웠다(faillock 목록 공백 확인). |
| 5 | 셸 재시작 후 1~4 반복 — 등록이 살아남는가 | 2026-08-24 PASS: `cachy-omarchy-reload` 로 셸을 893157→926740 으로 교체한 직후 저널에 `omarchy polkit agent registered` 가 다시 남았고, 새 셸에서 프롬프트가 정상 등장(1)하고 올바른 암호가 다시 rc=0 · uid=0(root) 를 냈다(4). 앞선 1~3 단계도 이미 reload 로 태어난 셸(893157)에서 측정한 것이므로 등록은 재시작을 두 번 넘겨 살아남았다. 등록 중복 WARN 은 어느 재시작에서도 나타나지 않았다. |

**reload 워처 누수 — 수정됨(2026-08-24 21:25).** 패치 `0001-stop-plugin-watcher-on-shell-exit.patch` 가 `setpriv --pdeathsig TERM --` 로 커널 parent-death signal을 워처에 건다. 패치된 셸(4.0.0-22)에서 `cachy-omarchy-reload` exit 0 로 셸 PID 2105554→2107737 교체 시, 옛 셸 소유 `inotifywait` PID 2105674 가 100ms 내에 종료됐다 — 커널이 SIGTERM을 보냈다. reload 후 살아 있는 `inotifywait` 는 PID 2107851 하나뿐이며 PPID 가 새 셸 2107737 이다 — **고아 0**. 이전 측정에서 **reload 1회당** 1개씩 systemd user manager 로 리페어런트돼 영구히 남던 결함이 패치로 해결됐다.

**polkit 잠금 취소 — 수정됨(2026-08-24 21:25).** 패치 `0002-cancel-polkit-flow-before-session-lock.patch` 가 `PolkitAgent.cancelForSessionLock()` 와 `lock.Service.cancelPolkitForSessionLock()` 를 추가한다. 활성 `pkexec /usr/bin/id` 프롬프트(`omarchy-polkit` 서피스, 셸 PID 2107737)에서 `omarchy-system-lock` 트리거 시 100ms 내 `Error executing command as another user: Request dismissed` + exit 127로 종료, `omarchy-polkit` 서피스 소멸. 잠금 해제 후 새 `pkexec /usr/bin/id` 정상 인증 exit 0 + `uid=0(root) gid=0(root) groups=0(root)`, `faillock --user stadia` 깨끗. 이전 결함 후보(idle/잠금을 사이에 둔 요청이 영구 대기로 남는 문제)가 패치로 해결됐다.

**화면 잠금은 이 정책에서 분리돼 있다.** 우리가 소유한 `/etc/pam.d/omarchy-lock-password` 는
`pam_faillock` 을 `deny=10 unlock_time=120` 으로 명시해 시스템 기본(3/600)보다 관대하다.
그래서 polkit 오답으로 sudo 가 잠긴 순간에도 사용자는 자기 화면 잠금을 풀 수 있다 —
"자기 세션에서 쫓겨나지 않는다"가 설계 의도대로 실측됐다. faillock 집계는 사용자 단위로
공유되지만 임계값은 서비스마다 따로 평가되기 때문이다.

**3 단계의 함정:** 이 환경에서 `auth could not identify password` 는 틀린
암호가 아니라 **입력이 도달하지 않은 것**일 수 있다(한글 입력기). 측정 전
한/영 상태를 확인하지 않으면 없는 결함을 만들어낸다.

## VM lane 측정 기록 (2026-08-24)

**측정 환경.** 호스트의 `qemu:///session` 도메인 `coo-rc-vm` (4 vCPU, 8GiB,
40GiB qcow2, q35, UEFI secure-boot off, virtio-gpu, passt 사용자 네트워킹).
게스트는 `cachyos-desktop-linux-260809.iso` 로 `cachyos-installer` 무인 설치했다.
ISO SHA256 은 미러와 CDN 의 공표값, 내려받은 파일의 재계산값이 모두
`959f6577f45e25ee9fd8c220fd221b08e4ea79412c7315c0f922dd6d86d5e33c` 로 일치했다.
커널 `7.2.0-1-cachyos`, 루트 `/dev/vda2` ext4, 저장소 `[cachyos] [core] [extra]
[multilib]`, loader 는 `x86-64-v4 (supported, searched)` 를 보고했다.

**기준선과 복원.** 설치 직후 405 개 패키지, `omarchy` 와 `omarchy-settings` 는
물론 `hyprland` `uwsm` `quickshell` 도 모두 부재, 실패 유닛 0. 스냅샷
`task10-baseline` (2026-08-24 08:35:38, shutoff) 을 만든 뒤 마커 파일 생성 →
revert → 마커 소멸과 405 개 복귀로 복원 가능성을 실측했다.

**의존 해석 게이트.** 게스트 안에서 `bin/build-packages` 로 두 패키지를 빌드하고
`bin/ci-resolve-install` 을 root 로 돌렸다. 게이트 A·B·C 가 모두 `ok` 를 냈고
`의존 해석 lane 통과` 로 끝났다. 설치 뒤 패키지 수는 405 에서 605 로 늘었고
`hyprland 0.56.2-1` `uwsm 0.26.6-1` `quickshell 0.3.1-1` 이 우리 depends 로
끌려왔다 — 설치 전에 셋 다 없었으므로 depends 선언이 실제로 이들을 해석한다는
직접 증거다. 이것은 VM 실측이며, 같은 이름을 가진 container lane 항목은 CI 가
이 브랜치에서 아직 돌지 않았으므로 미검증으로 남긴다.

**측정 조건과 편차.** 이 이미지는 설치기의 `server_profile` 을 `minimal` 로
골랐다. 데스크톱 프로파일은 수백 개 패키지를 미리 설치해 "우리 depends 선언이
충분한가" 라는 주장을 약화시키기 때문이다. 그 결과 ufw 가 inbound 기본 거부로
켜져 있고(22 만 허용), sshd 는 키 전용이며, server sysctl 이 적용돼 있다.
커널만 `linux-cachyos` 로 덮어썼다. 또 이 최소 이미지에는 pipewire 와
xdg-desktop-portal 이 없어 셸이 `Failed to connect pipewire context` 와 포털
등록 경고를 남긴다 — 최소 이미지의 결과이지 제품 결함이 아니다.

**무인 측정 장치.** `bin/install-packages` 와 `bin/rollback` 이 부르는 `sudo` 는
tty 가 없으면 암호를 읽지 못하고, sudo 타임스탬프는 tty 가 없을 때 ppid 에 묶여
스크립트가 부르는 자식 `sudo` 에 적용되지 않는다. 시스템 sudo 정책은 그대로 두고
스크립트가 이미 제공하는 `COO_SUDO_BIN` 을 sudo askpass 헬퍼로 지정해 무인으로
돌렸다. `sudo pacman` 이라는 실제 경로 자체는 바뀌지 않는다.

**범위 밖.** 유휴 시간이 지나 잠금 화면이 뜬 것을 지나가며 관측했으나,
lock 과 suspend 와 logout 과 reboot 과 polkit 은 host lane 항목이므로 측정으로
기록하지 않는다.
