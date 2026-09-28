# Quattro 셸 기동 계약

> Milestone 2 기동 계약 + Milestone 3 런처 실측. 패키징된 업스트림 Omarchy
> Quattro 셸을 CachyOS에서 기동·토글하기 위해 **실측으로 확정한** 계약.
> 측정한 것과 추론한 것을 구분해 적는다.
>
> 스펙: `SPEC.md` (Spec 1.0) §13–§17·§19·§20·§42.3·§43–§45·§48(R01–R06)·§55·§56.
> 측정 당시 핀: Omarchy 4.0.0 @ `f0020448ca87329199de7cb12f2015ebc4a3e5e7`. 현재 핀은 `upstream.lock`.
>
> §3 과 §7–§19(마일스톤별 실측 로그)는 지웠다. 다른 문서가 인용하는 그 절들은
> 태그 `v1.0.2` 시점 이 파일에 그대로 있다: `git show v1.0.2:docs/RUNTIME_STARTUP.md`.
> 남은 절은 번호를 바꾸지 않았다.

---

## 1. 기동 명령

확정된 `--run` 의 정확한 명령(`overlay/bin/cachy-omarchy-shell`):

```bash
export OMARCHY_PATH=/usr/share/cachy-omarchy/upstream
export QT_QPA_PLATFORM=wayland
# PATH 는 어느 레이어도 건드리지 않는다 (§45 개정). 위젯이 bare name 으로 부르는
# helper 는 /usr/bin/omarchy-* 상대 심링크로 노출된다.

exec env QS_DISABLE_FILE_WATCHER=1 QS_NO_RELOAD_POPUP=1 \
  systemd-cat -t cachy-omarchy-shell -- \
  quickshell -n -p "$OMARCHY_PATH/shell"
```

각 환경변수의 이유:

| 변수 | 값 | 이유 |
| --- | --- | --- |
| `OMARCHY_PATH` | `/usr/share/cachy-omarchy/upstream` | `shell/shell.qml:27` 가 `Quickshell.env("OMARCHY_PATH")` 로 자산을 찾는다. uwsm 세션 환경(`/usr/share/uwsm/env-hyprland.d/10-cachy-omarchy`)이 공급하고, 래퍼가 같은 값을 기본으로 설정한다. 어느 쪽도 없으면 IPC·기동이 모두 실패한다. |
| `QT_QPA_PLATFORM` | `wayland` | xcb 폴백 차단(방어적). Hyprland autostart(`hyprland.start`)로 기동하면 `WAYLAND_DISPLAY` 가 컴포지터 env 로 항상 정상이라 별도 socket-wait 는 없다. |
| `QS_DISABLE_FILE_WATCHER` | `1` | **필수.** pacman 이 `$OMARCHY_PATH/shell` 을 다시 쓰는 도중 Quickshell 파일 워처가 리로드를 걸면 반쯤 쓰인 트리를 읽고, 실패한 리로드가 두 번째 엔진 세대를 남겨 다음 재시작의 IPC kill 을 크래시로 만든다. 업스트림 `bin/omarchy-launch-shell` 이 같은 이유로 끈다. 우리는 pacman 배포이므로 그대로 해당. |
| `QS_NO_RELOAD_POPUP` | `1` | 업스트림 기동 명령이 함께 끄는 팝업. 기동 경로에 영향은 없지만 업스트림 동작을 그대로 따른다(§55). |

`systemd-cat -t cachy-omarchy-shell` 은 Quickshell 의 stdout/stderr 를 저널로 보낸다. **래퍼의 stdout 리다이렉트는 정상이라면 항상 비어 있다.** 기동 로그는 저널을 태그로 읽어야 한다:

```bash
journalctl --user -t cachy-omarchy-shell
```

> **측정**: 이 명령으로 띄운 셸은 IPC `shell ping` 에 `ok` 로 응답한다(2회차, 약 0.5s).
> 저널에 `Configuration Loaded` 가 한 줄 잡힌다. QML 오류·ERROR 레벨 없음.
> 호환 작업(추가 env·compat shim·래퍼 변경·패치)은 **0** 이었다 — 업스트림이 그대로 기동한다(§6.1 최상 결과).

---

## 2. 설정 해석

`shell/shell.qml` 의 `applyShellConfig()` (line 71~87) 는 **3단계를 순서대로** 시도하고,
**딥머지하지 않는다.**

```text
1. userConfigPath  = ~/.config/omarchy/shell.json
2. defaultsPath    = $OMARCHY_PATH/config/omarchy/shell.json
3. builtinShellConfig (셸 자체 내장)
```

규칙:

