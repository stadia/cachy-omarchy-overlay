# Quattro 셸 기동 계약

> Milestone 2 기동 계약 + Milestone 3 런처 실측. 패키징된 업스트림 Omarchy
> Quattro 셸을 CachyOS에서 기동·토글하기 위해 **실측으로 확정한** 계약.
> 측정한 것과 추론한 것을 구분해 적는다.
>
> 스펙: `SPEC.md` (Spec 1.0) §13–§17·§19·§20·§42.3·§43–§45·§48(R01–R06)·§55·§56.
> 핀: `upstream.lock` — Omarchy 4.0.0 @ `f0020448ca87329199de7cb12f2015ebc4a3e5e7`.

---

## 1. 기동 명령

확정된 `--run` 의 정확한 명령(`overlay/bin/cachy-omarchy-shell`):

```bash
export OMARCHY_PATH=/usr/share/cachy-omarchy/upstream
# compat shim 디렉터리가 존재할 때만 PATH 앞에 붙인다 (M3: uwsm-app, §4).
[[ -d /usr/lib/cachy-omarchy/compat/bin ]] && export PATH="/usr/lib/cachy-omarchy/compat/bin:$PATH"

exec env QS_DISABLE_FILE_WATCHER=1 QS_NO_RELOAD_POPUP=1 \
  systemd-cat -t cachy-omarchy-shell -- \
  quickshell -n -p "$OMARCHY_PATH/shell"
```

각 환경변수의 이유:

| 변수 | 값 | 이유 |
| --- | --- | --- |
| `OMARCHY_PATH` | `/usr/share/cachy-omarchy/upstream` | `shell/shell.qml:27` 가 `Quickshell.env("OMARCHY_PATH")` 로 자산을 찾는다. 래퍼/유닛이 설정하지 않으면 IPC·기동이 모두 실패한다. |
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

## 3. 비활성 플러그인 — v0.2.0 에서 폐기됨 (M2 기록으로 보존)

> **🔄 개정 (v0.2.0, M8, 2026-08-17).** 이 절이 서술하는 비활성 집합은 **더 이상
> 존재하지 않는다.** 정본 `overlay/defaults/shell.json` 은 핀 커밋 업스트림 파일
> 그대로이며 `disabledPlugins` 키 자체가 없다. 바·알림·OSD·idle·락은 전부 켜진
> 채로 뜬다. 억제는 라이브 충돌이 실측된 곳에만, 사용자 opt-out 으로 돌아온다
> (바는 `bar-off` 토글). 근거와 결정은 M8 평가 문서, 개정된 SPEC §4.3·§17·§18·§61.
>
> 아래 본문은 **M2 시점의 실측 기록**으로 남긴다. 그 안의 기술적 발견 두 가지는
> 지금도 참이고 여전히 중요하다: (a) `disabledPlugins` 로는 내장 바를 끌 수 없다,
> (b) `bar-off` 는 표면을 없애는 게 아니라 `y=-26` 으로 주차시킨다.

M2 당시 패키지에 스테이징되던 `disabledPlugins`:

```text
omarchy.bar  omarchy.notifications  omarchy.lock  omarchy.osd
omarchy.idle  omarchy.battery  omarchy.nightlight  omarchy.media
omarchy.polkit  omarchy.reminders  omarchy.background
```

`omarchy.menu` 는 목록에 **없었다** (M3 런처).

### 기동 시 실측 상태 (라이브 `listPlugins` IPC)

> Task 5 라이브 기동에서 `shell listPlugins` / `shell listShellConfig` 로 관측.

- **37개 플러그인이 레지스트리에 등록**되었다 (스캔 성공의 증거).
- `listShellConfig` 의 `disabledPlugins` 가 스테이징된 우리 정본과 **정확히 일치**.
- 내장 바를 뺀 비활성 대상 10개는 전부 `enabled=false` 로 보고.
- 대조군: 비활성 목록 밖 first-party 플러그인(`omarchy.clipboard`)은 `enabled=true`.
- `omarchy.menu`: `menu,bar-widget` 종류로 등록, `firstParty=true`, 비활성 목록 부재. **로드됨.**

### 🔴 한계 — `disabledPlugins` 는 내장 바를 끄지 못한다

이것이 본 문서의 가장 중요한 제약이다.

- `services/PluginRegistry.qml` 의 `isEnabled(id)` 는 플러그인 `kinds` 에 `"bar"` 가
  있으면 `isDisabled` 검사 **전에** early-return 한다. 선택 기준은 `config.bar.id`
  (없으면 `omarchy.bar`). 즉 `disabledPlugins` 에 `omarchy.bar` 를 넣어도 효과가 없다.
- `shell.qml:975` 의 `canDisable: !isBarOption` — 바 옵션은 `canDisable=false` 로
  선언된다 (`listPlugins` 로 실측 확인).
- `shell.qml:166,180,240` — `defaultBarId="omarchy.bar"`, `activeBarId` 가
  `config.bar.id` 없으면 `omarchy.bar` 로 회귀, `defaultBarLoader` 가
  `activeBarId===defaultBarId` 면 무조건 active. `bar.id` 를 다른 값으로 바꿔도
  로드 실패 시 `omarchy.bar` 로 폴백(line 257).

**결론**: `shell.json` 만으로는 "바 없음" 상태를 만들 수 없다. 업스트림은 항상 바를
원하며, 바를 숨기는 유일한 업스트림 경로는 **`bar-off` 토글** —
`~/.local/state/omarchy/toggles/bar-off` 파일 존재 여부(`plugins/bar/Bar.qml:935~949`,
`bin/omarchy-toggle-bar`). 이것은 **사용자 상태**이므로 §6.6 상 패키지 상태가 될 수 없다.

> **측정**: 라이브 기동에서 `omarchy-bar` layer-shell 표면이 매핑되었다
> (`namespace=omarchy-bar`, 폭 3072, 높이 26). 기본 `ExclusionMode.Auto` 면 화면 상단
> 26px 를 예약해 사용자 창을 민다. 본 테스트는 샌드박스 HOME 에 `bar-off` 를 만들어
> `y=-26` 에 주차시켜 화면 밖으로 숨겼다 — 이것이 "패키지 기본값이 바를 없앴다"가 아님에
> 주의. **패키징 기본값만 쓰면 사용자 Waybar 위에 바가 뜬다 (§4.3 위반).**

해결 후보 (M2 범위 밖, M5 `cachy-omarchy-init` 작업):

1. **compat/init** (§44 선호): M5 오버레이의 `cachy-omarchy-init` 가 세션 시작 시
   사용자 상태로 `bar-off` 토글을 생성. 패치 0 유지.
2. **패치** (§23, 최후): `disabledPlugins` 가 바를 존중하도록, 또는 `bar.id` 가
   비었을 때 바 로더를 끄도록. 패치 예산 증가 + 사유·테스트·`patches/README.md` 필수.

> **M2 선언 주의**: §55 의 세 종료 기준(R01 기동·R02 IPC·공식 Omarchy 미설치)은
> 충족되었으나, **§4.3(기존 Waybar 보존)·§17(서비스는 Waybar 대체 금지)·§61
> "Existing Waybar preserved" 는 현재 패키징 기본값으로 충족되지 않는다.** 이 항목은
> 위 후보 중 하나로 해결되기 전까지 "미충족"으로 다뤄야 한다.

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
이 호스트에 `uwsm-app` 이 없어 `overlay/compat/bin/uwsm-app` WRAPPER 를 추가했다
(`exec "$@"` 만, gtk-launch 재구현 아님). compat PATH 는 `cachy-omarchy-shell --run`
이 셸 프로세스에만 붙인다(§45). 기동 자체는 이 shim 없이 통과한다.

> **측정**: 기동에 `omarchy-*` shim 불필요. 메뉴 앱 실행에 `uwsm-app` WRAPPER 필요.

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

1. **바 억제 미충족 (§4.3)** — §3 참조. `disabledPlugins` 로 내장 바를 못 끈다.
   패키징 기본값만으로는 사용자 Waybar 위에 `omarchy-bar` 가 뜬다. M5 `cachy-omarchy-init`
   가 `bar-off` 토글을 사용자 상태로 생성하거나, 패치가 필요. **§61 "Existing Waybar
   preserved" 는 이 항목 해결 전까지 성립하지 않는다.**

2. **`inotify-tools` 미감사 의존성** — `services/PluginRegistry.qml:638` 의
   `localPluginWatcher` 가 `inotifywait` 로 `~/.config/omarchy/plugins` 를 감시한다.
   이 호스트에 `inotify-tools` 가 없어 **1초마다 WARN 이 반복**된다(`onExited` →
   1초 재시작 타이머). 기능은 정상(37개 플러그인 등록)이지만 로그 스팸. `PKGBUILD depends`
   에 없고 `RUNTIME_DEPENDENCIES.md` 에도 없었다 — M1 의존성 감사(§28)의 누락.
   → `RUNTIME_DEPENDENCIES.md` 갱신 + `inotify-tools` 를 `depends` 에 추가할지 결정 필요.

3. **셸 자동 기동 누락** — 셸은 Hyprland autostart(`overlay/hypr/bindings.lua`
   의 `hl.on("hyprland.start", …)`)로 기동한다. 업그레이드로 autostart 줄이
   추가됐더라도 live `~/.config/cachy-omarchy/hypr/bindings.lua` 는 `--force`
   없이 갱신되지 않는다. 해결: `cachy-omarchy-bindings --force` 로 정본 새로고침
   후 재로그인(또는 수동 `cachy-omarchy-shell --run`). `hyprctl reload` 만으로는
   `hyprland.start` 가 재발화하지 않으므로 셸이 뜨지 않는 게 정상이다.
   참고: `hyprland.start` 트리거의 1회 발화 자체는 아직 실측되지 않았다 —
   첫 재로그인 시 확인(프로젝트 관행 "문서 < 실측"). 정적 테스트는 이벤트 이름이
   bindings 파일에 존재함만 검증하며, 실제 발화를 증명하지 않는다. 또, 과거에
   구 유닛을 수동으로 `enable` 했던 사용자는 `systemctl --user disable
   cachy-omarchy-shell.service` 로 잔여 `wants/` 심볼릭 링크를 정리해야 한다
   (pacman 은 유닛 파일은 지우지만 symlink 는 남길 수 있다).

4. **사용자 `~/.config/omarchy/shell.json` 오버라이드** — §2. 우리 기본값이 통째로
   무시될 수 있음. 감지·경고는 M7 doctor 후보.

5. **`uwsm` 부재** — `pacman -Q uwsm` → 미설치(실측). M3 에서
   `overlay/compat/bin/uwsm-app` WRAPPER 를 추가해 `gtk-launch` 로 위임.
   `REIMPLEMENT` 아님. 셸 프로세스 PATH 에만 붙음.

6. **패키지 미설치 상태에서만 검증** — 본 M2 검증은 빌드 산출물을 임시 디렉터리에
   추출해 그 트리를 띄운 것으로, `/usr/share/cachy-omarchy/upstream` 에 실제 설치된
   상태는 아니다. 실설치 경로 검증은 M5.

7. **IPC 오류 문자열** — §5. M3 에서 `Target not found.` / `Function not found.`
   실측 완료. 미실측이 아님.

---

## 7. M3 결과

브랜치 `feature/spec-1.0-m3`. 메뉴 UI 재구현 없음. 패치 수 0. Waybar 보존은
성공으로 선언하지 않음(한계 1).

| 수용 | 실측 |
| --- | --- |
| R03 | `listPlugins` 에서 `omarchy.menu` kinds `menu,bar-widget` |
| R04 | `cachy-omarchy-launcher` 후 `hyprctl layers` 의 `omarchy-menu` 기하 (예: 3072×1728 @ 0,0). IPC 불린만으로 렌더를 주장하지 않음 |
| R05 | `wtype -k Escape` 후 `omarchy-menu` layer 소멸 |
| R06 | 샌드박스 더미 `.desktop` → AppLibrary `uwsm-app -- gtk-launch` → 마커 파일 |

구현:

