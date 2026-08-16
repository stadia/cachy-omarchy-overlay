# cachy-omarchy-overlay

기존 CachyOS + Hyprland 위에 Quickshell 기반 Quattro 런처를 올리는 **데스크톱 오버레이**입니다. Omarchy 전체를 설치하는 프로그램이 아닙니다.

기존 설정, 바, 알림, 잠금 화면, 셸은 건드리지 않습니다.

## 키바인딩

```text
SUPER + SPACE  → Quattro 스타일 런처 / 메뉴
SUPER + K      → 검색 가능한 키바인딩 치트시트
```

## 상태

**Milestone 0 · Milestone 1 완료** (pre-v0.1)

- Milestone 0: Quattro 메뉴 의존성 맵 (`docs/QUATTRO_PORT_MAP.md`)
- Milestone 1: 장기 Quickshell 호스트, IPC 테스트 서피스, `coo-shell` CLI, systemd 유저 서비스

런처 UI·앱 검색·키바인딩 뷰어·설치 스크립트는 이후 마일스톤입니다.

## 개발

```bash
# 격리된 설정 루트로 호스트만 띄우기
./dev/run-shell.sh

# IPC (개발 중에는 셸 경로를 명시)
export COO_SHELL_PATH="$PWD/shell"
./bin/coo-shell ping
./bin/coo-shell test open   # 테스트 패널
./bin/coo-shell test close

# 전체 테스트
./tests/test.sh
```

systemd 유저 서비스(개발용으로 레포의 `bin/coo-shell-daemon`을 가리킬 수 있음):

```bash
systemctl --user status coo-shell.service
systemctl --user disable --now coo-shell.service   # 되돌리기
```

## 더 보기

- 전체 명세: [`SPEC.md`](SPEC.md)
- Quattro 포트 맵: [`docs/QUATTRO_PORT_MAP.md`](docs/QUATTRO_PORT_MAP.md)
- Hyprland 연동: [`docs/HYPRLAND_INTEGRATION.md`](docs/HYPRLAND_INTEGRATION.md)
- Quickshell CLI 실측: [`docs/QUICKSHELL_API.md`](docs/QUICKSHELL_API.md)
- 구현 플랜: [`docs/superpowers/plans/2026-08-15-coo-m0-m1.md`](docs/superpowers/plans/2026-08-15-coo-m0-m1.md)