- `version: 1` 을 가진 유효한 사용자 파일이 `userConfigPath` 에 있으면 **기본값을 통째로 대체**한다. (일부 키만 덮어쓰기 불가.)
- 없으면 `defaultsPath` 를 읽는다. `stage-upstream.sh` 는 이 자리에 정본 `overlay/defaults/shell.json` 을 설치한다. **v0.2.0 부터 그 정본의 내용은 핀 커밋 업스트림 파일과 바이트 동일하다** — 우리 값을 넣기 위해서가 아니라, 리베이스로 업스트림 기본값이 바뀌면 `tests/runtime/test_shell_config.sh` 의 핀 커밋 대조가 잡게 하려고 우리 경로를 거친다.
- 그것도 실패하면 `builtinShellConfig`.

### 알려진 한계 — 사용자 `~/.config/omarchy/shell.json` 오버라이드

사용자가 `~/.config/omarchy/shell.json` 을 만들면, 딥머지가 없으므로 **우리 기본값이 통째로 무시된다.** 그 파일에 `disabledPlugins` 가 없으면 §3의 비활성 집합이 풀려 바·알림·락이 돌아온다.

**우리는 `~/.config/omarchy/shell.json` 을 쓰지 않는다** (감사 지침, §6.6). 대응:

- 감지해 경로에 경고를 인쇄하는 것은 M7 `cachy-omarchy-doctor` 후보 항목이다.
- 이 한계는 패키지 기본값의 안전성이 사용자 파일 하나에 의해 우회될 수 있음을 의미한다.

> **측정 vs 추론**: 3단계 해석 순서와 "딥머지 없음"은 핀 커밋 소스(`shell.qml:71~87`)에서
> 확인한 사실이다. 사용자 파일이 우리 기본값을 무시한다는 것은 소스에서 직접 읽은
> 동작이고, 본 테스트(샌드박스 HOME)에서는 사용자 파일이 없어 발현하지 않았다.

---

## 4. compat 확정 목록

Task 5 라이브 기동에서 **실제로 필요했던** `omarchy-*` compat shim: **없음.**

근거:

- `shell.qml` · `AppLibrary.qml` · `PluginRegistry.qml` 이 참조하는
  `omarchy-shell` 문자열은 **기동 경로에서 실제로 호출되지 않았다** (기동 로그에
  `omarchy-shell` 미발견 관련 WARN/오류 없음, IPC ping 응답 정상).
- 업스트림이 `omarchy-toggle-bar` 를 부르는 경로는 본 테스트에서 `bar-off` 파일을
  직접 만들어 우회했으므로, 그 shim 이 기동에 필요했는지는 **미확인** (M3 메뉴
  토글에서 재측정).

**기동 경로**의 `omarchy-*` shim 은 여전히 없다. `overlay/compat/bin/` 에 넣는 것은
로그/소스가 요구한 명령만이다(§44).

**M3 앱 실행 경로**에서 `AppLibrary.launch` 가 `uwsm-app -- gtk-launch` 를 부른다.
M3 당시에는 이 호스트에 `uwsm-app` 이 없어 `overlay/compat/bin/uwsm-app` WRAPPER 를
추가했었으나(`exec "$@"` 만, gtk-launch 재구현 아님), **그 shim 은 삭제됐다.**
현재 계약: uwsm-app 은 uwsm 패키지가 소유하는 실제 바이너리이고,
`cachy-omarchy-shell` 이 `uwsm` 을 hard depends 로 끌어온다 — 우리 두 패키지
어느 쪽도 `uwsm-app` 을 소유하지 않는다. shim 을 뺀 이유는, uwsm 이 필수 의존이
된 이상 shim 은 실제 바이너리를 가리기만 하기 때문이다(§15.2 에서 실측된 결함).
어느 레이어도 PATH 를 조작하지 않는다(§45 개정). 기동 자체는 `uwsm-app` 없이 통과한다.

> **측정**: 기동에 `omarchy-*` shim 불필요. 메뉴 앱 실행의 `uwsm-app` 은 uwsm
> 패키지의 실제 바이너리가 담당한다. shim 시절의 M3 측정·수정 경위는 §13.3·§15 의
> 역사 기록을 본다.

---

## 5. IPC 계약

```bash
timeout --kill-after=1s "${COO_IPC_TIMEOUT:-2s}" \
  qs ipc -n -p "$OMARCHY_PATH/shell" call -- <target> <method> [args...]
```

- 메뉴 토글(M3): `qs ipc ... call -- shell toggle omarchy.menu '{"menu":"root"}'`
- 상태 조회: `call -- shell listPlugins`, `call -- shell listShellConfig`
- 건강 검사: `call -- shell ping` → `ok`

### 함정 — IPC 레벨 오류는 stdout + exit 0 으로 온다

`qs ipc` 는 대상/함수가 없을 때 stderr 가 아닌 **stdout 에 오류 문자열을 실어 exit 0**
으로 반환한다. 그대로 통과시키면 실패가 성공처럼 보인다. 래퍼 `cmd_ipc` 가 알려진 오류
문자열을 `case` 로 잡아 exit 1 로 바꾼다:

```bash
case $output in
  "Target not found."|"Function not found."|"Too few arguments provided"*|"Too many arguments provided"*)
    fail "$output" ;;
esac
```

