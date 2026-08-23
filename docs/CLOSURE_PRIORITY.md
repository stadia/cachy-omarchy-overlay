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

## v0.12.0 — Presentation & Runtime Polish (출하 완료, 2026-08-23)

네 갈래로 묶어 계획했고, 넷 다 그대로 출하됐다. A 는 v0.11 출고 직후 이미
닫혀 있었다.

**A. correctness — newline-safe Hypr toggle sweep** ✅ 완료(`12bb343`, main 에서)
`overlay/hypr/bindings.lua` 의 sweep 이 `find | sort` 를 줄 단위로 읽어, 파일명에
개행이 들어가면 경로가 잘려 그 toggle 이 조용히 로드되지 않았다. `-print0` + NUL
분리 + `table.sort` 로 교체했다. 위험도는 낮았다 — `pcall` 이 설정 전체를 지키고
omarchy 헬퍼는 고정된 이름만 쓴다 — 그래서 v0.12 로 넘겼으나 착수 비용이 낮아
먼저 닫았다.

**B. visual parity — omarchy-bar-text-color** ✅ 완료(`0faaf0b`)
125줄 verbatim + `imagemagick` optdepend 선언. 배경 이미지에서 바 텍스트 대비색을
계산한다. `magick` 은 `tests/data/command-packages.tsv` 에, 클로저는
`docs/RUNTIME_DEPENDENCIES.md` 에 반영했다. 새 외부 의존 하나뿐이라
자체완결적이었다 — 계획과 실제 출하가 정확히 일치한다.

**C. safe shell lifecycle** ✅ 완료(`638b659`, `ade0fa4`, `7237394`)
- `638b659` — `cachy-omarchy-shell --restart` 가 락 인지: 세션이 secure/locking
  이거나 응답한 셸의 회신을 파싱할 수 없으면 거부한다(exit 1, 영어 stderr
  `Refusing to restart the shell while the session is locked.`). 명확히 언락
  상태이거나 IPC 가 아예 실패하면 진행한다.
- `ade0fa4` — `cachy-omarchy-reload` 를 7번째 공개 명령으로 추가. `--restart`
  위의 얇은 앞단.
- `7237394` — `overlay/compat/bin/omarchy-restart-shell` 을
  `cachy-omarchy-reload` 로 위임하도록 재작성. compat 적응 카피는 이제 6개다.

verbatim 은 처음부터 금지였다 — 업스트림 원본은 quickshell 을 kill·재기동하며
세션 락 상태를 폴링해 재확보한다. 계획대로 어댑터로 감쌌다.

**※ stranded-lock recovery 는 계획대로 범위 밖에 남겨뒀다.**
`omarchy-hyprland-session-locked` 는 여전히 `milestone=blocked` 다. 스테이징하면
hyprlock 이 세션을 쥔 상태에서 ext-session-lock 거부로 quickshell 이 죽는다는
실측(`docs/RUNTIME_STARTUP.md` §22.4)이 그대로 유효하고, 이번 마일스톤에서 그
실측을 재확인하거나 뒤집는 작업은 하지 않았다. 락 인지 재시작 어댑터는 그
헬퍼 없이 성립하므로 경계를 그대로 유지한다.

**D. presentation layer** ✅ 완료(`c7c8820`)
- `omarchy-launch-floating-terminal-with-presentation`
- `omarchy-restart-gum`
- `omarchy-show-logo`
- `omarchy-show-done`
- `logo.txt`

얇은 앞단이 아니라 gum 테마 프레젠테이션 레이어 전체가 진짜 작업이었다. `clear`
(ncurses, BASE) 를 새로 매핑했다. 알려졌던 실제 결손 셋을 닫았다 — 메뉴
`update.hardware.audio`, `setup.security.passwordless-sudo`,
`setup.network.dns.custom` 세 행이 이 런처 부재로 실패하던 것이 이제 실행된다.

**결산.** 네 갈래 다 `closure-exceptions.tsv` 의 기존 예외 행을 지우는 것으로
끝났다 — 이번 마일스톤에서 새로 등록한 backlog 예외 행은 없다. 유일하게 계속
열어두기로 한 것은 stranded-lock recovery 이고, 그건 애초에 예외 행이 아니라
`milestone=blocked` 로 표시된 별도 결정이다.

## 이후 — v0.12.0 이후 backlog

경계는 기준 ① 에 있다. v0.9~v0.12 는 전부 "현재 Quattro desktop 의 결손을
닫는다" 였다. v0.12.0 을 끝으로 그 범주의 알려진 결손은 남아 있지 않다 —
아래 항목들은 "새 기능 표면을 채택한다" 로 성격이 다르다. 없어서 무언가
깨진 것이 아니라, 지금 없는 능력을 새로 들이는 일이다. 채택 여부는 그
자체로 결정할 문제이지 마일스톤에 얹을 일이 아니다.

- P2 선택 기능: network-password+network-qr(자격증명 노출 실측 선행),
  network-speedtest·disk-speedtest(외부 트래픽/디스크 쓰기),
  tailscale-send.
- P3: display-text-size+font-set(앱 설정 takeover 경계 먼저),
  agent+default-agent, voxtype-status+voxtype-config(v0.11.0 에서
  omarchy-cmd-missing 이 스테이징돼 예전의 127 가드 붕괴 우려는 해소됐다 —
  남은 유일한 이유는 voxtype 딕테이션 기능 자체의 채택 여부 미정).
- HOLD: hyprland-session-locked(blocked — 해제 조건은 §22.4 실측을 뒤집는 새
  증거뿐이다. v0.12.0 은 그 실측을 재확인·재측정하지 않고 그대로 상속했다),
  omarchy·channel-current·update(never — 진입점·패키지/채널 경계).