- `overlay/bin/cachy-omarchy-launcher` — `--ipc shell toggle omarchy.menu '{"menu":"root"}'`
- `overlay/compat/bin/uwsm-app` — `--` 뒤 `exec "$@"`
- `overlay/bin/cachy-omarchy-bindings` + `overlay/hypr/bindings.{conf,lua}` —
  SUPER+SPACE. 충돌 시 기본은 미주입. `hyprctl reload` 없음. SUPER+K 는 주석 자리(M4)
- `docs/COMMAND_AUDIT.md` 전수 표 160행. ADAPTED 3 (`omarchy-shell`,
  `omarchy-menu-keybindings`, `omarchy-restart-shell`). 나머지 DISABLED/disable.
  비활성 경로 = 공식 bin 미설치 + when 가드. JSONC 패치 없음

## 8. M4 결과 — 업스트림 키바인딩 UI

브랜치 `feature/spec-1.0-m4`. `SUPER+K`의 공개 명령은
`cachy-omarchy-keybindings`다. 이는 핀된 `bin/omarchy-menu-keybindings`
(`f0020448ca87329199de7cb12f2015ebc4a3e5e7`, MIT)의 **적응 카피**이며, 별도
**커스텀 QML** 키바인딩 뷰어는 만들지 않았다. 시각/런타임 경로는 업스트림 그대로
`omarchy-menu-select` → compat `omarchy-shell` →
`shell summon omarchy.menu` select mode 다.

### 데이터 수집 적응과 한계

호스트 CachyOS Lua 설정은 `description` 없는 `__lua` bind 48개를 보고한다. 원본
스크립트는 description 조인 때문에 webapp 정적 2행만 출력했다. 적응 카피는
`modmask+key`로 Lua 캐시를 조인하고 설명을 합성하며, CachyOS에 없는 정적 webapp
행은 제거했다. 실사용 설정으로 한 `--print`는 정확히 **48** record를 출력한다.
캐시 schema는 업스트림 v11을 재사용하지 않는 **v12**다.

`code:NNN` bind가 Hyprland에서 기호 키를 주지 않으면 조인이 빗나갈 수 있고, 같은
modmask+key를 submap/중복 정의하면 마지막 Lua source record가 이긴다. 이 두 한계는
M4에서 해소하지 않았다.

사용자 Lua source는 실행 가능한 신뢰 입력으로 취급하지 않는다. 스캐너는
`loadfile(config, "t", env)` 제한 환경에서만 `pcall(chunk)` 하며 **dofile 하지 않는다**.
config에는 fake `hl`, 순수 Lua 기능, 읽기 전용 `string`/`table`/`math`, `os.getenv`만
보이고 `io`/`package`/`require`/`debug`/`dofile`/`loadfile`은 없다. `os.execute`로
marker를 만들려는 회귀 fixture가 실행되지 않음을 검증했다. 지원하지 않는 config API는
fail-closed 되므로 그 뒤 bind가 누락될 수 있다.

### compat·패키지 표면

패키지 upstream tree에는 필요한 두 원본만 stage한다:
`upstream/bin/omarchy-menu-select`, `upstream/bin/omarchy-cmd-present`.
`overlay/compat/bin/omarchy-shell`은 `cachy-omarchy-shell --ipc`로 전달한다. compat에
`omarchy-menu-keybindings` **동명 shim**은 두지 않았으므로, upstream 메뉴의
`learn.keybindings` action은 여전히 범위 밖이며 실패한다. 범위는 SUPER+K / 공개 명령만이다.
공식 omarchy를 설치하거나 대량의 가짜 `omarchy-*`를 `/usr/bin`에 설치하지 않았다.

### 라이브 샌드박스 실측

`tests/test.sh`의 샌드박스 HOME에 실제 `hyprland.lua`를 읽기 전용 복사하고 `bar-off`
상태에서 추출 tree 셸을 기동했다. helper는 `omarchy-menu` layer를 열었고 측정 기하는
**1920×1080 @ 0,0** 이었다. Lua cache는 정확히 48행이었다. binding을 선택하지 않고
`Escape`만 보내면 layer가 닫히고 dispatch 없이 **helper exit 0**으로 끝났다. journal에는
`Configuration Loaded` 한 줄, QML 오류/`ERROR` 없음, PID cleanup 후 남은 menu layer도
없었다.

이는 테스트 샌드박스 결과일 뿐 **Waybar 보존을 성공으로 선언하지 않는다**. `bar-off`는
M4 데모 격리용이며 사용자 상태/기존 Waybar 문제 해결이 아니다.

### 관리 바인딩과 범위

`overlay/hypr/bindings.conf`와 `bindings.lua`는 `SUPER+K`를 unbind 뒤
`cachy-omarchy-keybindings`에 bind한다. 기본은 기존 SUPER+K 충돌을 거부하고, `--force`는
한 줄 경고 후 기존 사용자 bind 줄을 지우지 않은 채 관리 블록만 추가한다. 문서화된
SUPER/mainMod 형식만 충돌로 인식한다. 테스트는 사용자 설정을 바꾸지 않으며
**hyprctl reload 없음**을 정적으로 검증한다.

패치 수 0을 유지한다(`packages/cachy-omarchy-shell/patches/README.md`: `none`).
overlay 패키지, `cachy-omarchy-init`, Waybar 처리와 실제 설치 통합은 **M5 범위 밖**이며,
사용자 지시 전에는 구현하거나 merge/handoff 하지 않는다.

---

## 9. M5 결과 — 오버레이 패키지와 설치 트리 통합 검증

브랜치 `feature/spec-1.0-m5`. `tests/runtime/test_installed_tree.sh` 가 두 패키지
아티팩트(`cachy-omarchy-overlay-0.1.0-1-any.pkg.tar.zst`,
`cachy-omarchy-shell-4.0.0-1-any.pkg.tar.zst`)를 임시 디렉터리에 겹쳐 추출해
"설치된 것처럼" 배치하고, 공개 명령이 그 트리만으로 동작하는지 검증한다.
`sudo`/`pacman -U` 는 쓰지 않는다. 패치 수는 여전히 **0**이다.

### 9.1 패키지 소유 경로 — `cachy-omarchy-overlay` 실측

`bsdtar -tvf build/cachy-omarchy-overlay-0.1.0-1-any.pkg.tar.zst` 로 실측한 결과,
메타 항목(`.BUILDINFO`/`.MTREE`/`.PKGINFO`)과 디렉터리 항목을 뺀 **파일 11개**가
정확히 아래 경로다:

| # | 경로 |
| --- | --- |
| 1 | `usr/bin/cachy-omarchy-bindings` |
| 2 | `usr/bin/cachy-omarchy-init` |
| 3 | `usr/bin/cachy-omarchy-keybindings` |
| 4 | `usr/bin/cachy-omarchy-launcher` |
| 5 | `usr/bin/cachy-omarchy-shell` |
| 6 | `usr/lib/cachy-omarchy/compat/bin/omarchy-shell` |
| 7 | `usr/lib/cachy-omarchy/compat/bin/uwsm-app` |
| 8 | usr/share/cachy-omarchy/hypr/bindings.lua (autostart) |
| 9 | `usr/share/cachy-omarchy/defaults/shell.json` |
| 10 | `usr/share/cachy-omarchy/hypr/bindings.conf` |
| 11 | `usr/share/cachy-omarchy/hypr/bindings.lua` |
| 12 | `usr/lib/cachy-omarchy/compat/bin/omarchy-update-available` (v0.2.0) |

> **M9 갱신 (v0.3.0)**: 위 표는 M5 시점의 실측 스냅샷이다. 현재 오버레이 패키지는
> 여기에 `usr/bin/cachy-omarchy-doctor`·`usr/bin/cachy-omarchy-theme-set` 과
> compat no-op shim 2개(`omarchy-theme-set-browser`·`-keyboard`)를 더 소유한다.
> 셸 패키지는 M9 부터 `themes/`·`default/themed/`·테마 helper Tier A/B 도
> 스테이징한다 — §18 참조.

v0.2.0 부터 셸 패키지는 바 위젯이 bare name 으로 부르는 업스트림 helper 도 함께
스테이징한다 (`usr/share/cachy-omarchy/upstream/bin/`): Tier A `omarchy-menu-select`
`omarchy-cmd-present` `omarchy-audio-output-sink` `omarchy-network-status`
`omarchy-network-band` `omarchy-monitor-state` `omarchy-hyprland-monitor-scaling`,
Tier B `omarchy-reminder` `omarchy-notification-send` `omarchy-agent-usage-{update,claude,codex,fireworks}`.
전부 업스트림과 바이트 동일하다(`tests/package/test_staged_helpers.sh` 가 확인).
밝기 체인(`omarchy-brightness-display*`, `omarchy-hw-display`)은 의존 명령이 없어
넣지 않는다. `cachy-omarchy-shell --run` 이 `$OMARCHY_PATH/bin` 을 **셸 프로세스
PATH 에만** 붙인다 — compat shim 디렉터리가 그보다 앞이라 적응 카피가 동명
업스트림 파일을 이긴다.

`/etc`, `/boot`, `/efi`, system 유닛(`usr/lib/systemd/system/`)은 소유하지 않는다.
compat shim(6, 7번)은 `/usr/lib/cachy-omarchy/compat/bin/` 에만 있고 `/usr/bin` 으로
새지 않는다 — `test_installed_tree.sh` 가 두 방향 모두 확인한다.

### 9.2 `cachy-omarchy-init` 계약

`overlay/bin/cachy-omarchy-init` (설치 후 `usr/bin/cachy-omarchy-init`)은 패키지의
post-install 훅이 아니라 **사용자가 직접 실행**하는 유저 레벨 헬퍼다(SPEC §38). 무엇을
만드는지, 언제 만드는지, 멱등 규칙은 다음과 같다.

- **만드는 것 (최초 실행 시에만)**
  - `~/.config/cachy-omarchy/hypr/bindings.{conf,lua}` — `cachy-omarchy-bindings` 에
    위임해 설치하고, 사용자 Hyprland 설정에 관리 source 블록만 주입한다(본문은 건드리지
    않음).
- **만들지 않는 것 — `~/.local/state/omarchy/toggles/bar-off` (v0.2.0 개정).** 0.1.x
  init 은 이 빈 파일을 만들어 내장 바를 숨겼다. v0.2.0 부터는 만들지 않는다 —
  바는 기본으로 보인다. `toggles` 디렉터리조차 만들지 않는다(만들면 다음 실행이
  "사용자 상태 존재"로 오독한다). 업그레이드한 사용자가 이미 가진 토글은 사용자
  상태이므로 지우지 않고, init 은 "유지" 한 줄을, `cachy-omarchy-doctor` 는
  `WARN` 과 함께 지울 `rm` 명령을 알린다. 바를 끄고 싶으면 사용자가 직접 만든다:
  `: > ~/.local/state/omarchy/toggles/bar-off`.
- **만들지 않는 것** — `~/.config/cachy-omarchy/shell.json`. 셸이 읽는 사용자 경로는
  `~/.config/omarchy/shell.json` 이지 이 경로가 아니므로, 여기에 파일을 만들면 사용자
  편집이 조용히 무시된다(dead file). 패키지 기본값은
  `/usr/share/cachy-omarchy/upstream/config/omarchy/shell.json` 으로 스테이징되며
  init 없이도 셸이 적용한다. 기존 사용자가 이 dead file 을 갖고 있다면
  `cachy-omarchy-doctor` 가 WARN 으로 알린다.
- **멱등 규칙 — 파일 단위, 존재 여부만 본다.** 대상 파일이 이미 있으면 건드리지 않고
  "유지" 메시지만 낸다. 두 번째 실행은 사용자가 고친 `shell.json` 을 덮어쓰지 않는다
  (`tests/runtime/test_init.sh` 의 `USER_EDIT` 보존 검증).
  - `--dry-run` 은 무엇을 할지 출력만 하고 **아무 파일도 만들지 않는다.**