> **측정 (M3 Task 1)**: 실행 중인 추출 트리에서 원본 `qs ipc` 는
> `Target not found.` / `Function not found.` 를 **stdout + exit 0** 으로 낸다.
> 마침표 포함, 래퍼 `case` 와 바이트 일치. `cachy-omarchy-shell` 은 둘 다 exit 1
> 로 승격한다. 래퍼 수정 없음.

### 타임아웃 분류

| exit | 의미 | 래퍼 동작 |
| --- | --- | --- |
| `124` / `137` | `timeout` 초과 — 셸이 응답하지 않음 | exit 1 "셸이 응답하지 않는다" |
| `!= 0` (그 외) | `qs ipc` 자체 실패 — 셸이 실행 중이 아님 | exit 1 "셸이 실행 중이 아니다" |
| `0` | IPC 도달 성공 (위 함정 case 처리 후) | stdout 출력 |

---

## 6. 알려진 한계 (미해결)

1. **바 억제 미충족 (§4.3) — 폐기됨 (M2 기록).** 전제가 v0.2.0 에서 뒤집혔다. 이제
   업스트림 바를 켠 채 출고하는 것이 기본이고 억제가 opt-out 이다. 그리고 "두 바는 못
   쓴다"는 가정 자체가 실측으로 틀렸다 — waybar 와 `omarchy-bar` 는 layer-shell
   exclusive zone 을 누적해 겹치지 않고 쌓인다(세로 예약 36→62px). §61 "Existing
   Waybar preserved" 는 §17.6 에서 충족됐다.

2. **`inotify-tools` 미감사 의존성** — `services/PluginRegistry.qml:638` 의
   `localPluginWatcher` 가 `inotifywait` 로 `~/.config/omarchy/plugins` 를 감시한다.
   이 호스트에 `inotify-tools` 가 없어 **1초마다 WARN 이 반복**된다(`onExited` →
   1초 재시작 타이머). 기능은 정상(37개 플러그인 등록)이지만 로그 스팸. `PKGBUILD depends`
   에 없고 `RUNTIME_DEPENDENCIES.md` 에도 없었다 — M1 의존성 감사(§28)의 누락.
   → **해소됨.** `inotify-tools` 는 `cachy-omarchy-shell` 의 `depends` 에 들어가 있다
   (2026-08-20 확인). 실제 `pacman -U` 트랜잭션이 이것을 끌어온 기록은 §12.2.

   → **후속 (2026-08-24, v1.0 수용):** 같은 감시자가 이번에는 **종료 쪽에서** 샌다.
   Quickshell 0.3.0 의 `Io.Process` 는 소유자가 사라져도 자식을 죽이지 않으므로,
   셸을 한 번 띄울 때마다 `inotifywait -m -r` 하나가 `systemd --user` 로
   재부모화되어 `select()` 에 영원히 걸린 채 남는다. 감시 대상 디렉터리를 지워도
   풀리지 않는다 — `tests/test.sh` 가 샌드박스를 "죽이고 나서 지우는" 이유와 같은
   사정이다. 회수 여부는 `tests/runtime/test_reload_watcher_reap.sh` 가 추출된
   패키지 트리를 실제로 띄워 런타임에서 판정한다(§9.5 의 `skip:` 정책 적용 —
   게이트는 라이브 런타임과 빌드 아티팩트 두 개뿐이고, 셸을 띄운 뒤로는 어떤
   경로로도 조용히 통과하지 않는다).

3. **셸 자동 기동 누락** — 셸은 Hyprland autostart(`overlay/hypr/bindings.lua`
   의 `hl.on("hyprland.start", …)`)로 기동한다. 업그레이드로 autostart 줄이
   추가됐더라도 live `~/.config/cachy-omarchy/hypr/bindings.lua` 는 `--force`
   없이 갱신되지 않는다. 해결: `cachy-omarchy-bindings --force` 로 정본 새로고침
   후 재로그인(또는 수동 `cachy-omarchy-shell --run`). `hyprctl reload` 만으로는
   `hyprland.start` 가 재발화하지 않으므로 셸이 뜨지 않는 게 정상이다.
   `hyprland.conf` 사용자는 `bindings.conf` 의 `exec-once` 한 줄이 같은 역할을 하며,
   그 줄이 없는 구형 사본은 `cachy-omarchy-doctor` 가 FAIL 로 잡는다.
   참고: `hyprland.start` 트리거의 1회 발화는 **실측됐다** — 재로그인 후 라이브 셸의
   부모가 곧 `Hyprland` 인 것을 확인했다(§16.1). 이 문단의 "아직 실측되지 않았다"는
   그 이전 기록이다. 정적 테스트가 이벤트 이름 존재만 검증한다는 점은 그대로다. 또, 과거에
   구 유닛을 수동으로 `enable` 했던 사용자는 `systemctl --user disable
   cachy-omarchy-shell.service` 로 잔여 `wants/` 심볼릭 링크를 정리해야 한다
   (pacman 은 유닛 파일은 지우지만 symlink 는 남길 수 있다).

