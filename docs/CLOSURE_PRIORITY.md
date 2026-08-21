# 클로저 예외 우선순위 (2026-08-21 확정)

`tests/data/closure-exceptions.tsv` 잔여 22행의 포기(prioritization) 결정
(원래 31행; v0.10.0 이 가시 UI 9개를 스테이징하며 행을 지웠다). milestone
열은 스캐너가 읽지 않는 사람용 주석이다 — 이 문서가 그 해석의 근거다.

## 기준

① 현재 기본 Quattro UI의 실제 결손인지 ② upstream verbatim으로 가져오기
쉬운지 ③ 시스템/사용자 설정 영향 ④ 새 의존성·보안 부담.

## v0.10.0 — Visible Quattro Completeness (9)

현재 켜져 있는 UI(bar weather/monitor/audio/bluetooth/power 위젯·패널)의
결손을 닫았다: omarchy-battery-status, omarchy-system-stats,
omarchy-audio-input-set-default, omarchy-audio-sink-availability,
omarchy-bluetooth-power, omarchy-bluetooth-device, omarchy-weather-location,
omarchy-weather-status, omarchy-theme-refresh.

프라이버시: weather 짝을 올리면 기본 bar 위젯이 wttr.in 에 실 외부 요청을
보낸다. 저장된 위치는 `omarchy-weather-location --set` 만이
`~/.local/state/omarchy/settings/weather.json`(업스트림 기본 경로)에 쓴다.
파일이 없으면 조회마다 IP 기반으로 도시를 추정하며 그 결과는 기록하지
않는다. 위젯을 끄려면 `~/.config/omarchy/shell.json` bar layout 에서
`omarchy.weather` 를 제거한다. 그 파일을 만들면 딥머지가 없다 — 패키지
기본값이 통째로 무시되고, `cachy-omarchy-doctor` 가 존재 시 WARN 한다
(`docs/RUNTIME_STARTUP.md`, `docs/RC_GAP_INVENTORY.md`).

## v0.11.0 — Session Lifecycle Parity (후보 7)

예외 표 7행 + `omarchy-hyprland-monitor-clamshell`(신규 — 예외 행 없음,
system-wake 체인):

omarchy-brightness-keyboard, omarchy-system-wake,
omarchy-hyprland-monitor-clamshell,
omarchy-hw-laptop-closed, omarchy-launch-screensaver(+별도 클로저),
omarchy-restart-shell(ADAPT — cachy-omarchy-shell --restart 경유 어댑터,
verbatim 금지), omarchy-launch-floating-terminal-with-presentation(+gum
프레젠테이션 레이어), omarchy-bar-text-color(ImageMagick optdep 선행).

선행 의사결정: xdg-terminal-exec(AUR-only) — AUR optdepend 사용자 책임으로
둘지, 안전한 fallback adapter를 둘지 v0.11 착수 전에 정한다.

## 이후

- P2 선택 기능: network-password+network-qr(자격증명 노출 실측 선행),
  network-speedtest·disk-speedtest(외부 트래픽/디스크 쓰기),
  tailscale-send.
- P3: display-text-size+font-set(앱 설정 takeover 경계 먼저),
  agent+default-agent, voxtype-status+voxtype-config(선행: omarchy-cmd-missing
  스테이징 — 없으면 status 가드가 127이라 바 위젯 프로세스가 죽는다).
- HOLD: hyprland-session-locked(blocked — 해제 조건은 예외 행 사유 참조),
  omarchy·channel-current·update(never — 진입점·패키지/채널 경계).
