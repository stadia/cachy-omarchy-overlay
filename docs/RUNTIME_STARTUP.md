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
- 없으면 `defaultsPath` 를 읽는다. 우리 패키지는 이 자리에 **우리 기본값**(`overlay/defaults/shell.json`)을 설치한다 — `stage-upstream.sh` 가 업스트림 것이 아니라 우리 것을 넣는다.
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

## 3. 비활성 플러그인

패키지에 실제로 스테이징되는 `disabledPlugins` (`overlay/defaults/shell.json`):

```text
omarchy.bar  omarchy.notifications  omarchy.lock  omarchy.osd
omarchy.idle  omarchy.battery  omarchy.nightlight  omarchy.media
omarchy.polkit  omarchy.reminders  omarchy.background
```

`omarchy.menu` 는 목록에 **없다** (M3 런처).

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

3. **`graphical-session.target` 비활성** — `overlay/systemd/cachy-omarchy-shell.service`
   는 `WantedBy=graphical-session.target` + `ConditionEnvironment=WAYLAND_DISPLAY`
   (업스트림 패턴, 실측 일치). 그러나 이 호스트엔 `uwsm` 이 없어
   `graphical-session.target` 이 `inactive (dead)` 다. 현재 Wayland 세션은 살아
   있음(`wayland-1`). **결과: M5 에서 유닛이 자동 시작하지 않는다.** M2 는 유닛을 쓰지
   않고 래퍼를 직접 부르므로 영향 없으나, §17 "CachyOS 에서 target 순서 검증" 은
   미충족. 해결: `graphical-session.target` 활성화 경로 문서화 / Hyprland `exec-once`
   로 서비스 시작 / 타겟 재검토.

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
| 8 | `usr/lib/systemd/user/cachy-omarchy-shell.service` |
| 9 | `usr/share/cachy-omarchy/defaults/shell.json` |
| 10 | `usr/share/cachy-omarchy/hypr/bindings.conf` |
| 11 | `usr/share/cachy-omarchy/hypr/bindings.lua` |

`/etc`, `/boot`, `/efi`, system 유닛(`usr/lib/systemd/system/`)은 소유하지 않는다.
compat shim(6, 7번)은 `/usr/lib/cachy-omarchy/compat/bin/` 에만 있고 `/usr/bin` 으로
새지 않는다 — `test_installed_tree.sh` 가 두 방향 모두 확인한다.

### 9.2 `cachy-omarchy-init` 계약

`overlay/bin/cachy-omarchy-init` (설치 후 `usr/bin/cachy-omarchy-init`)은 패키지의
post-install 훅이 아니라 **사용자가 직접 실행**하는 유저 레벨 헬퍼다(SPEC §38). 무엇을
만드는지, 언제 만드는지, 멱등 규칙은 다음과 같다.

- **만드는 것 (최초 실행 시에만)**
  - `~/.config/cachy-omarchy/shell.json` — `$COO_PREFIX_ROOT/defaults/shell.json` 복사본.
  - `~/.config/cachy-omarchy/hypr/bindings.{conf,lua}` — `cachy-omarchy-bindings` 에
    위임해 설치하고, 사용자 Hyprland 설정에 관리 source 블록만 주입한다(본문은 건드리지
    않음).
  - `~/.local/state/omarchy/toggles/bar-off` — 내장 바를 숨기는 빈 파일.
- **멱등 규칙 — 파일 단위, 존재 여부만 본다.** 대상 파일이 이미 있으면 건드리지 않고
  "유지" 메시지만 낸다. 두 번째 실행은 사용자가 고친 `shell.json` 을 덮어쓰지 않는다
  (`tests/runtime/test_init.sh` 의 `USER_EDIT` 보존 검증).
  - `--dry-run` 은 무엇을 할지 출력만 하고 **아무 파일도 만들지 않는다.**
- **`bar-off` 는 사용자가 지우면 되살리지 않는다.** 판단 기준은 **파일이 아니라
    toggles 디렉터리의 존재**다: `~/.local/state/omarchy/toggles/` 디렉터리가 이미
    있으면(즉, 최초 실행을 이미 거쳤으면) 그 안의 `bar-off` 를 다시 만들지 않는다 —
    사용자가 지운 것을 "바를 보겠다"는 의사로 해석한다. 디렉터리 자체가 없을 때만
    최초 생성 대상이다.
- 바인딩 설치는 **재구현하지 않고** 형제 명령 `cachy-omarchy-bindings` 에 위임한다
  (SPEC §20). `--force` 는 그대로 전달되며, 충돌 시에도 기존 사용자 바인딩 줄을
  지우지 않는다. `hyprctl reload` 는 어디에서도 호출하지 않는다.

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