4. **사용자 `~/.config/omarchy/shell.json` 오버라이드** — §2. 우리 기본값이 통째로
   무시될 수 있음. **감지·경고는 구현됐다** — `cachy-omarchy-doctor` 가 WARN 으로
   보고한다(이 호스트가 실제로 그 상태). 딥머지가 없다는 한계 자체는 업스트림
   동작이라 그대로 남는다.

5. **`uwsm` 부재 — 해소됨.** M3 시점에는 미설치(실측)라 compat WRAPPER 로
   `gtk-launch` 에 위임했었다. 현재는 `cachy-omarchy-shell` 이 `uwsm` 을 hard
   depends 로 끌어오므로 `/usr/bin/uwsm-app` 은 항상 uwsm 패키지의 실제
   바이너리다. shim 은 삭제됐다 (§4).

6. **패키지 미설치 상태에서만 검증** — 본 M2 검증은 빌드 산출물을 임시 디렉터리에
   추출해 그 트리를 띄운 것으로, `/usr/share/cachy-omarchy/upstream` 에 실제 설치된
   상태는 아니다. 실설치 경로 검증은 M5.

7. **IPC 오류 문자열** — §5. M3 에서 `Target not found.` / `Function not found.`
   실측 완료. 미실측이 아님.

---

## 20. 세션 환경 — uwsm 드롭인 + `/usr/bin` 심링크 뷰 (2026-08-19)

계약: `OMARCHY_PATH` 는 overlay 소유 uwsm 드롭인
`/usr/share/uwsm/env-hyprland.d/10-cachy-omarchy` 가 그래픽 세션에 공급한다.
업스트림 helper 55개와 compat 적응 카피 4개는 `/usr/bin/omarchy-*` 상대
심링크로만 노출한다. 어느 레이어도 PATH 를 조작하지 않는다. `uwsm-app` 은
uwsm 패키지 소유 실 바이너리다 (shim 삭제). SPEC §45.

### 20.1 패키지·단위 증거

- `tests/package/test_usr_bin_helpers.sh` — 집합 일치, 서로소, 상대 심링크,
  dangling 없음, 어느 패키지도 `usr/bin/uwsm-app` 을 소유하지 않음.
- `tests/runtime/test_installed_tree.sh` — 심링크 뷰 양방향.
- `tests/runtime/test_shell_path.sh` — 래퍼가 PATH 를 건드리지 않음.
- `tests/runtime/test_init_theme_seed.sh` — 추출 페이로드 init, 격리 PATH
  에서 `omarchy-theme-set` 부재는 exact note.
- `tests/runtime/test_doctor.sh` — 세션 `OMARCHY_PATH` 부재 FAIL, 개별
  `omarchy-theme-set`/`omarchy-shell` 노출.
- `tests/runtime/test_app_scope.sh` — 추출 셸만 기동하고 `--restart` 도 그
  추출 경로 패턴에만 매칭, AppLibrary→real `/usr/bin/uwsm-app`→`app-graphical.slice`.

측정 당시 있었던 doctor 의 `pacman -Qqo` uwsm-app 소유권 검사와
`test_app_scope_safety.sh`(`test_app_scope.sh` 본문 문자열 고정)는 지웠다.
소유권은 위 `test_usr_bin_helpers.sh` 가 패키지 단계에서 막는다.

### 20.2 라이브 실측 (2026-08-19)

`COO_RUN_LIVE=1 ./bin/test-packages` 최종 게이트: 50/50, skip 0
(`/tmp/coo-final-live-gate2.log`). 프로덕션 셸 pid 1168513,
`OMARCHY_PATH=/usr/share/cachy-omarchy/upstream` (세션·프로세스 모두).
`cachy-omarchy-doctor` 전 항목 PASS (exit 0; WARN 1건은 사용자
`~/.config/omarchy/shell.json` 오버라이드 — 의도된 보고). SUPER+SPACE /
SUPER+K 는 사용자가 직접 눌러 둘 다 정상 확인. 메뉴 Style > Theme 목록
표시 후 Escape, 테마는 `tokyo-night` 유지. 레이어는 `omarchy-background`·
`omarchy-bar`. PID-scoped 저널 QML ERROR 0건.

사용자 선택으로 생략: `omarchy-theme-set "Nord"` (테마 변경), 프로덕션 셸
`--restart` 생존. 앱 scope 생존은 추출 셸 경로의 `test_app_scope` 가 실측.

`wtype` 가상 키보드는 이 호스트의 Hyprland 0.56.2 `__lua` 바인드 매칭을
발화시키지 못했다. 레포 라이브 테스트는 IPC 경로를 쓰므로 영향 없음.

## 21. 오디오 전환·밝기·입력 가드 (verbatim)