- **`bindings.conf`/`bindings.lua` 도 같은 규칙을 따른다 — 존재하면 절대 덮어쓰지
  않는다.** SPEC §6.6 상 이 두 파일은 "사용자 라이브 설정"이고 정본은
  `/usr/share/cachy-omarchy/hypr/` 에 있으므로, 패키지가 업그레이드돼도 사용자가
  고친 바인딩을 재실행이 지우면 안 된다. `cachy-omarchy-bindings` 는 파일이 이미
  있으면 건드리지 않고 어떤 파일을 그대로 뒀는지 한 줄로 알린다.
  **예외 — `--force` 는 이 두 파일도 정본으로 새로고침한다.** `--force` 는 원래
  "바인딩 충돌이 있어도 관리 블록을 주입한다"는 뜻이었는데, 같은 플래그가 이제
  "이미 있는 bindings.conf/lua 도 갱신하라"는 의미를 겸한다 — 사용자가 명시적으로
  더 적극적인 동작을 요청했다고 보기 때문이다. `--force` 를 전달하지 않으면 두
  동작 모두 일어나지 않는다(`tests/runtime/test_init.sh` 의 바인딩 보존 / `--force`
  갱신 케이스로 검증).
- **`bar-off` 는 사용자가 지우면 되살리지 않는다.** 판단 기준은 **파일이 아니라
    toggles 디렉터리의 존재**다: `~/.local/state/omarchy/toggles/` 디렉터리가 이미
    있으면(즉, 최초 실행을 이미 거쳤으면) 그 안의 `bar-off` 를 다시 만들지 않는다 —
    사용자가 지운 것을 "바를 보겠다"는 의사로 해석한다. 디렉터리 자체가 없을 때만
    최초 생성 대상이다.
- 바인딩 설치는 **재구현하지 않고** 형제 명령 `cachy-omarchy-bindings` 에 위임한다
  (SPEC §20). `--force` 는 그대로 전달되며, 충돌 시에도 기존 사용자 바인딩 줄을
  지우지 않는다(관리 블록 주입 대상은 여전히 `hyprland.lua`/`hyprland.conf` 본문이며,
  거기서는 --force 도 사용자 줄을 삭제하지 않는다 — 새로고침 대상은 어디까지나
  `~/.config/cachy-omarchy/hypr/bindings.{conf,lua}` 파일 자체다).
  `hyprctl reload` 는 어디에서도 호출하지 않는다.

### 9.3 바 / Waybar 상태 — 정확히 이렇게 말한다

**패키지 기본값은 내장 바를 끄지 못한다.** `shell.qml:975` 의 `canDisable: !isBarOption`
때문에 바 종류(`kinds` 에 `"bar"` 포함) 플러그인은 `disabledPlugins` 검사 이전에
early-return 하도록 업스트림이 설계돼 있다(§3 상세). 이 제약은 M5 에서도 그대로다 —
`shell.json` 만으로는 바를 끌 수 없다.

`cachy-omarchy-init` 를 **실행한** 사용자만 `~/.local/state/omarchy/toggles/bar-off`
를 갖게 되고, 그 토글이 바를 화면 밖(`y=-26`)으로 숨긴다. `cachy-omarchy-init` 를
실행하지 않은 사용자는 매 모니터 상단에 26px 를 예약하는 바를 그대로 보게 된다.

**"Waybar 가 보존된다"고 선언하지 않는다.** 이 오버레이는 사용자의 기존 Waybar 를
찾거나 조율하지 않는다. 위 문장은 "패키지 설치만으로 내장 바가 꺼진다"는 오해를 막기
위한 것이며, `init` 를 실행한 뒤에도 검증한 것은 Omarchy 내장 바가 숨는다는 사실뿐이고
Waybar 와의 상호작용은 측정한 적이 없다.

### 9.4 systemd 타깃 실측 (재확인, 2026-08-16)

Task 4 가 측정한 값을 본 태스크에서 동일한 읽기 전용 명령으로 재확인했다. 값은
변화가 없다:

```
$ systemctl --user is-active graphical-session.target; echo "exit=$?"
inactive
exit=3

$ systemctl --user show -p WantedBy -p After graphical-session.target
WantedBy=
After=graphical-session-pre.target basic.target gnome-session.target

$ systemctl --user list-unit-files | grep -i cachy-omarchy
(출력 없음 — 일치 항목 없음)
```

`graphical-session.target` 은 이 호스트에서 **inactive** 이고, `cachy-omarchy-shell.service`
는 어떤 systemd 유닛 탐색 경로에도 설치돼 있지 않다(추출 트리 안에서만 존재 확인).
**자동 기동 경로는 실측하지 못했다.** 유닛 파일의 `WantedBy=graphical-session.target`
은 유닛이 **의도**하는 바이지, 타깃이 활성화됐을 때 실제로 pull-in 되어 기동한다는
**실측된 동작이 아니다.** `enable`/`start`/`daemon-reload` 를 실행하지 않았으므로 이
차이를 관측할 방법 자체가 없었다. 이후 문서·핸드오프에서 "자동으로 기동한다"라고
쓰지 않는다.

### 9.5 미검증 항목

> **2026-08-17 갱신:** 아래 1·3·4 항목은 §12 에서 실 시스템으로 검증됐다. 이 목록은
> Milestone 5 종료 시점의 기록으로 보존하며, 현재 상태는 §12 와
> `docs/RC_GAP_INVENTORY.md` 를 권위로 삼는다. 2(키 주입)와 5(스킵 false-green)는
> 여전히 유효하다.

Milestone 5 종료 시점까지 실측하지 못한 것을 명시한다:

1. **실제 `pacman -U` 설치.** 본 태스크의 검증은 `bsdtar` 로 임시 디렉터리에 두 패키지를
   겹쳐 추출한 것이며, 파일 권한·소유자·`.INSTALL` 스크립트 유무 등 실제 설치와 다른
   부분이 있을 수 있다.
2. **`COO_RUN_LIVE=1` 키 주입 전수 테스트.** 포커스 창이 없는 상태에서 사용자가 수동으로
   실행해야 하는 항목이며, 본 태스크에서는 실행하지 않았다.
3. **클린 chroot 빌드.** 두 PKGBUILD 모두 `package()` 에서 `$startdir/../../` 로 레포
   상위 경로를 참조한다(`packages/cachy-omarchy-shell/PKGBUILD`,
   `packages/cachy-omarchy-overlay/PKGBUILD`). 클린 chroot 는 PKGBUILD 자신의 디렉터리만
   바인드 마운트하므로 이 경로가 해석되지 않는다. SPEC §26 이 v0.1 에는 일반 `makepkg`
   를 허용하지만, 릴리스 품질에는 해결이 필요하다(M6/M7 로 이월).
4. **`graphical-session.target` 자동 기동.** §9.4 참조 — 이 호스트에서 타깃이 inactive
   라 pull-in 동작을 관측할 수 없었다.
5. **🔴 `build/*.pkg.tar.zst` 가 없으면 이 캡스톤 테스트는 아무것도 검증하지 않고
   "통과"로 집계된다 — Milestone 6 파이프라인은 반드시 이 문단을 읽을 것.**
   `tests/runtime/test_installed_tree.sh` 는 시작부에 다음 두 줄이 있다:

   ```bash
   coo_pkg_artifact >/dev/null 2>&1 || { echo "skip: 셸 아티팩트 없음"; exit 0; }
   coo_overlay_artifact >/dev/null 2>&1 || { echo "skip: 오버레이 아티팩트 없음"; exit 0; }
   ```

   `build/cachy-omarchy-shell-*.pkg.tar.zst` 또는
   `build/cachy-omarchy-overlay-*.pkg.tar.zst` 가 (아직 `makepkg` 를 돌리지 않아서)
   하나라도 없으면, 아홉 개 assertion 중 **단 하나도 실행되지 않고** `exit 0` 으로
   끝난다. `tests/test.sh` 는 이것을 여느 성공한 테스트와 구분 없이 `PASS` 로 세고
   총계에 더한다 — 이 태스크 보고서의 "25/25 test files passed" 도 그 스킵 분기를
   타지 않고 실제로 아홉 assertion 이 전부 돈 결과였지만, 그 사실은 로그를 직접
   읽어야만 알 수 있고 총계 숫자만으로는 구분되지 않는다. **깨끗한 체크아웃에서
   `makepkg` 없이 `./tests/test.sh` 만 돌리는 CI 는, 이 캡스톤 테스트가 증명하려는
   바로 그것(추출 트리 통합)을 한 번도 실행하지 않고도 녹색을 낼 수 있다.**

   같은 패턴이 이 테스트에만 있는 것이 아니다 — `tests/runtime/test_harness.sh`,
   `tests/runtime/test_shell_smoke.sh`, `tests/runtime/test_app_launch.sh`,
   `tests/runtime/test_launcher_toggle.sh`, `tests/runtime/test_keybindings_toggle.sh`,
   `tests/package/test_overlay_files.sh`, `tests/package/test_overlay_forbidden.sh`
   모두 아티팩트나 라이브 환경(quickshell/jq/hyprctl/wtype/`WAYLAND_DISPLAY`/
   `COO_RUN_LIVE=1`)이 없으면 동일하게 `skip:` 후 `exit 0` 한다. 즉, **파이프라인
   요구사항은 이 파일 하나에 국한되지 않는다.**

   이 문서는 스킵 동작 자체를 바꾸지 않는다 — 환경 의존 테스트가 스킵하는 것은
   정당한 설계이고, 하나만 예외로 만들면 형제 테스트들은 조용히 스킵하는데 이
   테스트만 깨끗한 체크아웃에서 알 수 없는 빨간불을 내게 된다. 대신 **Milestone 6
   이 빌드/업데이트 파이프라인을 만들 때 지켜야 할 요구사항으로 못박는다**:

   - 파이프라인은 `./tests/test.sh` 를 돌리기 **전에** 두 패키지 모두 `makepkg` 로
     빌드해 `build/*.pkg.tar.zst` 를 준비해야 한다.
   - 파이프라인은 `tests/runtime/test_installed_tree.sh` (및 위에 나열한 형제
     테스트들)의 출력에서 `skip:` 문자열을 감지하면, 그 테스트를 **PASS 가 아니라
     실패로 취급**해야 한다 — `tests/test.sh` 자체의 exit code 만으로는 스킵과 실제
     통과를 구분할 수 없으므로, 파이프라인이 로그를 파싱해 별도로 강제해야 한다.

---

## 10. M6 결과 — 검증된 업데이트/재빌드 파이프라인

M6 공개 명령은 `bin/check-upstream`, `bin/update-upstream`, `bin/build-packages`,
`bin/test-packages`, `bin/install-packages`, `bin/rollback`, `bin/bump-pkgrel`이다.
이 명령들은 공식 `omarchy`/`omarchy-settings`를 설치하지 않으며, 기본 경로는
`pacman -U`를 호출하지 않는다.

### 10.1 build-before-test와 false-green 스킵 정책

`build-packages`는 shell 뒤 overlay 순서로 평범한 `makepkg --nodeps`를 실행하고,
두 아카이브의 금지 경로를 감사한 뒤 checksum을 기록한다. 테스트는 항상
`build-packages` 뒤에 `test-packages`로 실행한다. `makepkg -i`, clean chroot,
실제 설치는 이 명령 경로에 없다.

`test-packages`는 현재 lock/패키지 버전과 checksum이 일치하는
`validated-build.manifest`가 먼저 있어야 한다. 전체 테스트 출력에서 `skip:`을
실패로 승격한다. 특히 `tests/runtime/test_installed_tree.sh`의 아티팩트 부재
스킵은 절대 PASS가 아니다. 기본적으로 허용되는 것은 명시적
`COO_RUN_LIVE=1` 없이 생기는 라이브 키 주입 스킵과 라이브 Wayland 런타임
없음(소켓 부재 또는 systemd-cat/journald 사용 불가 — `command -v` 존재만으로
판단하지 않는다) 스킵뿐이며, 이 예외도 설치 트리/패키지 검증 성공을 뜻하지
않는다.

### 10.2 validated release와 명시적 설치

