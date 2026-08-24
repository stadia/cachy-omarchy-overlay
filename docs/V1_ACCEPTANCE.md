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