M10 이 남긴 audio-output-switch / audio-tuning / brightness-display 체인과
메뉴 `when` 가드 `omarchy-hw-touchpad`/`-touchscreen` 을 verbatim 으로
스테이징한다. 래퍼가 필요한 `omarchy-hw-laptop` 과
`omarchy-hyprland-monitor-internal(-mirror)` 는 올리지 않는다 — CachyOS
Hyprland 설정이 `~/.local/state/omarchy/toggles/hypr/` 를 source 하지 않아
가드만 올리면 동작하지 않는 메뉴 행이 드러난다.

패키지는 사용자 `~/.config/pipewire` 와 systemd --user 유닛을 만들지 않는다.
`omarchy-audio-tuning on` 이 `$OMARCHY_PATH/default/audio` 와
`default/systemd/user/omarchy-speaker-tuning.service` 템플릿을 복사한다.
`brightnessctl` / `ddcutil` / `lsp-plugins-lv2` 는 optdepends. XF86 키는
주입하지 않는다 (M10 D6).

단위 증거 (sandbox HOME + fake pactl/wpctl/hyprctl/brightnessctl, 실 세션
무접촉. `omarchy-restart-audio` 와 `audio-tuning on/off` 는 실행하지 않음):

- `tests/package/test_staged_audio_brightness_helpers.sh` — 16개 helper
  verbatim, audio/unit 템플릿, hw-laptop·monitor-internal·crash-watch
  미스테이징.
- `tests/runtime/test_audio_brightness_input_helpers.sh` — switch 순환,
  hw-display sysfs, brightness +5%, touchpad toggle 상태 파일.
- `tests/package/test_forbidden.sh` — brightnessctl/ddcutil 은 depends 가
  아니라 optdepends.

### 21.1 라이브 실측 (2026-08-19 22:54–22:56 KST)

설치본 `cachy-omarchy-shell 4.0.0-10` / overlay `0.7.0-1`. 프로덕션 셸 pid
921196 을 `--restart` 하지 않았다. XF86 주입, `audio-tuning on/off`,
`omarchy-restart-audio`, 밝기 `+5%`, 터치패드 토글은 하지 않았다.

읽기 전용:

- `cachy-omarchy-doctor` exit 0. WARN 1건은 기존 사용자
  `~/.config/omarchy/shell.json` 오버라이드.
- `omarchy-speaker-tuning.service` / `omarchy-crash-watch.service` 둘 다
  user unit `not-found`. 패키지가 user 유닛을 enable 하지 않음.
- `omarchy-audio-tuning status`: Installed no, Matches nothing ships for
  this laptop. `match` exit 1.
- 이 호스트는 데스크톱: `/sys/class/backlight` 비어 `omarchy-hw-display`
  exit 1, `brightnessctl` 부재, 포커스 모니터 `DP-1` LG HDR 4K.
  `omarchy-brightness-display` 조회도 exit 1 (내부 backlight 없음, DDC
  도구 없음).
- `hyprctl devices`: 마우스 2개, touch/tablet 0. `omarchy-hw-touchpad` /
  `-touchscreen` exit 1 — 메뉴 Hardware 행은 `when` 실패로 숨은 채.

격리 인스턴스 (추출 트리 + sandbox HOME + `bar-off`, pid 1209690):

| 항목 | 기대 | 실측 |
| --- | --- | --- |
| IPC ping | `ok` | `ok` |
| OSD | 격리 pid 에 레이어 | `omarchy-osd` xywh 0 0 3072 1728 pid 1209690, 1.5s 후 0개 |
| bar | 주차 | `omarchy-bar` y=-26 (`bar-off`) |
| 정리 | 격리만 종료 | isolated 잔여 없음, 프로덕션 921196 생존 |

라이브 오디오 (원복):

- `omarchy-audio-output-volume lower`: 52%→47%, `pactl set-sink-volume` 로
  52% 복원.
- `omarchy-audio-output-switch` exit 0. sink 1개뿐이라 default 는
  `alsa_output.pci-0000_65_00.6.analog-stereo` 유지. OSD 경로에서 장치
  description 의 비-ASCII 에 대해 `Invalid ASCII character` 가 stderr 로
  보임 (헬퍼 exit 0, 싱크 불변).
- `~/.config/pipewire` 에 speaker-tuning 드롭인 없음.

---

## 22. 잠금 화면 공존 실측 — hyprlock (2026-08-20)

