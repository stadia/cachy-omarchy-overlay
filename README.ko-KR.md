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
| `cachy-omarchy-shell` | 4.0.1-1 | 핀된 Omarchy Quattro 셸 런타임 (Quickshell 트리, `omarchy-settings` 제외) |
| `cachy-omarchy-overlay` | 1.0.1-1 | CachyOS 통합 계층 (래퍼 명령, Hyprland 바인딩, 기본값) |

업스트림 핀은 `upstream.lock`이 관리한다 (현재 `basecamp/omarchy @ v4.0.0`,
`f0020448`).

설치되는 공개 명령 8개 (`/usr/bin`):

- `cachy-omarchy-shell` — 셸 기동(`--run`)·IPC(`--ipc`)·수동 재기동(`--restart`)
- `cachy-omarchy-launcher` — 런처 토글 (SUPER + SPACE)
- `cachy-omarchy-keybindings` — 키바인딩 뷰어 토글 (SUPER + K)
- `cachy-omarchy-bindings` — 사용자 Hyprland 설정에 관리 source 블록 주입/제거
- `cachy-omarchy-init` — 최초 1회 사용자 설정 생성 (기존 파일 덮어쓰지 않음)
- `cachy-omarchy-doctor` — 읽기 전용 진단 (테마 상태 포함)
- `cachy-omarchy-reload` — `cachy-omarchy-shell --restart` 의 락 인지 앞단
- `omarchy-theme-set` — 감사된 업스트림 helper 집합으로 테마 적용

## 세션 요구사항

로그인할 때 **Hyprland (uwsm-managed)** 를 선택해야 한다. 두 패키지는 공식
`omarchy` 패키지와 같은 `/usr/bin/omarchy-*` 이름을 소유하므로 서로 충돌한다.

## 테마

업스트림 테마 파이프라인을 그대로 쓴다. 첫 `cachy-omarchy-init` 이 테마가
없을 때만 "Tokyo Night" 를 시드한다.

```bash
omarchy-theme-set "Nord"     # 전환 — 셸 재시작 없이 바·메뉴에 반영
```

또는 런처 메뉴의 `Style > Theme`. 테마 상태는 업스트림과 같은
`~/.local/state/omarchy/current/theme/` 에 있고, 사용자 오버레이
(`~/.config/omarchy/themes/<name>/`)가 패키지 테마 위에 합쳐진다.

## 유틸리티 플러그인

업스트림 first-party 플러그인 다섯 개 — clipboard·emojis·image-picker·
reminders·OSD — 는 업스트림 규칙상 기본 로드된다. 그 QML 이 부르는
helper 와 런타임 의존성(`jq`, `wl-clipboard`, `wtype`, `wireplumber`,
`pipewire-pulse`, `xdg-utils`)을 패키지가 함께 닫는다.

- **Clipboard** — 메뉴의 clipboard 항목 또는 `omarchy.clipboard` 토글. 히스토리는
  업스트림과 같은 `~/.local/state/omarchy/clipboard-history.json` (최대 300개,
  로컬 전용)에 기록되며, 민감한 selection(비밀번호 관리자 hint 등)은 저장하지
  않는다. `cachy-omarchy-doctor` 가 경로와 항목 수를 읽기 전용으로 보고한다.
  지우는 것은 사용자의 명시 동작뿐이다.
- **Emojis** — 메뉴의 Emoji 항목. 선택한 emoji 를 clipboard 에 넣고 focused 앱에
  한 번 붙여넣는다. 취소는 아무 side effect 도 없다.
- **Image picker** — 테마/배경 선택 등에 쓰이는 업스트림 image-grid
  (`omarchy-menu-images` 경로 그대로).
- **Reminders** — `omarchy-reminder -i`/메뉴에서 설정. user systemd 타이머
  (`omarchy-reminder-*.timer`)와 `${XDG_RUNTIME_DIR:-/tmp}/omarchy-reminders/`
  메타데이터만 사용한다 — system 유닛·`/etc`·root 없음.