검증 정본은 `${XDG_STATE_HOME:-$HOME/.local/state}/cachy-omarchy/`
아래의 `validated-build.manifest`다. manifest는 upstream lock commit, 두 패키지
이름, SHA-256, immutable release 디렉터리를 함께 묶는다. `build/`의 평면
아카이브는 편의 복사본일 뿐 검증 권위가 아니며, stale 아티팩트를 설치 후보로
추정하지 않는다.

`install-packages`는 인자 없이 설치하지 않고 반드시 `--install`을 요구한다.
그 직전에 현재 manifest/checksum을 다시 검증하고, 이미 설치된 검증 pair가 있으면
먼저 state archive로 보존한다. 설치는 정확히 shell+overlay 두 파일만 대상으로
한다. 실제 `pacman -U` 실행은 사용자 승인 환경에서만 수행한다. pacman 성공 뒤
`installed-build.manifest` 확정에 실패하면 `install-pending.manifest`를 남기고
fail-closed로 끝낸다. 이 상태에서는 install/rollback 모두 거부되며, 운영자는
**operator recovery**로 실제 설치 상태를 확인·정리한 뒤에만 다음 작업을 진행한다.

`rollback`은 `packages/previous-*` 아래의 완전하고 checksum이 맞는 prior pair만
선택해 두 패키지를 함께 되돌린다. 임의 pacman cache나 CachyOS 시스템 파일,
Hyprland/Waybar/사용자 설정은 복원하지 않는다. prior manifest가 없거나 손상되면
pacman을 호출하지 않고 실패한다.

### 10.3 update transaction과 버전/문서 경계

`check-upstream`은 stable `vMAJOR.MINOR.PATCH` tag만 조회하는 read-only 명령이다.
annotated tag는 peeled commit을, lightweight tag는 direct commit을 사용한다.
`update-upstream`은 disposable candidate에서 patch→build→audit→test를 모두
성공시킨 뒤에만 `upstream.lock`, shell PKGBUILD의 `pkgver`/`_commit`, `pkgrel=1`을
발행한다. metadata 두 파일이 성공한 뒤에만 validated manifest를 **마지막**으로
발행하며, metadata 발행 실패 시 이전 metadata와 manifest를 보상 복구한다. overlay
버전은 독립적이므로 upstream update로 바꾸지 않는다.
`bump-pkgrel`은 로컬 packaging revision만 증가시키고 lock/pkgver를 바꾸지 않는다.

`UPSTREAM.md`의 Version/Tag/Commit 표는 사람이 유지하는 snapshot이다. release date와
CachyOS 실측 환경은 tag 조회만으로 알 수 없으므로 update 뒤 stale일 수 있다.
자동화/패키징 권위는 항상 `upstream.lock`이며, 사람이 release/test attestation을
확인한 뒤 `UPSTREAM.md`를 갱신한다.

### 10.4 U01–U10 검증과 남은 한계

`tests/package/test_update_pipeline.sh`는 fake git/makepkg/bsdtar/pacman만 사용해
U01 no-update/read-only, U02 lock update, U03 pkgrel reset, U04 local bump, U05 patch
failure, U06 build failure, U07 audit failure, U08 test/skip failure, U09 prior pair
retention, U10 valid/corrupt rollback을 검증한다. 실패 경로는 모두 install/pacman을
호출하지 않고 원래 lock/PKGBUILD를 보존해야 한다.

패치 수 0은 계속 유지한다. `packages/*/PKGBUILD`가 `$startdir/../../overlay`을
참조하므로 clean chroot는 여전히 깨져 있으며 M7에서 해결한다. 또한 이 호스트의
`graphical-session.target`은 inactive여서 service의 자동 기동은 미검증이다.
`WantedBy=graphical-session.target`은 의도이지 관측된 자동 시작이 아니다.

- autostart 전환 마이그레이션: 기존 설치는 `cachy-omarchy-bindings --force` 로
  live bindings 를 새로고침해야 자동 기동을 얻는다.


## 11. M7 RC 증거 — 실측 경계와 남은 승인 작업

M7은 증거 갱신이지 라이브 세션 수정 허가가 아니다. clean build 및 다른 모든 M7
테스트는 샌드박스 HOME, 추출 패키지 트리, 또는 fake 패키지 매니저 도구만 쓴다.
`cachy-omarchy-doctor`는 진단 전용이다 — 패키지 설치, 상태 복구, Hyprland reload,
서비스 시작, 사용자 설정 변경을 하지 않는다.

### 11.1 Doctor와 릴리스 상태

`cachy-omarchy-doctor`는 패키지 질의, 래퍼, 서비스, manifest, 프로세스, IPC 상태를
읽는다. 관측 불가를 정상으로 간주하지 않고 PASS, WARN, FAIL을 구분한다. 특히 공식
`omarchy` 및 `omarchy-settings` 패키지 질의, 사용자 오버라이드 및 inert
`~/.config/cachy-omarchy/shell.json`, 미관측 자동 시작 경계를 보고한다. 이 명령은
`tests/runtime/test_doctor.sh`가 통제된 `pacman`, `qs`, 프로세스, manifest fixture로
검증한다.

검증된 manifest가 릴리스 권위이며 평면 `build/` 아카이브는 편의 복사본일 뿐이다.
`install-pending.manifest`는 fail-closed다 — doctor가 FAIL로 보고하고 install과
rollback 모두 pacman 호출 전에 거부한다. 운영자가 실제 패키지 상태를 확인·해결해야
하며 doctor는 복구 동작을 의도적으로 두지 않는다. dangling pending 또는
installed-manifest 심볼릭 링크는 부재가 아니라 손상 상태다.

### 11.2 clean build 경계

`bin/build-packages --clean`은 임시의 commit 검증된 `clean-omarchy.tar`와
`clean-overlay*.tar`를 임시 패키지 컨텍스트로 운반하고
`makechrootpkg -r "$COO_CLEAN_CHROOT_DIR" -- --nodeps`를 호출한다. 이렇게 `overlay/`를
유일한 추적 정본으로 유지한다 — `packages/` 아래에 overlay 복사본을 커밋하지 않고
임시 소스는 실행 후 제거한다. `tests/package/test_clean_build.sh`가 fake
`makechrootpkg`로 해당 운반과 아카이브 감사를 실측한다.

> **2026-08-17 갱신:** 이 문단은 M7 종료 시점의 기록이다. 이후 `devtools 1:1.5.1-1`
> 을 설치하고 실제 chroot 에서 `build-packages --clean` 을 성공시켰다 — §12.5 참조.
> 다만 `--nodeps` 때문에 의존 선언의 충분성은 여전히 이 경로로 검증되지 않는다.

M7 종료 시점 기록: 이 호스트에는 `makechrootpkg`, `archbuild`, `devtools`가 없고 준비된
chroot도 없었다. 따라서 당시 실제 clean chroot 패키지 빌드는 **미검증**이었다 — fake
운반 테스트가 실제 chroot나 `makepkg -i`가 실행됐다는 주장이 아니다.

### 11.3 R01–R10 런타임 증거

`tests/runtime/test_runtime_reliability.sh`는 두 아카이브 페이로드를 하나의 추출 트리에
겹치고 샌드박스 HOME에서 실행한다. R01 래퍼 프로세스 생존과 R02 IPC `shell ping`을
실측했다. R03과 R06은 추출/정적 증거만 있고 R04와 R05는 승인된 라이브 Wayland 세션이
필요하므로 **미검증**이다. R08은 패키지 소유 경로만 실측했고 라이브 사용자 Waybar는
아니다.

R07은 **manual wrapper-restart evidence**다 — 테스트 소유 래퍼 자식을 멈추고 래퍼를
수동으로 다시 시작한 뒤 IPC가 성공한다. `Restart=on-failure` 서비스 복구는 승인된
user-systemd 테스트 없이 **미검증**이다. 자동 시작 역시 **미검증**이다 —
`graphical-session.target`이 inactive로 관측됐고 M7은 유닛을 enable/start/reload하지
않았다.

R09와 R10은 패키지가 notification/lock 시스템 경로를 소유하지 않고
`omarchy.notifications`/`omarchy.lock`이 기본 비활성임을 실측했다. dunst/mako 또는
hyprlock 등 사용자 lock 설정과의 라이브 공존은 **미검증**이다. 기존 Waybar 라이브
공존도 **미검증**이다. 어떤 notification/lock 데몬도 중지·시작·설정하지 않았다.

### 11.4 U01–U10 업그레이드·롤백 RC 증거

`tests/package/test_update_pipeline.sh`는 U01–U10을 **fake lane**으로 검증한다 — git,
makepkg, bsdtar, checksum, pacman이 샌드박스 fake다. no-update 동작, lock/pkgrel 발행,
설치 전 patch/build/audit/runtime 실패, prior-pair 보존, rollback 선택을 실측한다.
fake lane은 install 또는 rollback 후 pending 확정 실패도 검증한다 — pending이
fail-closed로 유지되고 doctor가 이를 FAIL로 보고하며 이후 install/rollback은 pacman을
호출하지 않는다.

이것은 워크플로 안전 증거이지 실제 `pacman -U` 설치·업그레이드·다운그레이드가 아니다.
실제 패키지 매니저 smoke는 격리 환경에서 명시적 사용자 승인 전까지 **미검증**이다.

### 11.5 RC 체크리스트 판정

패치 수는 **패치 수 0**이다 (`packages/cachy-omarchy-shell/patches/README.md`가 `none`).
공식 `omarchy`와 `omarchy-settings` 패키지는 기록된 호스트 검사에서 부재이며 의존이나
설치 대상이 아니다. `docs/RC_GAP_INVENTORY.md`가 SPEC §61의 권위 체크리스트다 —
모든 기준을 `측정됨`, `추론됨`, `미검증`으로 표시하고 해당 테스트를 연결한다. 위의
미검증 항목은 릴리스 갭이지 완료된 수용이 아니다.

---

## 12. 실 시스템 승인 검증 (2026-08-17)

사용자 승인 아래 실제 CachyOS 호스트에서 SPEC §61의 미검증 3항목을 재현했다.
sudo 가 필요한 명령은 전부 사용자가 직접 실행했고, 서브에이전트는 실행하지 않았다.

### 12.1 실행 환경과 사전 스냅샷

CachyOS, Hyprland 0.56.2 실행 중, Quickshell 0.3.0. 시작 시점에 `cachy-omarchy-*`
두 패키지와 `omarchy`/`omarchy-settings` 모두 미설치, 오버레이가 소유할 11개 경로
전부 부재, `~/.config/cachy-omarchy/`·`~/.local/state/omarchy/` 부재,
`~/.config/hypr/hyprland.lua` md5 `60248c3256462f4f75475a1cc70c2eeb`.

### 12.2 실제 `pacman -U` 설치 — 측정됨

`./bin/install-packages --install` 로 두 패키지를 실제 설치했다. 확인 결과:

- 11개 경로 전부 `cachy-omarchy-overlay` 소유(`pacman -Qo`).
- 의존 해석이 `inotify-tools` 하나만 추가로 끌어왔다. 공식 `omarchy`/`omarchy-settings`
  는 요구되지 않았다 — **정적 감사가 아니라 실제 pacman 트랜잭션이 이를 증명한다.**
- 서비스는 `disabled`/`inactive`. `.INSTALL` 스크립트가 없고 `.wants/` 심볼릭도 없어
  **설치만으로는 아무것도 실행되지 않는다.**
- `hyprland.lua` md5 불변. `~/.config/cachy-omarchy/`·`~/.local/state/omarchy/` 부재 유지 —
  **패키지는 사용자 상태를 만들지 않는다**(SPEC §6.6, §38)는 계약이 실측됐다.
- 화면 layer 0개.

CachyOS snapper 훅이 설치 전후 스냅샷(450/451)을 자동 생성했다.

### 12.3 `cachy-omarchy-init` 과 충돌 정책 — 측정됨

설치된 `/usr/bin/cachy-omarchy-init` 를 **사용자의 실제 홈**에 대해 실행했다.

