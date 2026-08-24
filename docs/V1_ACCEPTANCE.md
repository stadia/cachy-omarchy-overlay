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
| reboot / shutdown | 핵심 | host | 미검증 | |
| shell reload | 핵심 | host | 측정됨 | 2026-08-24 host PASS: `cachy-omarchy-reload` exit 0 으로 셸 PID 873223→893157 교체, `hyprctl layers` 에 omarchy-background·omarchy-bar 복귀, IPC ping ok, 세션 안 doctor DOCTOR_EXIT=0 (PASS 32 + 기존 사용자 override WARN 1), journal 에 QML 오류 없음. **재현된 기존 결함:** 옛 셸의 `inotifywait` PID 873421(`~/.config/omarchy/plugins` 감시)이 살아남아 PPID 876(systemd user manager)으로 리페어런트됐고 새 셸이 893275 를 새로 띄웠다 — 우리 소유 워처가 reload 1회당 1개씩 누적된다. `docs/` 에 기록된 Quickshell `Io.Process` 고아 누수가 테스트 하네스가 아니라 실세션 reload 에서 재현된 것이다. |
| lock 중 reload 거부 | 핵심 | host | 미검증 | |
| idle → screensaver → lock → wake | 핵심 | host | 미검증 | 부분 관측 — 통과 판정 아님. idle IPC status 는 `enabled:true, screensaver:150, lock:300` 으로 타이머가 살아 있고, 2026-08-24 16:24:26 실제 idle 사이클이 돌아 screensaver 프로세스를 띄웠다. 그때의 `process-exit: screensaver exitCode=1` 은 결함이 아니라 설계된 가드다: `omarchy-launch-screensaver` 첫 줄의 `omarchy-cmd-missing ttfx` 가 AUR 전용 `ttfx` 부재를 exit 1 로 흡수한다(`docs/RUNTIME_DEPENDENCIES.md:207`). 이 머신엔 `ttfx` 도 `xdg-terminal-exec` 도 없어 기본 설치에서 스크린세이버 단계는 도달 불가하다. lock→wake 구간은 잠금 해제에 사람이 암호를 넣어야 하므로 미측정으로 남긴다. |
| suspend → resume | 핵심 | host | 미검증 | 이 머신에서 측정 불가: 2026-08-24 16:23:56 `systemctl suspend` 가 logind 에서 "Unit suspend.target is masked, refusing operation" 으로 거부됐다. `/etc/systemd/system/{suspend,sleep,hibernate}.target` 이 2026-07-12 부터 `/dev/null` 로 마스크된 시스템 정책이며 우리 오버레이가 만든 상태가 아니다. 마스크를 푸는 것은 시스템 정책 변경이므로 측정하려면 별도 승인이 필요하다. |
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