- **OSD** — 볼륨/마이크 뮤트 helper 와 `omarchy-osd` 가 upstream `omarchy.osd`
  패널을 띄운다. 감사된 helper 는 `/usr/bin/omarchy-*`로 노출되며, 올바르게
  동작하려면 그래픽 uwsm 세션이 공급하는 `OMARCHY_PATH`가 필요하다. XF86 미디어 키 바인딩은 주입하지 않는다 — 도달 경로는
  명시적 CLI/메뉴뿐이다 (화면 밝기 체인은 범위 밖).

## Weather 위젯

바 weather 위젯과 패널은 **wttr.in**(IP 도시 조회·현재 날씨)과
**Open-Meteo**(`api.open-meteo.com` 예보, `geocoding-api.open-meteo.com` 도시
검색)에 실 외부 요청을 보낸다. 저장된 위치는 `omarchy-weather-location --set`
만이 `~/.local/state/omarchy/settings/weather.json`(업스트림 기본 경로)에 쓴다.
파일이 없으면 조회마다 IP 기반으로 도시를 추정하며 그 결과는 기록하지
않는다. 위젯을 끄려면 `~/.config/omarchy/shell.json` bar layout 에서
`omarchy.weather` 를 제거한다. 그 파일을 만들면 딥머지가 없다 — 패키지
기본값이 통째로 무시되고, `cachy-omarchy-doctor` 가 존재 시 WARN 한다
(`docs/RUNTIME_STARTUP.md`, `docs/RC_GAP_INVENTORY.md`).

### 지원 범위

**Lua toggle 파일은 hyprland.lua 설정에서만 적용된다.** `hyprland.conf` 를
쓰는 경우 설치·셸·런처·테마는 정상 동작하지만 그 Lua toggle 파일은 적용되지
않습니다 — `.conf` 는 Lua 파일을 실행하지 않기 때문입니다. 이는 노트북 뚜껑
동작을 지원한다는 뜻이 아닙니다. 이 오버레이는 upstream lid-switch 바인딩을
스테이징하지 않습니다. 자세한 내용은 SPEC 의 "지원 계약" 절을 참고하세요.

## 세션 생명주기

idle → screensaver → lock → wake 체인이 패키징돼 있다: idle 타임아웃은 키보드
백라이트를 끄고(`off`) 화면을 잠그며, 명시적 lock 요청은 터미널
스크린세이버를 띄우고, 깨어날 때 키보드 백라이트를 복원한다(`restore`). 이
제품에는 노트북 뚜껑 트리거가 없다 — 업스트림 뚜껑 스위치 바인딩
(`default/hypr/bindings/utilities.lua`)은 전혀 스테이징되지 않으므로, 이
빌드에서는 뚜껑을 닫아도 `omarchy-hyprland-monitor-clamshell`이 불리지
않는다. 이 헬퍼는 여전히 출하되고 여전히 닿기는 하지만, idle/lock 체인이
이미 부르는 `omarchy-system-wake` 경로를 통한 간접 도달일 뿐이다. 마찬가지로
`omarchy-brightness-keyboard`도 `off`/`restore`만 실제로 연결돼 있고,
`up`/`down`/`cycle`은 이 오버레이가 스테이징하지 않는 업스트림 미디어 키
(XF86Kbd*) 바인딩 전용이다.

선택: idle 스크린세이버는 `ttfx`(AUR), 다중 모니터 배치는 `socat` 이 있어야
한다. 없으면 스크린세이버만 조용히 뜨지 않으며 다른 기능에는 영향이 없다. 이
체인이 쓰는 clamshell/toggle seam 은 `hyprland.lua` 설정에서만 동작한다 —
`hyprland.conf` 사용자는 toggle 파일이 있으면 `cachy-omarchy-doctor` 가
WARN 한다(`docs/RUNTIME_STARTUP.md` 참고).

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

## 알려진 한계

`xdg-terminal-exec` 는 여전히 AUR 전용 optdepend — fallback 어댑터는 만들지
않는다. 크래시한 `hyprlock` 이 stranded 시킨 잠금을 복구하는 것은 범위 밖이다
(`docs/RUNTIME_STARTUP.md` §22.4). 릴리스 이력은 git 태그(`v0.1.2`부터
`v1.0.1`까지)에 있다.

## 라이선스

MIT (`LICENSE`). 업스트림 Omarchy 또한 MIT.