`--dry-run` 은 아무것도 쓰지 않았다(hyprland.lua md5 불변, 두 디렉터리 부재 유지).
실제 실행은 `~/.local/state/omarchy/toggles/bar-off` 와
`~/.config/cachy-omarchy/hypr/bindings.{conf,lua}` 를 만들고, `shell.json` 은 만들지
않았다(M7 의 dead-file 수정이 설치본에 반영됨).

바인딩 주입은 다음을 출력하고 중단했다:

```
warning: 기존 설정이 SUPER+SPACE 를 이미 바인딩한다. 덮어쓰지 않는다. 교체하려면 --force.
```

`hyprland.lua` md5 는 `60248c32…` 그대로였고 관리 블록은 주입되지 않았다.
**SPEC §20 의 "감지·경고하되 조용히 덮어쓰지 않는다"가 사용자의 실제 walker 바인딩
(`hyprland.lua:295`)에 대해 실측됐다.** §9.5 의 "실제 사용자 설정에는 실행하지 않았다"
는 이 절로 대체된다.

### 12.4 rollback — 측정됨

`bump-pkgrel` → `build-packages` → `test-packages` → `install-packages` 로
`cachy-omarchy-shell 4.0.0-2` 를 설치한 뒤 `./bin/rollback` 을 실행했다.

- 이전 쌍이 `~/.local/state/cachy-omarchy/packages/previous-<stamp>/artifacts/` 에
  체크섬과 함께 보존됐다.
- pacman 이 `4.0.0-2 → 4.0.0-1` 다운그레이드를 수행했다.
- `installed-build.manifest` 가 `-1` 쌍으로 되돌아갔고 pending 마커는 남지 않았다.
- `pacman -Qkk` 결과 셸 232파일·오버레이 24파일, **대체 0개**.
- `hyprland.lua` 와 사용자 상태(`bar-off`, 바인딩 사본)는 무손상.
  **rollback 이 무관한 시스템 파일을 복원하지 않는다**(SPEC §36)가 실측됐다.

### 12.5 clean chroot build — 측정됨, 단 의존 해석은 제외

`devtools 1:1.5.1-1` 을 설치하고 `mkarchroot /var/lib/archbuild/coo/root base-devel`
로 chroot(1.3G)를 만든 뒤
`COO_CLEAN_CHROOT_DIR=/var/lib/archbuild/coo ./bin/build-packages --clean` 을 실행했다.
두 패키지 모두 빌드에 성공했다.

- chroot 는 **Arch 저장소**로 만들었다. CachyOS 특화 패키지에 의존하지 않는다는 성질을
  보존하기 위해서다.
- clean 빌드본과 호스트 빌드본의 **파일 목록이 완전히 동일**하고 권한·소유권 집합
  (`-rw-r--r--`/`-rwxr-xr-x`/`drwxr-xr-x`, uid 0)도 같다.
- 셸 패키징 중 `libfakeroot internal error: payload not recognized!` 가 출력됐다.
  호스트와 chroot 의 fakeroot/glibc 버전 차이에서 오는 잡음이며, 위 비교로 **산출물에
  영향이 없음을 확인**했다.
- §11.2 의 "실제 clean chroot build 는 미검증" 은 이 절로 대체된다.

**이 실행이 검증하지 않은 것 — `--nodeps`.** `bin/build-packages` 는
`makechrootpkg -r … -- --nodeps` 를 호출하므로 출력에 `Skipping dependency checks.` 가
두 번 찍힌다. 따라서 **선언된 `depends`/`makedepends` 의 충분성은 이 경로로 확인되지
않는다.** `cachy-omarchy-overlay` 가 저장소에 없는 로컬 패키지 `cachy-omarchy-shell` 에
의존하기 때문에 불가피한 선택이며, 제대로 풀려면 로컬 저장소 구성이 필요하다
(SPEC §64 — v0.1 범위 밖). 의존 선언의 실제 근거는 clean build 가 아니라 §12.2 의
실제 `pacman -U` 트랜잭션이다.

### 12.6 이 검증이 드러낸 결함 2건

둘 다 M7 v0.1 수용 심사를 통과한 상태였다. 심사가 부실했다기보다 **실제로 실행하지
않으면 드러나지 않는 종류**였고, 그것이 §61 이 이 항목들을 미검증으로 남긴 이유다.

| 커밋 | 결함 | 회귀 가드 |
| --- | --- | --- |
| `2b3da38` | `bin/install-packages`·`bin/rollback` 을 문서대로 실행할 수 없었다. `sudo` 로 전체를 감싸면 `state_dir` 이 `/root/.local/state/…` 로 해석돼 실패하고, `COO_PACMAN_BIN="sudo pacman"` 은 단일 단어 인용 때문에 동작하지 않았다. SPEC §37 이 규정한 설치 경로가 막혀 있었다. | 가짜 `sudo` 를 샌드박스 PATH 에 놓고 구성된 argv 가 `sudo pacman -U …` 인지 단언. 픽스 이전 코드는 4개 실패 |
| `4311a42` | 테스트 스위트가 SPEC §49 U04(`pkgrel` 범프)를 견디지 못했다. 지원되는 조작이 `test_update_pipeline.sh` 의 11개 단언을 깨뜨려 `test-packages` 가 fail-closed 되고 rollback 검증 경로 전체가 막혔다 | 픽스처 `pkgrel` 을 센티넬 5 로 고정. 하드코딩된 `-1-` 이 재발하면 어느 값에서든 실패 |

수정 후 두 결함 모두 실제 시스템에서 해소를 확인했다 — 래퍼 없이
`./bin/install-packages --install` 이 동작하고, 전체 스위트는 `pkgrel` 1·2 양쪽에서
31/31 통과한다.

### 12.7 여전히 미검증

이 세션은 **셸을 서비스로 기동하지 않았다.** 따라서 다음은 그대로 미검증이다:

- `SUPER+SPACE` / `SUPER+K` 라이브 동작. 관리 블록이 충돌로 주입되지 않았으므로
  바인딩 자체가 존재하지 않는다. 검증하려면 `--force` 와 사용자 승인이 필요하다.
- 라이브 Quickshell 프로세스와 세션 IPC.
- 기존 Waybar·notification daemon·lock 화면과의 **공존**. 패키지가 해당 경로를 소유하지
  않는다는 것은 측정됐지만(§11.3 R08–R10), 동시 실행은 관측하지 않았다.
- `graphical-session.target` 자동 기동(§9.4 — 타깃이 여전히 inactive).
- `COO_RUN_LIVE=1` 키 주입.

**이후 절의 실측으로 대체된 항목.** 이 파일의 관례대로 원문은 보존하고 대체 절을
가리킨다. SUPER+SPACE/SUPER+K 라이브 동작과 라이브 Quickshell 프로세스·세션
IPC 는 §13.1 에서, 알림 데몬(mako)과의 공존은 §13.2·§14.1 에서 측정됐다.
자동 기동은 기동 모델이 Hyprland autostart 로 바뀌며(§16) `hyprland.start` 발화가
부모=Hyprland 로 실측됐다(§16.1) — `graphical-session.target` pull-in 은 새
모델의 전제가 아니게 됐다. 이 절 기준으로 **여전히 미검증으로 남는 것은
Waybar·lock 화면 공존과 `COO_RUN_LIVE=1` 키 주입뿐**이다(§16.7).

---

## 13. 라이브 세션 승인 검증 (2026-08-17)

사용자가 `bar-off` 토글을 삭제하고 `cachy-omarchy-bindings --force` 로 관리 블록을
주입한 뒤, `cachy-omarchy-shell --run` 을 포그라운드로 기동해 직접 조작했다.
서비스를 enable 하지 않았고 종료는 Ctrl-C 였다.

### 13.1 관측된 사실

셸은 **설치 경로**에서 기동했다 —
`quickshell -n -p /usr/share/cachy-omarchy/upstream/shell` (pid 3041286),
`INFO: Configuration Loaded`, 무중단 8분 32초.

| 항목 | 결과 |
| --- | --- |
| IPC ping | `ok` |
| `SUPER+SPACE` → 원본 Quattro 런처 | 열림 |
| `Escape` | 닫힘 |
| 앱 실행 | 성공 |
| `SUPER+K` → 키바인딩 UI | 열림 |
| QML 오류 / `ERROR` 레벨 | **0건** |

레이어 구성:

```
omarchy-bar     xywh: 0 0 3072 26     pid 3041286   (우리 셸)
notifications   xywh: 2752 26 320 63  pid 652539    (사용자 mako)
```

### 13.2 기존 데스크톱 구성요소와의 공존 — 측정됨

사용자의 `mako`(pid 652539)가 **살아남았고**, 우리 바가 상단 26px 를 점유하자
`y=0` 에서 `y=26` 으로 재배치됐다. 두 layer-shell 클라이언트가 정상 협상한 것이며,
**우리 셸이 알림 데몬을 대체하지 않았다**는 직접 증거다(SPEC §61 R09). 지금까지
R08–R10 은 "패키지가 해당 경로를 소유하지 않는다"는 정적 증거뿐이었고, 동시 실행
관측은 이것이 처음이다.

### 13.3 compat PATH 격리 — 측정됨

사용자가 `uwsm-app` 을 찾지 못한다고 보고했다. **이는 설계대로다.**

```
사용자 셸        : uwsm-app 없음
shim            : /usr/lib/cachy-omarchy/compat/bin/uwsm-app (root:root 755)
셸 프로세스 PATH : /usr/lib/cachy-omarchy/compat/bin  ← 첫 항목
```

`/proc/3041286/environ` 을 직접 읽어 확인했다. compat 디렉터리는 **셸 프로세스에만**
붙고 사용자 일반 환경에는 없다 — SPEC §44(‘/usr/bin 에 가짜 omarchy-* 대량 설치 금지’)
와 §45(환경 격리)가 동시에 성립한다. 이 호스트에 `uwsm` 이 없으므로 앱이 실행됐다는
사실 자체가 **shim 이 실제로 사용됐다**는 증거다. M3 이래 `WRAPPER` 로 분류만 하고
라이브 검증은 못 했던 경로다.

### 13.4 관리 블록 — 측정됨

`--force` 주입 결과가 `~/.config/hypr/hyprland.lua:391-393` 에 다음과 같이 들어갔다:

```lua
-- >>> cachy-omarchy >>>
pcall(dofile, "/home/<user>/.config/cachy-omarchy/hypr/bindings.lua")
-- <<< cachy-omarchy <<<
```

M2 에서 확립한 두 방어가 사용자의 실제 설정에서 동작한다 — Lua 주석 마커 `--`
(`#` 였다면 길이 연산자로 해석돼 이 파일 전체가 죽는다) 와 `pcall` 가드
(오버레이 디렉터리가 사라져도 사용자 설정이 깨지지 않는다).

Hyprland 가 설정을 다시 읽었음이 바인딩 수로 확인된다 — 48 → 49 개, `SUPER+K` 가
신규 생성, `SUPER+space` 는 **1개**(`hl.unbind` 후 재바인딩이므로 중복 없음).

### 13.5 우리 결함이 아닌 것 두 가지

**메뉴 아이콘 누락 WARN.** `Cannot open: file:///home/<user>/.local/share/omakub/
applications/icons/*.png` 가 반복된다. 업스트림 셸 트리에 `omakub` 참조는 **0건**이며,
사용자 자신의 `.desktop` 3개(`Activity`·`About`·`Docker`)가 존재하지 않는 디렉터리를
가리킨다. 메뉴는 사용자 `.desktop` 을 올바르게 읽고 있다.

**`listPlugins` 의 `omarchy.menu enabled=false`.** 런처가 실제로 열리는데도 이 값이
`false` 다. `shell.qml:952-976` 의 bar-widget 분기가 `inBar(id)` 를 반환하기 때문이며,
`kinds` 에 `bar-widget` 이 있는 플러그인에서 이 필드는 '바에 위젯으로 올라가 있는가'
를 뜻한다. 우리 기본값이 바 레이아웃을 비웠으므로 `false` 가 맞고, 메뉴는
`keepLoaded: true` 로 살아 있다. M5 에서 논증으로만 확인했던 것이 **런처가 열리는
것으로 실증됐다**.

### 13.6 이 세션이 여전히 검증하지 않은 것

