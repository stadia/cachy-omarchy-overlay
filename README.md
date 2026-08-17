# Cachy Omarchy Overlay

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
| `cachy-omarchy-shell` | 4.0.0-2 | 핀된 Omarchy Quattro 셸 런타임 (Quickshell 트리, `omarchy-settings` 제외) |
| `cachy-omarchy-overlay` | 0.1.1-1 | CachyOS 통합 계층 (래퍼 명령, Hyprland 바인딩, 기본값) |

업스트림 핀은 `upstream.lock`이 관리한다 (현재 `basecamp/omarchy @ v4.0.0`,
`f0020448`).

설치되는 공개 명령 5개 (`/usr/bin`):

- `cachy-omarchy-shell` — 셸 기동(`--run`)·IPC(`--ipc`)·수동 재기동(`--restart`)
- `cachy-omarchy-launcher` — 런처 토글 (SUPER + SPACE)
- `cachy-omarchy-keybindings` — 키바인딩 뷰어 토글 (SUPER + K)
- `cachy-omarchy-bindings` — 사용자 Hyprland 설정에 관리 source 블록 주입/제거
- `cachy-omarchy-init` — 최초 1회 사용자 설정 생성 (기존 파일 덮어쓰지 않음)

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
- `docs/superpowers/plans/` — 마일스톤 설계·구현 문서.
  **먼저 `docs/superpowers/plans/INDEX.md`를 읽을 것** — 완료된 플랜에 남아 있는,
  이후 실측이 뒤집은 주장들을 모아뒀다.

## 로드맵

- **v0.1** — 런타임 패키징 + 런처 + 키바인딩 + 업데이트/재빌드. 완료.
- **v0.2 (Milestone 8)** — `omarchy.bar` 채택. 완료(`v0.2.0`). 업스트림 바를
  켠 채로 출고한다. Waybar를 대체하지는 않는다 — 둘을 함께 띄우면 겹치지 않고
  쌓이며(세로 예약 `36 → 62px`), 우리는 Waybar를 중지·제거하지 않는다.
- **v0.3 (Milestone 9)** — 업스트림 테마 런타임 채택. 진행 중
  (`docs/superpowers/plans/2026-08-17-m9-theme-runtime-design.md`).

## 라이선스

MIT (`LICENSE`). 업스트림 Omarchy 또한 MIT.
