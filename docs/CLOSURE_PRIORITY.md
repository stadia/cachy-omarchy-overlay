# 클로저 예외 우선순위 (2026-08-21 확정)

`tests/data/closure-exceptions.tsv` 잔여 18행의 포기(prioritization) 결정
(원래 31행; v0.10.0 이 가시 UI 9개를 스테이징하며 9행을, v0.11.0 이 session
lifecycle 9개를 스테이징하며 그중 예외 행이 있던 4행을 마저 지웠다 — 나머지
5개는 애초에 예외 행 자체가 없었다). milestone 열은 스캐너가 읽지 않는
사람용 주석이다 — 이 문서가 그 해석의 근거다.

## 기준

① 현재 기본 Quattro UI의 실제 결손인지 ② upstream verbatim으로 가져오기
쉬운지 ③ 시스템/사용자 설정 영향 ④ 새 의존성·보안 부담.

## v0.10.0 — Visible Quattro Completeness (9)

현재 켜져 있는 UI(bar weather/monitor/audio/bluetooth/power 위젯·패널)의
결손을 닫았다: omarchy-battery-status, omarchy-system-stats,
omarchy-audio-input-set-default, omarchy-audio-sink-availability,
omarchy-bluetooth-power, omarchy-bluetooth-device, omarchy-weather-location,
omarchy-weather-status, omarchy-theme-refresh.

프라이버시: weather 짝을 올리면 기본 bar 위젯·패널이 **wttr.in**(IP 도시
조회·현재 날씨)과 **Open-Meteo**(예보 `api.open-meteo.com`, 지오코딩
`geocoding-api.open-meteo.com`)에 실 외부 요청을 보낸다. 저장된 위치는
`omarchy-weather-location --set` 만이
`~/.local/state/omarchy/settings/weather.json`(업스트림 기본 경로)에 쓴다.
파일이 없으면 조회마다 IP 기반으로 도시를 추정하며 그 결과는 기록하지
않는다. 위젯을 끄려면 `~/.config/omarchy/shell.json` bar layout 에서
`omarchy.weather` 를 제거한다. 그 파일을 만들면 딥머지가 없다 — 패키지
기본값이 통째로 무시되고, `cachy-omarchy-doctor` 가 존재 시 WARN 한다
(`docs/RUNTIME_STARTUP.md`, `docs/RC_GAP_INVENTORY.md`).

## v0.11.0 — Session Lifecycle Parity (출하 9)

`idle → screensaver → lock → wake` 체인을 닫았다. 계획 당시 후보는 7이었으나
클로저를 열어보니 **예외 표에 행조차 없던 미스테이징 4개**가 체인 안에 있었다
— 실제 출하 집합은 9다:

omarchy-cmd-missing, omarchy-hw-laptop-closed, omarchy-hw-external-monitors,
omarchy-hw-clamshell, omarchy-brightness-keyboard,
omarchy-hyprland-monitor-clamshell, omarchy-system-wake, omarchy-screensaver,
omarchy-launch-screensaver. 터미널 screensaver 설정 3개도 함께 올렸다.

seam: clamshell 은 `~/.local/state/omarchy/toggles/hypr/*.lua` 를 쓰고
`hyprctl reload` 하는데 우리 hypr 설정에 그것을 읽는 쪽이 없었다. verbatim
그대로 올리면 dead file 만 남으므로, `overlay/hypr/bindings.lua` 에 정렬된
`pcall(dofile)` sweep 블록을 놓아 seam 을 열었다(설계 §4,
`docs/RUNTIME_STARTUP.md` §23). 같은 seam 이
`omarchy-hyprland-monitor-internal(-mirror)` 의 막힘 사유도 해소했다. conf
사용자(`hyprland.conf`) 는 이 seam 을 타지 못한다 — `.conf` 의
`source = <dir>/*.lua` 는 파싱 에러 없이 통과하지만 Hyprland conf 파서가 그
Lua 를 실행하지 않는다(`docs/RUNTIME_STARTUP.md` §23 실측). 그래서 seam 은
lua-config 전용이며, `cachy-omarchy-doctor` 가 conf 사용자 중 toggle 파일
보유자를 WARN 한다.

의존: 계획 당시 예상은 `socat`/`ttfx`/`tty` 셋이었다. 실제로 열어보니
`closure_check.py` 가 네 번째 `UNMAPPED_COMMAND stty` 를 잡아냈다 —
`omarchy-screensaver` 의 `wait_for_terminal_resize()` 가 `stty size` 를
폴링한다. 이 넷째는 계획이 아니라 클로저 스캐너가 찾았다. `socat`(extra,
OPT) 과 `ttfx`(AUR — 리포 무결과) 를 optdepends 로 선언했고, `stty`/`tty`
는 coreutils(BASE) 라 새 optdepend 가 아니다. `xdg-terminal-exec` 는
선례대로 AUR optdepend 를 유지한다(fallback 어댑터를 만들지 않는다 — 만들면
이미 출하된 omarchy-launch-tui 와 동작이 갈린다).

## v0.12.0 — 후보 3

omarchy-bar-text-color(ImageMagick optdep 선행),
omarchy-restart-shell(ADAPT — `cachy-omarchy-reload` 어댑터, verbatim 금지),
omarchy-launch-floating-terminal-with-presentation(+gum 프레젠테이션 레이어
`omarchy-restart-gum`/`-show-logo`/`-show-done`).

## 이후

- P2 선택 기능: network-password+network-qr(자격증명 노출 실측 선행),
  network-speedtest·disk-speedtest(외부 트래픽/디스크 쓰기),
  tailscale-send.
- P3: display-text-size+font-set(앱 설정 takeover 경계 먼저),
  agent+default-agent, voxtype-status+voxtype-config(v0.11.0 에서
  omarchy-cmd-missing 이 스테이징돼 예전의 127 가드 붕괴 우려는 해소됐다 —
  남은 유일한 이유는 voxtype 딕테이션 기능 자체의 채택 여부 미정).
- HOLD: hyprland-session-locked(blocked — 해제 조건은 예외 행 사유 참조),
  omarchy·channel-current·update(never — 진입점·패키지/채널 경계).