- **systemd user service 로서의 기동.** 포그라운드 `--run` 이었고 서비스는
  `disabled`/`inactive` 그대로다. `Restart=on-failure` 복구(R07)와
  `graphical-session.target` 자동 기동(§9.4)은 미검증이다.
- **`bar-off` 가 있을 때의 동작.** 사용자가 토글을 삭제한 상태로 관측했으므로 바가
  떴다. 토글이 있을 때 바가 숨는지는 §12.3 이후 라이브로 재확인하지 않았다.
- **lock 화면 공존.** `omarchy.lock` 은 `disabledPlugins` 로 꺼져 있으나 hyprlock 등과
  동시 동작은 관측하지 않았다.
- `COO_RUN_LIVE=1` 키 주입 자동화 테스트.

---

## 14. systemd user service 검증 (2026-08-17)

> **참고:** 이 측정은 구 systemd 유닛 모델 기반이다; 현재 기동 모델은 §16/§17(Hyprland autostart)을 본다.

§13 의 포그라운드 세션을 종료한 뒤, 설치된 유닛으로 서비스를 기동해 R07 을 검증했다.
**`enable` 은 하지 않았다** — `start` 만으로 R07 이 성립하고, 이 호스트에서
`graphical-session.target` 이 inactive 라 enable 해도 자동 기동은 관측할 수 없기
때문이다. 지속적 변경을 만들지 않는 쪽을 택했다.

### 14.1 기동 — 측정됨

`systemctl --user start cachy-omarchy-shell.service` 가 exit 0 으로 성공했다.
유닛의 `ConditionEnvironment=WAYLAND_DISPLAY` 는 systemd 사용자 환경에
`WAYLAND_DISPLAY=wayland-1` 이 있어 충족됐다.

**`MainPID` 가 곧 `quickshell` 이다.** `MainPID=3104997` 이고
`ps -o comm= -p 3104997` 이 `quickshell` 을 반환했다 — 래퍼의
`exec env … systemd-cat -- quickshell` 체인이 PID 를 보존하므로 systemd 가 셸
프로세스를 직접 감독한다. **이것이 R07 의 전제다**: systemd 가 감독하는 대상이
래퍼 껍데기였다면 셸이 죽어도 재시작이 걸리지 않는다.

IPC ping `ok`, `omarchy-bar` 레이어 생성, 사용자 mako 는 `y=26` 으로 공존.

### 14.2 R07 `Restart=on-failure` — 측정됨

`MainPID` 를 `kill -KILL` 한 뒤 저널이 전 과정을 기록했다:

```
08:45:41  Started Cachy Omarchy Quattro Shell.
08:45:58  Main process exited, code=killed, status=9/KILL
08:45:58  Failed with result 'signal'.
08:45:59  Scheduled restart job, restart counter is at 1.
08:45:59  Started Cachy Omarchy Quattro Shell.
```

| 항목 | 값 |
| --- | --- |
| 복구 시간 | 2초 (`RestartSec=1` + 기동) |
| MainPID | `3104997` → `3105903` |
| `NRestarts` | 1 |
| 복구 후 IPC ping | `ok` |
| 복구 후 바 레이어 | 재생성 1개 |

### 14.3 정상 종료는 재시작하지 않는다 — 측정됨

`systemctl --user stop` 후 `active=inactive`, `NRestarts` 는 1 → 0 으로 리셋,
`quickshell` 프로세스 부재. **`Restart=on-failure` 가 의도대로 실패에만 반응하고
정상 종료에는 반응하지 않는다.** 재시작이 도는 것만 확인하면 "정상 종료 후에도
계속 되살아나는" 반대 결함을 놓친다.

종료 시 바 레이어가 사라지고 사용자 mako 가 `y=26` → **`y=0` 으로 복귀**했다 —
바가 예약했던 26px 가 반환된 것이며, exclusive zone 을 정상적으로 해제한다는 증거다.

### 14.4 `bar-off` 가 있을 때 — 측정됨 (2026-08-17)

§13 은 사용자가 토글을 삭제한 상태로 관측했으므로 바가 떴다. 토글을 되돌려
같은 서비스 경로로 재확인했다:

```
omarchy-bar   xywh: 0 -26 3072 26     ← y = -26
DP-1          reserved=[0,0,0,0]
IPC ping      ok
```

**바 레이어는 사라지지 않는다.** 여전히 매핑돼 있고 `y=-26` 으로 화면 위쪽 밖에
주차되며 exclusive zone 이 0 이다. 사용자에게 보이는 결과는 "바 없음"으로 같지만
메커니즘이 다르며, 테스트가 단언하는 것도 이 기하학적 성질이다 — "레이어가
존재하지 않는다" 로 단언했다면 이 구성에서 실패했을 것이다.

M5 Task 5 가 샌드박스에서 관측했던 동작이 실제 설치본에서 동일하게 재현됐다.
이는 §9.3 의 정책 서술을 뒷받침한다: 패키지 기본값은 내장 바를 끄지 못하며
(`shell.qml:975` `canDisable: !isBarOption`), `cachy-omarchy-init` 이 만드는
사용자 상태 파일만이 이 결과를 만든다.

### 14.5 이 절이 검증하지 않은 것

- **자동 기동.** `enable` 하지 않았고 `graphical-session.target` 은 여전히 inactive 다.
  `WantedBy=graphical-session.target` 이 실제 로그인에서 pull-in 되는지는 미검증이다(§9.4).
- **`StartLimitBurst` 도달 시 동작.** 재시작을 1회만 유발했다. systemd 기본
  (10초 내 5회)을 초과하면 유닛이 failed 로 고정되는데, 그 경계는 관측하지 않았다.
- 서비스는 검증 후 `stop` 했고 `disabled` 상태로 남겼다. `~/.config/systemd/user/`
  에 `.wants` 심볼릭이 생기지 않았음을 확인했다.

---

## 15. uwsm 도입과 앱 스코프 격리 (2026-08-17)

`graphical-session.target` 이 inactive 인 원인을 진단하다 `uwsm` 을 설치하게 됐고,
그 결과 compat shim 이 진짜 도구를 가리는 문제가 드러나 함께 수정했다.

### 15.1 `graphical-session.target` 이 inactive 인 이유 — 진단됨

이 호스트는 GDM 에서 `/usr/share/wayland-sessions/hyprland.desktop`
(`Exec=/usr/bin/start-hyprland`) 으로 로그인한다. `start-hyprland` 는 `hyprland`
패키지가 제공하는 **ELF 바이너리**이며 `strings` 에 `systemd`·`graphical-session`·
`import-environment` 가 하나도 없다 — 컴포지터만 띄우고 systemd 세션 타깃을
건드리지 않는다.

`systemctl --user list-dependencies graphical-session.target --reverse` 의 결과는
**`gnome-session.target` 하나뿐**이다. Hyprland 쪽에서 이 타깃을 원하는 유닛이 없고,
따라서 유닛의 `WantedBy=graphical-session.target` 은 발동할 계기가 없다.

환경 변수 자체는 정상이다 — systemd 사용자 환경에 `WAYLAND_DISPLAY=wayland-1`,
`XDG_CURRENT_DESKTOP=Hyprland` 가 있어 `ConditionEnvironment` 는 충족된다.
**문제는 조건이 아니라 트리거다.**

GDM 에는 `Exec=uwsm start -e -D Hyprland hyprland.desktop` 세션 엔트리도 있으나
`uwsm` 미설치로 사용할 수 없었다. `uwsm` 은 이 타깃을 올리는 것이 존재 이유다.

### 15.2 compat shim 이 진짜 `uwsm-app` 을 가리던 문제 — 수정됨

`uwsm 0.26.6-1` 이 설치되자 `/usr/bin/uwsm-app` 이 생겼다. 그런데 우리 compat
디렉터리가 셸 프로세스 PATH 의 **첫 항목**이므로(§13.3), 구 shim 이 계속 이기고
`exec "$@"` 로 스코프 배치를 버렸다. **uwsm 을 설치하고도 그 이점을 못 받는 상태.**

수정(`24ff123`)은 shim 을 투명하게 만들었다 — 자기 위치를 제외하고 다음
`uwsm-app` 을 해석해 인자를 그대로(선행 `--` 포함) 넘기고, 없으면 기존 폴백을
유지한다. 패키징 내용 변경이므로 오버레이를 `0.1.1-1` 로 릴리스했다(`6ae2fe6`).

### 15.3 앱 스코프 격리 — 측정됨

사용자가 `SUPER+SPACE` 런처로 계산기를 실행한 뒤 cgroup 을 읽었다:

```
계산기: app.slice/app-graphical.slice/app-Hyprland-gtk\x2dlaunch-f26d135d.scope
셸    : app.slice/cachy-omarchy-shell.service
```

앱이 **`app-graphical.slice` 아래 자기 스코프**에 들어갔고 셸 서비스 밖이다.
스코프 이름 `app-Hyprland-gtk\x2dlaunch-…` 는 진짜 `uwsm-app` 이 만든 것으로,
shim 이 위임했다는 직접 증거다. 구 shim 이었다면 `exec` 만 해서 계산기가
`cachy-omarchy-shell.service` 안에 남았을 것이다.

업스트림 `shell/services/AppLibrary.qml:81` 의 의도가 실현됐다 —
"apps do not inherit wayland-wm@.service".

**§14.2 의 R07 과 짝을 이룬다.** `Restart=on-failure` 복구가 2초 만에 도는 것을
확인했는데, 앱이 셸 서비스 안에 갇혀 있었다면 그 복구가 사용자 앱을 함께 죽인다.
스코프 격리가 그것을 막는다. 두 관측은 따로 보면 절반만 의미가 있다.

### 15.4 측정 방법에 관한 주의

첫 시도에서 컨트롤러가 터미널에서 `uwsm-app -- gtk-launch …` 를 직접 실행해
검증하려 했으나 **무효였다** — 그 경우 앱이 터미널의 스코프
(`app-ghostty-surface-transient-…`)를 상속하므로 셸과 무관하다. 이 성질은
**셸이 앱을 띄울 때만** 관측된다. 호출 맥락이 측정의 일부다.

### 15.5 아직 하지 않은 것

`uwsm` 은 설치했으나 **uwsm 세션으로 로그인하지는 않았다.** 따라서
`graphical-session.target` 은 여전히 inactive 이고 자동 기동은 미검증이다.
전환하려면 GDM 에서 uwsm 계열 세션을 선택해 재로그인해야 하며, 기존
`hyprland.desktop` 엔트리가 남아 있어 되돌릴 수 있다.

### 15.6 검증 환경 드리프트 — 이 호스트는 더 이상 "uwsm 없는 CachyOS"의 대표가 아니다

`uwsm` 을 설치한 것은 `graphical-session.target` 진단(§15.1) 때문이었는데, 그
부수 효과로 **이 호스트는 원래 타깃 환경과 달라졌다.** 이 프로젝트의 원래
전제는 uwsm 없는 CachyOS 였고 — shim 이 존재하는 이유가 그거고, M3 부터
`uwsm-app` 을 WRAPPER 등급으로 분류해온 근거이기도 하다. 이제 이 호스트에서는
shim 의 **Tier 1(fallback, `--` 벗기고 exec)** 이 라이브에서 발동하지 않는다.
Tier 1 은 통제된 PATH 테스트(`test_uwsm_app_shim.sh` path B,
`test_uwsm_scope.sh` 음성 대조)에서만 실측된다.

이 드리프트가 실제 결함을 숨길 뻔했다. uwsm 이 설치되기 전까지는 shim 의
폴백이 항상 발동했고, 그 폴백은 앱을 `cachy-omarchy-shell.service` cgroup 에
그대로 남겨 §14.2 의 `Restart=on-failure` 복구가 사용자 앱을 함께 죽이는
상태였다. 이 호스트에서 Tier 1 이 항상 발동하던 시절에는 그 degraded 상태가
드러나지 않았다 — **검증 환경이 목표 환경에서 멀어지면 이런 게 생긴다.**

