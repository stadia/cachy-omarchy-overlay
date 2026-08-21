# Cachy Omarchy Overlay

*[English README](README.md)*

CachyOS + Hyprland에서 [Omarchy](https://github.com/basecamp/omarchy) Quattro 셸을
**업스트림 그대로** 구동하기 위한 Arch 패키지 오버레이.

런처를 재구현하지 않는다. 공식 Omarchy 저장소를 커밋 단위로 핀하고, 필요한 런타임만
추출·패키징하며, 패치가 꼭 필요할 때만 최소한으로 적용한다(SPEC §1).

```text
SUPER + SPACE  →  Omarchy Quattro 런처 / 메뉴
SUPER + K      →  Omarchy 스타일 키바인딩 뷰어
```

## 구성 요소

두 개의 Arch 패키지를 만든다.

| 패키지 | 버전 | 역할 |
|---|---|---|
| `cachy-omarchy-shell` | 4.0.0-10 | 핀된 Omarchy Quattro 셸 런타임 (Quickshell 트리, `omarchy-settings` 제외) |
| `cachy-omarchy-overlay` | 0.8.2-1 | CachyOS 통합 계층 (래퍼 명령, Hyprland 바인딩, 기본값) |

업스트림 핀은 `upstream.lock`이 관리한다 (현재 `basecamp/omarchy @ v4.0.0`,
`f0020448`).

설치되는 공개 명령 7개 (`/usr/bin`):

- `cachy-omarchy-shell` — 셸 기동(`--run`)·IPC(`--ipc`)·수동 재기동(`--restart`)
- `cachy-omarchy-launcher` — 런처 토글 (SUPER + SPACE)
- `cachy-omarchy-keybindings` — 키바인딩 뷰어 토글 (SUPER + K)
- `cachy-omarchy-bindings` — 사용자 Hyprland 설정에 관리 source 블록 주입/제거
- `cachy-omarchy-init` — 최초 1회 사용자 설정 생성 (기존 파일 덮어쓰지 않음)
- `cachy-omarchy-doctor` — 읽기 전용 진단 (테마 상태 포함)
- `omarchy-theme-set` — 감사된 업스트림 helper 집합으로 테마 적용

## 세션 요구사항

로그인할 때 **Hyprland (uwsm-managed)** 를 선택해야 한다. 두 패키지는 공식
`omarchy` 패키지와 같은 `/usr/bin/omarchy-*` 이름을 소유하므로 서로 충돌한다.

## 테마

업스트림 테마 파이프라인을 그대로 쓴다 (M9). 첫 `cachy-omarchy-init` 이 테마가
없을 때만 "Tokyo Night" 를 시드한다.

```bash
omarchy-theme-set "Nord"     # 전환 — 셸 재시작 없이 바·메뉴에 반영
```

또는 런처 메뉴의 `Style > Theme`. 테마 상태는 업스트림과 같은
`~/.local/state/omarchy/current/theme/` 에 있고, 사용자 오버레이
(`~/.config/omarchy/themes/<name>/`)가 패키지 테마 위에 합쳐진다.

## 유틸리티 플러그인 (M10)

업스트림 first-party 플러그인 다섯 개 — clipboard·emojis·image-picker·
reminders·OSD — 는 업스트림 규칙상 기본 로드된다. M10 은 그 QML 이 부르는
helper 와 런타임 의존성(`jq`, `wl-clipboard`, `wtype`, `wireplumber`,
`pipewire-pulse`, `xdg-utils`)을 패키지가 닫는다.

- **Clipboard** — 메뉴의 clipboard 항목 또는 `omarchy.clipboard` 토글. 히스토리는
  업스트림과 같은 `~/.local/state/omarchy/clipboard-history.json` (최대 300개,
  로컬 전용)에 기록되며, 민감한 selection(비밀번호 관리자 hint 등)은 저장하지
  않는다. `cachy-omarchy-doctor` 가 경로와 항목 수를 읽기 전용으로 보고한다.
  지우는 것은 사용자의 명시 동작뿐이다.
- **Emojis** — 메뉴의 Emoji 항목. 선택한 emoji 를 clipboard 에 넣고 focused 앱에
  한 번 붙여넣는다. 취소는 아무 side effect 도 없다.
- **Image picker** — 테마/배경 선택 등에 쓰이는 업스트림 image-grid (M9 의
  `omarchy-menu-images` 경로 그대로).
- **Reminders** — `omarchy-reminder -i`/메뉴에서 설정. user systemd 타이머
  (`omarchy-reminder-*.timer`)와 `${XDG_RUNTIME_DIR:-/tmp}/omarchy-reminders/`
  메타데이터만 사용한다 — system 유닛·`/etc`·root 없음.
- **OSD** — 볼륨/마이크 뮤트 helper 와 `omarchy-osd` 가 upstream `omarchy.osd`
  패널을 띄운다. 감사된 helper 는 `/usr/bin/omarchy-*`로 노출되며, 올바르게
  동작하려면 그래픽 uwsm 세션이 공급하는 `OMARCHY_PATH`가 필요하다. XF86 미디어 키 바인딩은 주입하지 않는다 — 도달 경로는
  명시적 CLI/메뉴뿐이다 (화면 밝기 체인은 범위 밖).

## 기동 모델

셸은 systemd 유닛이 아니라 **Hyprland autostart**로 뜬다 — 업스트림 omarchy와 같은
모델이다. `bindings.lua`가 `hyprland.start` 이벤트(세션 시작 시 1회)에
`cachy-omarchy-shell --run`을 실행한다. 크래시 시 자동 재기동은 없으며
`cachy-omarchy-shell --restart`로 수동 복구한다.

## 빌드와 설치

```bash
bin/build-packages           # 두 패키지 빌드 + 감사 (build/*.pkg.tar.zst)
bin/install-packages         # 빌드 산출물 설치
cachy-omarchy-init           # 최초 1회: 바인딩 + 사용자 상태 생성
```

`cachy-omarchy-init` 은 첫 실행에서 잠금 화면도 설정한다. 업스트림
`omarchy-apply-lock` 헬퍼에 위임하며, 그 헬퍼가 `/etc/pam.d/omarchy-lock-password`
를 쓰기 때문에 sudo 를 묻는다. 이 PAM 서비스가 없으면 셸은 잠금을 거부하고
`omarchy-system-lock` 은 아무 일도 안 한 채 exit 0 이므로, 프롬프트를 건너뛰었다면
나중에 `omarchy-apply-lock` 을 직접 실행한다. `cachy-omarchy-doctor` 는 이
서비스의 부재를 FAIL 로 보고한다.

업스트림 추적:

```bash
bin/check-upstream           # 핀 대비 업스트림 변경 확인
bin/update-upstream          # 핀 갱신 + 재빌드 파이프라인
bin/rollback                 # 이전 핀으로 복귀
```

## 개발

```bash
./tests/test.sh              # 전체 테스트 (각 테스트는 격리 샌드박스 HOME에서 실행)
./tests/test.sh wrapper      # 필터 실행
```

문서 지도:

- `SPEC.md` — 최종 권위 명세
- `UPSTREAM.md` — 업스트림 핀/추적 정책
- `docs/RUNTIME_STARTUP.md` — 기동 경로·플러그인 비활성화 실측

마일스톤 설계·구현 플랜은 비공개 개발 트리에 남겨 두고 이 저장소에는 담지 않는다.
공개 문서에서 설계 기록을 인용할 때는 파일명만 밝힌다.

## 로드맵

- **v0.1** — 런타임 패키징 + 런처 + 키바인딩 + 업데이트/재빌드. 완료.
- **v0.2 (Milestone 8)** — `omarchy.bar` 채택. 완료(`v0.2.0`). 업스트림 바를
  켠 채로 출고한다. Waybar를 대체하지는 않는다 — 둘을 함께 띄우면 겹치지 않고
  쌓이며(세로 예약 `36 → 62px`), 우리는 Waybar를 중지·제거하지 않는다.
- **v0.3 (Milestone 9)** — 업스트림 테마 런타임 채택. 완료(`v0.3.0`).
  `themes/`+`default/themed/`+테마 helper 를 같은 핀에서 스테이징하고,
  `/usr/bin` 심링크로 업스트림 `omarchy-theme-set` 을 무패치 실행한다. 실측: `docs/RUNTIME_STARTUP.md` §18.6.
- **v0.4 (Milestone 10)** — 유틸리티 플러그인(clipboard·emojis·image-picker·
  reminders·OSD) helper/의존성 채택. 완료(`v0.4.0`). 실측:
  `docs/RUNTIME_STARTUP.md` §19.2.
- **v0.5** — 세션 환경: uwsm Hyprland 드롭인이 `OMARCHY_PATH` 를 공급하고,
  `/usr/bin/omarchy-*` 는 심링크만 놓는 뷰이며 PATH 는 조작하지 않는다.
  완료(`v0.5.0`). 실측: `docs/RUNTIME_STARTUP.md` §20.
- **v0.6** — 메뉴 `style.bar` 와 세션 lock/logout/reboot/shutdown helper 를
  스테이징한다 (`omarchy-bar` 및 config/catalog/state/window-close 전이).
  factory-reset 은 Omarchy ISO `@factory` 전제라 PATH 에 올리지 않는다.
  완료(`v0.6.0`).
- **v0.7** — 오디오 출력 전환/튜닝 템플릿, 디스플레이 밝기, 터치패드·터치스크린
  가드를 verbatim 스테이징. laptop/monitor-internal 은 래퍼가 필요해서 PATH 에
  올리지 않는다. 완료(`v0.7.0`). 실측: `docs/RUNTIME_STARTUP.md` §21.1.
- **v0.8** — 테마 설치/갱신/제거(`omarchy-theme-install`/`-update`/`-remove`),
  Hyprland 토글, 하드웨어 helper 를 verbatim 스테이징(`v0.8.0`) — 이 릴리스가
  `omarchy-hw-laptop` 과 monitor-internal 체인에 대한 v0.7 의 "래퍼 필요" 판단을
  뒤집었다; 둘 다 이 릴리스부터 스테이징된다. 키바인딩 시트가 오버레이 자신의
  바인드를 읽고(`v0.8.1`), 명령이 아니라 이름으로 보이게 라벨을 단다(`v0.8.2`).
- **잠금 공존 실측** — SPEC §61 인수 기준의 마지막 항목이 2026-08-20 에 닫혀
  **21/21 측정됨**이 됐다. 중첩 Hyprland 격리에서 hyprlock 과 양방향으로 쟀다.
  실측: `docs/RUNTIME_STARTUP.md` §22.

## 라이선스

MIT (`LICENSE`). 업스트림 Omarchy 또한 MIT.