SPEC §61 의 마지막 미검증 항목("An installed lock helper is not removed or
stopped by us")을 닫기 위한 실측. **사용자 세션의 화면을 잠그지 않았다** —
`env -u HYPRLAND_INSTANCE_SIGNATURE` 로 띄운 **중첩 Hyprland** 안에서만
잠금을 걸고 풀었다. 사용자 `~/.config/hypr` 는 읽기만 했고, 중첩 인스턴스는
전용 `XDG_CONFIG_HOME`/`HOME` 샌드박스를 썼다.

환경: Hyprland 0.56.2(중첩, `WAYLAND-1` 1507x1658), hyprlock 0.9.6-2.1,
quickshell 0.3.0, 격리 셸은 `/usr/share/cachy-omarchy/upstream` 사본을
`quickshell -n -p <사본>/shell` 로 기동.

### 22.1 Lane A — 소유·정지·제거 (읽기 전용, 실세션)

| 질문 | 실측 |
| --- | --- |
| hyprlock 은 누가 소유하나 | `hyprlock 0.9.6-2.1` (우리 패키지 아님) |
| 우리 패키지가 hyprlock 경로/`/etc`/시스템 유닛을 소유하나 | 두 아카이브 모두 **0건** |
| 우리 코드가 lock 데몬을 stop/mask/disable/제거하나 | `pkill`/`killall`/`systemctl stop|mask|disable`/`pacman -R` **일치 0건**. 트리 안의 유일한 `kill` 은 `cachy-omarchy-shell --restart` 가 `quickshell -n -p <경로>` 전체 매칭으로 **자기 인스턴스**를 끄는 것 |
| hyprlock 은 데몬인가 | 아니다 — 온디맨드 실행. 정지할 상주 프로세스 자체가 없다 |

부수 관측: **이 호스트에는 `~/.config/hypr/hyprlock.conf` 가 없다.** 설치돼
있지만 설정이 없어 `hyprlock` 은 `Config path error` 로 즉시 종료한다. 아래
D1/D2 는 샌드박스에 테스트 전용 최소 설정을 두고 잰 것이며, 사용자 설정을
만들지 않았다.

### 22.2 D1 — 우리 셸이 떠 있는 상태에서 hyprlock 이 잠글 수 있는가

`omarchy.lock` 은 `keepLoaded` 서비스지만 `WlSessionLock { locked: false }` 로
시작한다. 세션 잠금은 IPC `lock lock` 또는 stranded 복구에서만 잡는다.

| 단계 | 실측 |
| --- | --- |
| hyprlock 전 `solitaryBlockedBy` | `["WINDOWED","CANDIDATE"]` |
| hyprlock 실행 후 | `["LOCK","WINDOWED","CANDIDATE"]`, hyprlock 생존, `PAMPROMPT: Password:` |
| 그동안 우리 셸 | `locked:false, sessionLocked:false, lastEvent:"init"` — 개입 없음, 크래시 없음 |

**→ §61 잠금 항목 충족.** 우리는 hyprlock 을 제거·정지하지 않으며, 셸이 떠
있어도 hyprlock 은 평소대로 세션을 잠근다.

### 22.3 D2 — 우리가 먼저 잠근 뒤 hyprlock (역방향)

IPC `lock lock` → `ok`, `locked:true / sessionLocked:true / secure:true`,
`solitaryBlockedBy` 에 `LOCK`. 그 상태에서 hyprlock 실행:

```text
DEBUG]: Locking session
DEBUG]: onLockFinished called. Seems we got yeeten. Is another lockscreen running?
```

hyprlock 은 **거부당하지만 죽지 않고** 살아 있으며, 우리 잠금은 그대로다.
mako 때와 같은 구조 — 밀어내기가 아니라 **순서**다(§17.4). 다만 방향이
반대일 때의 견고성은 대칭이 아니다(§22.4).

### 22.4 결정적 발견 — 거부당했을 때 quickshell 은 죽는다

`Service.qml` 의 `checkStrandedLock()` 은 `omarchy-hyprland-session-locked` 를
불러 exit 0(=세션 잠김)이고 그 잠금이 우리 것이 아니면 `strandedLock` 으로
판정하고 `recoverStrandedLock()` → `beginLock()` 으로 세션 잠금을 **가져오려
한다**. 업스트림 의도는 "클라이언트가 죽어 고아가 된 failsafe 잠금 회수"다.

hyprlock 이 잠금을 쥔 상태에서 이 경로를 태워봤다(헬퍼를 샌드박스 PATH 에
올려 스테이징된 상태를 흉내):

```text
omarchy lock ... lock-stranded: recovering
omarchy lock ... lock-requested
omarchy lock ... secure=false
omarchy lock ... session-locked=false
wl_display#1: error 0: invalid object 70
WARN: The Wayland connection experienced a fatal error
→ 셸 프로세스 사망
```

즉 **ext-session-lock 거부의 결과가 두 클라이언트에서 다르다.** hyprlock 은
`onLockFinished` 로 우아하게 처리하고 생존, quickshell 은 프로토콜 오류로
연결이 끊겨 죽는다.

**현재 출고본은 이 경로에 진입하지 않는다** — `omarchy-hyprland-session-locked`
가 스테이징돼 있지 않아 `bash -c` 가 127 로 끝나고, `onExited(127)` 는
`strandedLockResolved = true` + `strandedLock = false` 로 조용히 비활성화된다
(exit 2 만 "미정"으로 재시도). 헬퍼 부재가 우연히 fail-safe 로 작동하고 있다.

| 상태 | hyprlock 잠금 중 셸 재시작 |
| --- | --- |
| 현재(헬퍼 미스테이징) | 셸 정상 기동, 개입 없음, hyprlock 유지 — **실측** |
| 헬퍼 스테이징 시 | 셸이 잠금 탈취 시도 → 거부 → **매번 사망** — **실측** |

`tests/package/test_staged_session_helpers.sh` 가 이 미스테이징을 의도로
고정한다(주석에 사유). 헬퍼 폐쇄(P08)를 이유로 나중에 올리려면 크래시를 먼저
막아야 한다.

### 22.5 남은 헬퍼 폐쇄 결함 (lock 경로)

lock 플러그인이 이름으로 부르지만 스테이징되지 않은 것:

| 헬퍼 | 호출 지점 | 현재 결과 |
| --- | --- | --- |
| `omarchy-hyprland-session-locked` | `strandedLockCheckProc` | 127 → stranded 복구 비활성 (**의도적 유지**, §22.4) |
| `omarchy-system-wake` | `runWake()` — 잠금/오타 입력마다 | 127 → 화면 깨우기 없음 |
| `omarchy-brightness-keyboard` | `runBlank()` | 127 → 키보드 백라이트 안 꺼짐 |

`omarchy-system-wake` / `omarchy-brightness-keyboard` 는 §22.4 같은 위험이
없고 순수 기능 손실이라 후속 마일스톤에서 verbatim 스테이징 후보다. 셋 다
`Process` stderr 가 저널로 나오지 않아 **로그에 `command not found` 가 남지
않는다** — 조용한 실패라는 점을 기록해 둔다.

### 22.6 정리

중첩 컴포지터·격리 셸·hyprlock 을 모두 종료한 뒤 확인: 소켓은 `wayland-1`
하나, 프로덕션 셸(pid 1252575) 생존, 사용자 `DP-1` 의 `solitaryBlockedBy` 에
`LOCK` 없음, 프로덕션 `lock isLocked` = `false`.

## §23 omarchy hypr toggles seam (v0.11, 2026-08-23 실측)

`omarchy-hyprland-monitor-clamshell` / `-internal` / `-internal-mirror` 는
`~/.local/state/omarchy/toggles/hypr/*.lua` 에 hl.monitor 규칙을 쓰고
`hyprctl reload` 한다. 업스트림에서 그것을 읽는 쪽은
`config/hypr/hyprland.lua:26` 의 `require("default.hypr.toggles")` 다.

우리 오버레이는 `overlay/hypr/bindings.lua` 끝의 sweep 블록으로 같은 자리를
채운다 — 정렬된 `*.lua` 를 각각 `pcall(dofile)`. `dofile` 은 모듈 캐시가 없어
업스트림 `{ reload = true }` 의 의미가 그대로 성립한다.

**conf 경로 실측:** 중첩 Hyprland(0.56.2, `env -u HYPRLAND_INSTANCE_SIGNATURE
Hyprland -c <tmp>/hyprland.conf --verify-config`, 사용자 세션 무관)로 세 번
쟀다.

1. `source = <dir>/*.lua` 에 실제 toggle 파일(`hl.monitor({ output =
   "HEADLESS-1", disabled = true })`, 한 줄)을 물렸을 때 — 로그는
   `config ok` 뿐, 오류 없음.
2. 그러나 `.lua` 확장자가 붙어도 conf 소스는 그 내용을 **Lua 로 실행하지
   않는다** — 일반 Hyprland conf 문법(줄마다 `keyword = value`)으로만
   파싱한다. 검증: `this_is_not_a_real_hypr_keyword = 123` 을 같은 방식으로
   sourcing 했을 때도 `config ok` 였다 — 즉 등호가 있는 줄은 미지의 keyword
   라도 조용히 버려진다(에러 없음). 대조로 등호가 없는 줄
   (`this is not valid lua at all !!! ###`)은 다음처럼 실패한다:

   ```
   Config error in file <tmp>/toggles/probe.lua at line 1: Invalid config line
   Config error in file <tmp>/hyprland.conf at line 2: Config error in file <tmp>/toggles/probe.lua at line 1: Invalid config line
   ```

   즉 `hl.monitor({ output = "HEADLESS-1", disabled = true })` 가 오류 없이
   통과한 것은 그 줄이 우연히 `keyword = value` 모양을 갖춰 "미지의 keyword"
   로 조용히 무시됐기 때문이지, Lua 로 실행돼 monitor 규칙이 적용된 것이
   아니다. glob 자체는 실제로 파일을 찾아 매칭한다는 것도 대조군으로 확인
   했다 — 존재하지 않는 디렉터리를 source 하면 `source= globbing error:
   found no match` 로 명확히 실패한다.
3. 실제 compositor(WLR_BACKENDS=headless)로 적용 여부까지 재확인하려 했으나
   이 환경엔 사용 가능한 headless DRM/GPU 백엔드가 없어(`CBackend::create()
   failed`) 기동 자체가 실패했다. 이 3번째 단계는 **측정하지 못했다** — 다만
   1·2번의 파싱 단계 증거만으로 브리프의 판정 기준("오류 없고 toggle 이
   반영되면 결말 A")을 결말 B 로 결정하기에 충분하다: 반영되지 않는다는
   근거(Lua 미실행)가 이미 확보됐다.

**결론(결말 B):** conf 의 `source =` 는 `.lua` 글롭을 문법적으로만 받아들일
뿐 그 안의 Lua 를 실행하지 않으므로, seam 은 `hyprland.lua` 설정에서만
성립한다. 관리 블록(`conf_snippet()`)에는 toggles glob source 줄을 넣지
않는다. conf 사용자에게는 `cachy-omarchy-doctor` 가 WARN 한다.

## §24 락 인지 셸 재시작 + reload/compat 위임 체인 (v0.12.0, 2026-08-23)

`cachy-omarchy-shell --restart` 는 kill 전에 셸 자신에게 `qs ipc -n -p
$OMARCHY_PATH/shell call -- lock status` 로 락 상태를 묻는다. `status()` 는
`shell/plugins/lock/Service.qml` 이 이미 계산해 둔 `locked`
(`lockRequested || sessionLock.locked || sessionLock.secure`) 를 포함해
`secure`/`requested` 등을 JSON 으로 반환한다. 판정:

- IPC 자체가 실패(타임아웃/셸 미기동)하거나, IPC 는 응답했지만 IPC-레벨
  오류(`qs ipc` 가 stdout + exit 0 으로 돌려주는 `Target not found.` 류 —
  lock 플러그인이 아직 로드되지 않았거나 애초에 빠졌다는 뜻)면 보존할
  락이 없으므로 **진행**.
- IPC 는 성공했고 응답이 `locked`/`secure`/`requested` 세 키를 모두 갖춘
  JSON 이며 `jq` 로 `.locked or .secure or .requested` 가 정확히 `false`
  로 읽히는 경우만 **진행**(셸 자신의 `locked` 판정을 우선한다).
- 그 외 전부 — 세 키 중 하나라도 없음(예: `{}`), 파싱 불가, `jq` 부재,
  판정값이 `true` — **거부**(exit 1, 영어 stderr
  `Refusing to restart the shell while the session is locked.`).

거부 쪽으로 기운 것은 의도다: 잘못 진행하면 hyprlock 이 quickshell 과 함께
죽어 세션이 Hyprland failsafe 뒤에 갇히는 중대 사고(§22.4)이고, 잘못
거부하면 재시작 한 번을 손해 보는 경미한 사고이기 때문이다. 이 계약은
`tests/runtime/test_shell_restart_lock.sh` 가 고정한다(실제 hyprlock 을
잠그는 라이브 실험은 하지 않았다 — mock IPC 응답으로 세 분기를 각각
검사한다).

위임 체인:

```
omarchy-restart-shell (compat, /usr/bin 심링크 → compat/bin 실체)
  → cachy-omarchy-shell --restart (락 조회 → kill → 재기동 로직 실체)
```

compat `omarchy-restart-shell` 은 `exec cachy-omarchy-shell --restart` 다 — 락
조회·kill 로직을 이중화하지 않는다. (v0.12.0 에는 사이에 `cachy-omarchy-reload`
별칭이 있었으나 `--restart` 와 같은 일이라 지웠다.) 업스트림 `omarchy-restart-shell` 을
verbatim 으로 올리지 않은 이유: 원본은 미스테이징 헬퍼 3개
(`omarchy-hyprland-session-locked`, `omarchy-launch-shell`,
`omarchy-system-sleep-lock`)를 전제하고 `quickshell kill` 이 종료까지
블록하는 빌드를 가정하는데, 이 환경에 고정된 quickshell 0.3.0 은 kill 이
즉시 반환해 그 전제가 레이스가 된다.

**stranded-lock recovery 를 이 체인에 넣지 않은 이유.**
`omarchy-hyprland-session-locked` (업스트림에서 고아 락을 판별해 재확보를
시도하는 헬퍼)는 여전히 스테이징하지 않는다 — `milestone=blocked`. §22.4 의
실측이 근거다: hyprlock 이 세션을 쥔 상태에서 quickshell 이 ext-session-lock
을 요청하면 hyprlock 은 `onLockFinished` 로 우아하게 처리해 생존하지만,
quickshell 은 Wayland 프로토콜 오류로 연결이 끊겨 죽는다. 이 마일스톤은 그
비대칭을 다시 측정하거나 뒤집지 않았다 — 그래서 우리 재시작 계약은 "거부"
까지만 하고, 락을 강제로 회수하려는 시도는 하지 않는다.