이를 막기 위해 `test_uwsm_scope.sh` 를 추가했다. 이 테스트는 PATH 를 통제해
실제 `uwsm-app` 을 넣어 Tier 2 를 강제하고, 띄운 프로세스의
`/proc/<pid>/cgroup` 을 읽어 `app-graphical.slice/….scope` 가 실제로 생겼는지
확인한다 — "호출했다"가 아니라 "효과가 있었다"를 본다. PATH 를 통제하지
않으면 uwsm 없는 머신에서 Tier 1 이 발동해도 "대상이 실행됐다"만 보고 통과해
버리므로, 실제 `uwsm-app` 이 없으면 **skip** 한다(Tier 1 을 조용히 검증하지
않는다). uwsm 없는 머신이 원래 타깃이므로, 그 머신에서 이 테스트가 skip 되는
것은 정상이다 — `bin/test-packages` 허용 목록에 그 skip 메시지가 등록돼 있다.

## 16. Hyprland autostart 기동 실측 (2026-08-17)

이 절은 셸을 systemd user service 가 아니라 **Hyprland autostart** 로
띄우는 모델(커밋 4c5731b `refactor: drop systemd shell unit, package Hyprland
autostart instead`, b093c06 `feat: launch Quattro shell on hyprland.start
autostart`)를 라이브로 잰 것이다. 6e0f6f5 가 `hyprland.start` 단발화 트리거를
"live-unverified" 로 남겨둔 caveat 가 이번 재로그인으로 해소됐다.

### 16.1 기동 출처 — autostart 가 맞다 (결정적 증거)

재로그인 후 라이브 셸 프로세스:

```
PID 3724905  quickshell -n -p /usr/share/cachy-omarchy/upstream/shell
  PPID 3724848  Hyprland --watchdog-fd 4
```

부모가 곧 `Hyprland` 자신이다. 즉 터미널에서 `cachy-omarchy-shell --run` 을
수동으로 친 게 아니라, **Hyprland 가 `hyprland.start` 에서 `exec-once` 로
`cachy-omarchy-shell --run` 을 실행한 결과**다. 이것이 autostart 기동의
직접 증거다. `WAYLAND_DISPLAY=wayland-1` 소켓(11:59 생성) 시점과 일치한다.

### 16.2 런타임 환경 (environ, 실설치 경로)

`/proc/3724905/environ`:

- `OMARCHY_PATH=/usr/share/cachy-omarchy/upstream` — 실 pacman 설치 경로(샌드박스 아님).
- `PATH=/usr/lib/cachy-omarchy/compat/bin:…` — compat bin 이 셸 PATH 선행. §45 PATH 격리가 autostart 세션에서도 그대로 유지됨(§13.3 과 동일).
- `QT_QPA_PLATFORM=wayland`, `QT_IM_MODULE=fcitx`, `XDG_RUNTIME_DIR=/run/user/1000`.
- `COO_RUN_LIVE` 없음 — 깨끗한 자동 기동(테스트 강제 키 아님).

### 16.3 QML 에러 0

`journalctl --user -t cachy-omarchy-shell` 에서 PID 3724905 의 항목은 Qt
wayland textinput `zwp_text_input_v3_leave` `WARN` (surface 0x0 leave —
양성, §13 시절과 동종) 만 있고 **QML 에러가 없다.** `shell.qml` 이
wayland-1 에 정상 로드됐다. (동일 저널에 보이는 `/tmp/coo-test-*` 경로의
INFO 항목들은 테스트 스위트가 만든 샌드박스 셸이지 라이브 셸이 아니다.)

### 16.4 런처와 바 — 동작 확인

- `hyprctl binds` 에 `key: space` 활성. 사용자가 **SUPER+SPACE 로 원본 Quattro
  런처를 열어 동작을 확인**했다(R04/R05, autostart 세션에서 재확정).
- `hyprctl layers`: `omarchy-bar` 레이어 `xywh: 0 -26 3072 26, a:1, pid:
  3724905` — `bar-off` 억제 상태로 `y=-26` 주차, `reserved=[0,0,0,0]`.
  §14.4/7ec6fda 측정과 동일. (사용자가 §13 이후 `bar-off` 를 유지 중.)

### 16.5 이 절이 검증하는 §61 항목

- **"Long-running shell starts as user"** — 측정됨. 부모=Hyprland 가 autostart
  기동을 증명한다. 이 항목의 systemd-service 해석(§14.1)은 이제 역사 기록.

### 16.6 모델 전환의 비용 — R07 자동 복구는 더 안 붙는다 (솔직한 한계)

**주의:** systemd user unit 을 제거(4c5731b)하면서 §14.2 의
`Restart=on-failure` 자동 복구(R07)도 함께 사라졌다. 새 모델에서:

- `hyprland.start` `exec-once` 는 로그인 한 번 발화한다. 셸이 그 후 죽으면
  자동으로 다시 뜨지 않는다.
- 수동 복구는 `cachy-omarchy-shell --restart`(1a3ac95, KILL 후 detached
  relaunch; dd31b59 로 reap 대기 강화)로만 가능하다.
- 즉 **R07 "restarting service recovers" 의 자동 복구 반은 더 이상
  shipped feature 가 아니다.** §14.2/§14.3 측정은 제거된 기능의 기록이다.

이는 §61 어느 항목의 명시적 요구사항도 아니지만(R07 자동 복구는 §60 M7
신뢰성 작업에서 도입된 것이지 §61 이 아님), 릴리스 노트에 드러나야 할
동작 변화다. 자동 기동(이전엔 `enable`+graphical-session.target pull-in
이 inactive 로 미검증)을 autostart 로 달성한 대가으로서 받은 trade-off 다.

### 16.7 여전히 미검증

- R08 Waybar 라이브 공존(호스트는 mako).
- 잠금화면 공존(§61 #18, hyprlock 미관측).
- `COO_RUN_LIVE=1` 자동화 키 주입 테스트(R04/R05 자동화).
- 셸 크래시 후 자동 재기동은 이 모델에 **존재하지 않는다**(위 16.6).

---

## 17. M8 — 업스트림 기본 바 라이브 실측 (2026-08-17)

v0.2.0 의 억제 해제(원칙 0)를 빌드된 아티팩트로 실제 검증했다. `sudo` 없이,
격리 트리 + 격리 HOME 으로 사용자 세션 위에 띄웠다.

### 17.1 절차

```bash
tmp=$(mktemp -d); ovl=$(mktemp -d); H=$(mktemp -d)
source lib/runtime.sh
coo_extract_pkg "$tmp"; coo_extract_overlay "$ovl"
UP="$tmp/usr/share/cachy-omarchy/upstream"
env HOME="$H" COO_OMARCHY_PATH="$UP" \
    COO_COMPAT_BIN="$ovl/usr/lib/cachy-omarchy/compat/bin" \
    "$ovl/usr/bin/cachy-omarchy-shell" --run &
```

### 17.2 측정 — 바가 y=0 에 실제로 그려진다

```console
$ hyprctl -j layers | jq -r '...'
level 0: omarchy-background xywh 0 0 3072 1728 pid 4073942   # 격리 인스턴스
level 2: omarchy-bar        xywh 0 0 3072 26   pid 4073942   # 격리 인스턴스
level 2: omarchy-bar        xywh 0 -26 3072 26 pid 3910280   # 기존 셸(bar-off)
level 2: notifications      xywh 2752 26 320 63 pid 3949882  # mako
```

- **`omarchy-bar` 가 `y=0` 에 매핑됐다** — 패키지 기본값만으로 바가 뜬다. 패치 0건.
- `omarchy-background` 가 level 0(모든 창 아래) 에 전체화면으로 깔린다.
- 대조: 같은 화면의 기존 셸(pid 3910280)은 `bar-off` 때문에 `y=-26` 에 주차돼
  있다. 같은 패키지, 다른 사용자 상태 — 토글이 바를 없애는 게 아니라 옮긴다는
  §3 의 발견이 두 인스턴스로 나란히 재현됐다.

### 17.3 측정 — helper 격차 0건

```console
$ grep -c 'binary could not be found' shell.journal
0
$ grep -iE 'error|exception' shell.journal
(없음)
```

M8 평가 시점의 helper 미해결 7건이 **전부 닫혔다.** Tier A·B 13개 스테이징 +
셸 프로세스 PATH 에 `$OMARCHY_PATH/bin` 연결 + compat shim 1개
(`omarchy-update-available`) 로 해결했고, 업스트림 본문 패치는 0건이다.
Tier D 밝기 helper 는 `omarchy-monitor-state` 내부 가드에 걸려 이 grep 에 잡히지
않는다(잡히면 가드가 깨진 것).

### 17.4 🔴 정정 — mako 는 인계되지 않는다

기동 로그의 유일한 WARN 2줄:

```console
WARN quickshell.service.notifications: Could not register notification server at
  org.freedesktop.Notifications, presumably because one is already registered.
WARN quickshell.service.notifications: Registration will be attempted again if
  the active service is unregistered.
$ busctl --user status org.freedesktop.Notifications
PID=3949882  Comm=mako
```

**M8 평가 문서의 "mako 인계는 D-Bus 이름 회수로 1초 내 성립" 은 이 조건에서
재현되지 않았다.** 셸은 이미 주인이 있는 이름을 **뺏지 않는다.**

추가 측정으로 밀어내기 가능 여부를 확인했다. 셸이 뜬 상태에서:

```console
$ busctl --user call … ListQueuedOwners s org.freedesktop.Notifications
as 1 ":1.2615"        # mako 하나뿐 — 셸은 대기열에도 없다
```

즉 셸은 `DBUS_NAME_FLAG_REPLACE_EXISTING` 를 요청하지도, 대기열에 서지도 않고,
`NameOwnerChanged` 를 지켜보다 재시도한다(WARN 문구 그대로). D-Bus 에서
밀어내기가 성립하려면 **요청자가 REPLACE_EXISTING 을 보내고 동시에 현 소유자가
ALLOW_REPLACEMENT 로 이름을 잡았어야** 하는데, 우리 쪽이 애초에 요청하지 않는다.
바꾸려면 omarchy 가 아니라 **quickshell 본체**를 패치해야 한다 — 우리 패치 예산
바깥이다.

### 17.4.1 그래서 누가 이기는가 — 순서 문제이지 밀어내기 문제가 아니다

```console
$ systemctl --user show mako.service -p Type,UnitFileState
Type=dbus
UnitFileState=disabled
$ journalctl --user -u mako.service --since today | grep -c Started
6      # 10:19, 10:22, 10:30, 12:02, 13:13, 13:38 — 뜨고 내려가기를 반복
```

**mako 는 상주 데몬이 아니다.** unit 은 `disabled` 이고 `Type=dbus` 라, 이름의
주인이 없는 상태에서 알림이 도착할 때 D-Bus 가 활성화시킨다. 오늘 하루에만 6번
새로 떴다. 즉 mako 에게 영구적 선점권은 없다.

따라서 실질적 규칙은 이렇다:

- **셸이 이름을 먼저 잡으면 mako 는 활성화조차 되지 않는다.** 밀어낼 필요가 없다.
- 반대로 이름의 주인이 이미 mako 면 셸은 물러난다. §17.2 의 측정이 바로 이
  경우였다 — 격리 인스턴스가 **나중에** 떴기 때문이다.
- 우리 코드는 어느 쪽에서도 mako 를 죽이거나 mask 하지 않는다. 패키지에
  `.INSTALL` 스크립트 자체가 없고(`test_runtime_reliability` 의 R08 이 고정),
  설치는 파일만 놓는다 — 설치 시점에 D-Bus 는 관여하지 않는다.

> **✅ 검증됨 (2026-08-17 14:20 재로그인).** 위 세 줄은 원래 unit 설정과 활성화
> 기록에서 끌어낸 추론이었으나, 0.2.0 이 설치된 상태로 세션을 새로 시작해 직접
> 측정했다 — 셸이 이름을 먼저 잡았고 mako 는 활성화되지 않았다. 출력은 §17.7.

### 17.5 정리 — 잔여물 없음

```console
$ kill 4073942 && sleep 2
$ hyprctl -j layers | jq '[... | select(.pid == 4073942)] | length'
0
```

우리 PID 의 표면이 하나도 남지 않았고, 사용자의 기존 셸(3910280)과 mako(3949882)
는 그대로다. 되돌리기는 프로세스 종료 하나뿐이다.

### 17.6 Waybar 공존 — §61 미검증 항목 해소 (2026-08-17, waybar 설치 후)

M8 평가 시점에 waybar 는 이 호스트에 없었고, 그래서 §61 의 "Existing Waybar is
preserved" 는 v0.1 부터 계속 미검증으로 남아 있었다. 사용자가 `waybar 0.15.0-2.1`
을 설치해 처음으로 측정 가능해졌다.

**baseline** (셸의 바는 `bar-off` 로 주차, waybar 미실행):

```console
$ hyprctl -j monitors | jq -c '.[] | {name, reserved}'
{"name":"DP-1","reserved":[0,0,0,0]}
```

**waybar 단독:**

```console
level 2: waybar xywh 0 0 3072 36 pid 4180851
{"name":"DP-1","reserved":[0,36,0,0]}
```

**waybar + omarchy.bar 동시** (격리 HOME 에 `bar-off` 없음 = 바가 보이는 기본 상태):

```console
level 2: waybar     xywh 0  0 3072 36 pid 4180851
level 2: omarchy-bar xywh 0 36 3072 26 pid 4181106   # ← waybar 아래에 쌓인다
level 0: omarchy-background xywh 0 0 3072 1728
{"name":"DP-1","reserved":[0,62,0,0]}
```

**결과 — 겹치지 않는다.** layer-shell 앵커링이 exclusive zone 을 누적 적용해
`omarchy-bar` 를 `y=36`, 즉 waybar **바로 아래**에 배치한다. 가림도 없고 z-order
싸움도 없다. 비용은 화면 세로 `36 → 62px` 예약뿐이다.

**쌓이는 순서는 고정이 아니다 — 먼저 매핑한 쪽이 위를 가진다.** 같은 날 사용자가
실제 홈의 `bar-off` 토글을 지워 라이브 셸의 바가 켜졌을 때는 반대로 나왔다:

```console
level 2: omarchy-bar xywh 0  0 3072 26 pid 3910280   # 이번엔 셸이 위
level 2: waybar      xywh 0 26 3072 36 pid 4180851
```

격리 실험에서는 waybar 가 먼저 떠 있었고, 이 경우엔 셸이 먼저였다. 어느 쪽이든
결론은 같다 — 겹치지 않고 쌓이며, 총 예약은 62px 다. 위치를 고정하고 싶으면
그건 사용자가 각 바의 앵커/레이어 설정으로 정할 일이지 우리가 강제할 것이 아니다.

**waybar 는 살아남았다.** 우리 셸을 띄우는 동안에도 종료 후에도 pid 4180851 이
그대로다. 우리 코드는 waybar 를 중지·mask·제거하지 않는다 (R08). 우리 셸을
죽이자 예약은 `62 → 36` 으로 되돌아갔다 — 되돌리기는 프로세스 종료 하나.

> **🔴 SPEC §4.3 문언 정정.** v0.2.0 개정에서 "바는 두 개가 나란히 있으면 단순
> 중복이 아니라 사용 불가라서 Waybar 만 비수정 목록에 남긴다" 고 적었는데, 그
> 근거는 **추론이었고 측정에서 틀렸다.** 두 바는 깔끔하게 쌓이며 결과는 정확히
> "단순 중복" 이다. Waybar 를 목록에 남기는 이유는 사용 불가라서가 아니라,
> **세로 공간을 두 번 먹는 것이 사용자가 원한 결과가 아닐 가능성이 높기 때문**
> 이다 — 그건 감지해서 알릴 일이지 우리가 결정할 일이 아니다 (§66).

### 17.7 인계 항목 해소 — 셸이 알림 이름을 먼저 잡는다 (2026-08-17 14:20 재로그인)

§17.4.1 의 "셸이 이름을 먼저 잡으면 mako 는 활성화되지 않는다" 를 **관측으로
승격한다.** 0.2.0(overlay) + 4.0.0-3(shell) 이 설치된 상태로 로그아웃 후 새
세션을 시작해, 알림이 도착하기 전에 잰 결과다. 셸 PID 는 22315, 기동 14:20:07.

**1) 알림 이름의 주인은 우리 셸이다.**

```console
$ busctl --user call … GetNameOwner s org.freedesktop.Notifications
s ":1.2748"
$ busctl --user call … GetConnectionUnixProcessID s ":1.2748"
u 22315
$ ps -p 22315 -o args=
quickshell -n -p /usr/share/cachy-omarchy/upstream/shell
```

**2) mako 는 이 세션에서 한 번도 뜨지 않았다.**

```console
$ systemctl --user is-active mako.service     # exit 3
inactive
$ systemctl --user is-enabled mako.service
disabled
$ journalctl --user -u mako.service --since "2026-08-17 14:20:00"
-- No entries --
```

부팅이 이어지고 있어 `-b` 는 이전 세션(마지막 기동 13:38:52)까지 포함한다 —
그래서 셸 기동 시각으로 창을 잘랐다. **재로그인 이후 기동 기록은 0건이다.**

**3) 셸 로그에 등록 실패 WARN 이 없다.**

```console
$ journalctl --user -t cachy-omarchy-shell --since "2026-08-17 14:20:00" \
    | grep -iE "notif|warn|error"
WARN: Could not load icon "input-keyboard-symbolic" …   # ×4, 아이콘 테마 문제
WARN qt.svg.draw: The requested buffer size is too big, ignoring
WARN qt.svg: <use> element m in wrong context!
```

`Could not register notification server` 가 없다 — §17.4 에서 나왔던 그 WARN 이
사라졌다. 남은 WARN 은 전부 아이콘/SVG 렌더 잡음이고 알림과 무관하다.

같은 로그에서 **`service plugin load failed for omarchy.notifications` 도 사라졌다.**
0.2.0 이전(09:17) 로그에는 `plugins/notifications/Service.qml: No such file or
directory` 가 찍혔지만, 현재 설치본에는 파일이 있다:

```console
$ ls /usr/share/cachy-omarchy/upstream/shell/plugins/notifications/
NotificationLogic.js  Service.qml  components/  manifest.json
```

즉 `omarchy.notifications` 가 실제로 로드되어 알림을 담당하고 있다.

**부수 확인 — 바와 doctor.**

```console
$ hyprctl layers
Layer level 2 (top):
  xywh: 0 0 3072 26, namespace: omarchy-bar, pid: 22315
$ hyprctl monitors | grep reserved
reserved: 0 26 0 0
$ pgrep -a waybar
(없음)
```

바는 `y=0` 에 뜨고 26px 만 예약한다. 이 세션에서는 waybar 가 실행되지 않아
§17.6 의 62px 적층은 발생하지 않았다 — 적층은 waybar 를 함께 띄울 때의 이야기다.

`cachy-omarchy-doctor` 는 24개 검사 **전부 PASS**, WARN/FAIL 0건이다
(`bar-off toggle absent (bar shows by default)` 포함).
---

## 18. M9 — 테마 런타임 채택 (구현, 2026-08-17)

설계 결정(D1–D8)과 전수 감사 근거는
`docs/superpowers/plans/2026-08-17-m9-theme-runtime-design.md` 에 있다. 이 절은
구현 실태만 기록한다. 라이브 실측(R06/R07)은 Task 9 에서 이 절에 덧붙인다.

### 18.1 스테이징

- `themes/` 22개 + `default/themed/*.tpl` 17개 — 셸과 같은 핀 커밋
  (`colors.toml`·`*.tpl` 은 한 쌍). `tests/package/test_staged_themes.sh` 가
  개수·핵심 파일·원본 동일성을 단언한다.
- Tier A helper 20개 — 코어 체인(`omarchy-theme-set`·`-set-templates`·`-color`
  등) + 배경 묶음 + `omarchy-menu-images`(메뉴 미리보기). Tier B 훅 7개
  (foot/tmux/gnome/pi/claude/vscode/obsidian). 목록과 근거는 설계 문서
  "helper 분류", 단언은 `tests/package/test_staged_theme_helpers.sh`.
- Tier C 11개 미스테이징 — 네트워크 설치(`theme-install/update/remove`),
  `/etc` 쓰기(plymouth, browser), 하드웨어 전용(keyboard*), 개발 도구.
  `omarchy-theme-set` 이 post 훅으로 browser/keyboard 를 **무조건** 호출하고
  `set -e` 가 없어 부재 시 "command not found" 만 stderr 로 새고 exit 는 0 이다
  — 이 조용한 실패를 메우기 위해 `compat/bin/omarchy-theme-set-{browser,keyboard}`
  no-op shim 2개를 둔다. `test_installed_tree.sh` 가 compat 디렉터리를 순회해
  모든 shim 의 통제 경로 존재·`/usr/bin` 누출 부재·no-op 내용을 단언한다.

### 18.2 진입점

- `cachy-omarchy-theme-set` (공개 래퍼, D6) — `OMARCHY_PATH` 를 export 하고
  `compat/bin:$OMARCHY_PATH/bin` 을 PATH 앞에 붙인 뒤 업스트림
  `omarchy-theme-set` 을 exec 한다. 테마 로직 재구현 없음.
  `tests/runtime/test_theme_set_wrapper.sh` 가 샌드박스 HOME 에서 headless
  끝단 적용(colors.toml·shell.toml·theme.name·background symlink)과 사용자
  오버레이(`~/.config/omarchy/themes/<name>/`) 우선순위를 실측한다.
- `cachy-omarchy-init` 시드(D4) — `~/.local/state/omarchy/current/theme.name`
  이 없거나 **비어 있으면**(upstream `install/user/theme.sh` 와 같은
  `[[ ! -s ]]`) "Tokyo Night" 를 시드한다. 셸이 떠 있으면 일반 경로, 아니면
  `OMARCHY_THEME_HEADLESS=1`. 기존 테마는 절대 덮어쓰지 않는다(SPEC §6.6).
  시드는 바인딩 주입보다 먼저 온다 — conf 관리 블록의 테마 `source =` 조건이
  성립해야 하기 때문(D5).

### 18.3 Hyprland 연결 (D5)

- lua 사용자: 관리 파일 `bindings.lua` 끝의 가드 블록이
  `current/theme/hyprland.lua` 를 존재할 때만 `pcall(dofile)` 한다. 파일
  부재는 정상 경로(조용히 지나감)라 무조건 dofile 하는 것과 달리 reload 마다
  오류가 나지 않는다.
- conf 사용자: 관리 블록 스니펫이 테마 파일이 있을 때만
  `source = ~/.local/state/omarchy/current/theme/hyprland.lua` 를 포함한다
  (conf 에는 조건식이 없어 존재 시에만 넣는다). M9 이전에 주입된 구형 블록은
  `cachy-omarchy-bindings --force` 가 블록을 새 스니펫으로 교체해 따라온다
  (--force 재주입은 M9 에서 추가). `cachy-omarchy-doctor` 가 구형 주입을
  `WARN` 으로 보고한다.

### 18.4 의존성

`cachy-omarchy-shell` `depends` 에 `libvips`(menu-images 썸네일)·
`procps-ng`(pgrep/pkill)·`psmisc`(killall) 추가, `optdepends` 에 `jq`(Tier B
중 vscode/pi/claude/obsidian 훅)·`tmux`·`foot` 추가. `yq` 는 핀 커밋의
theme-set 경로에서 불필요(감사 실측 — 설계 문서).

### 18.5 알려진 범위 밖

- Tier C 를 부르는 메뉴 항목(Install/Update/Remove theme, Plymouth,
  Browser/Keyboard 훅)은 `omarchy-menu.jsonc` 에 그대로 남는다 — 무패치 원칙상
  죽은 항목으로 둔다 (D3).
- 헤드리스 모드는 post 훅 전체를 건너뛴다 — 샌드박스 테스트는 훅을 검증하지
  않는다. 훅 체인의 유일한 검증은 라이브 비헤드리스 실측(§18.6 예정)이다.
