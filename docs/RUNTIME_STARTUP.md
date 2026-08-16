# Quattro 셸 기동 계약

> Milestone 2 산출물. 패키징된 업스트림 Omarchy Quattro 셸을 CachyOS에서
> 기동시키기 위해 **실측으로 확정한** 계약. 구현 세션이 Task 5 라이브 기동으로
> 얻은 관측값에 근거하며, 측정한 것과 추론한 것을 구분해 적는다.
>
> 스펙: `SPEC.md` (Spec 1.0) §13·§14·§15·§16·§17·§44·§45·§48·§55.
> 핀: `upstream.lock` — Omarchy 4.0.0 @ `f0020448ca87329199de7cb12f2015ebc4a3e5e7`.

---

## 1. 기동 명령

확정된 `--run` 의 정확한 명령(`overlay/bin/cachy-omarchy-shell`):

```bash
export OMARCHY_PATH=/usr/share/cachy-omarchy/upstream
# compat shim 디렉터리가 존재할 때만 PATH 앞에 붙인다 (현재는 비어 있음, §4).
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

따라서 `overlay/compat/bin/` 은 비어 있는 채로 둔다(§44: 로그가 요구하지 않은 shim
은 만들지 않는다). shim 이 필요해지면 그 명령만 추가한다.

> **추론 표시**: "기동에 shim 불필요" 는 측정이다. "omarchy-toggle-bar 가 기동에
> 필요한지" 는 우회했으므로 미확인이다 — M3 에서 다시 본다.

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

> **미확인**: 이 오류 문자열들은 실행 중인 셸이 있어야 재현되는 영역이다. 본 정적
> 검수에서는 계획/래퍼의 주장으로 남겨둔다. **M3 에서 실측 문자열과 일치하는지 반드시
> 확인할 것.** 매칭이 빗나가면 IPC 실패가 exit 0 으로 조용히 통과한다(silent success).

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

5. **`uwsm` 부재** — `pacman -Q uwsm` → 미설치(실측). `AppLibrary.launch` 가
   `uwsm-app -- gtk-launch` 를 쓴다(M0 감사). 이 호스트엔 `gtk-launch` 만 있다.
   M3 앱 실행에서 compat 래퍼가 필요할 가능성 높음(`WRAPPER`, `REIMPLEMENT` 아님).

6. **패키지 미설치 상태에서만 검증** — 본 M2 검증은 빌드 산출물을 임시 디렉터리에
   추출해 그 트리를 띄운 것으로, `/usr/share/cachy-omarchy/upstream` 에 실제 설치된
   상태는 아니다. 실설치 경로 검증은 M5.

7. **IPC 오류 문자열 미실측** — §5. M3 에서 확인.

---

## 7. M3 를 위한 다음 단계

`shell toggle omarchy.menu` 를 부르기 전에 확인할 것:

1. **메뉴가 이미 로드됨은 확인됨** — §3에서 `omarchy.menu` 등록·firstParty·비활성 목록
   부재를 실측. M3는 토글 IPC만 추가하면 된다.
2. **`cachy-omarchy-launcher` 래퍼** — `cachy-omarchy-shell --ipc shell toggle omarchy.menu
   '{"menu":"root"}'` 를 감싼 얇은 래퍼. IPC 재발명 금지(§15).
3. **앱 실행 compat** — `uwsm-app` 부재(§6 한계 5). `overlay/compat/bin/uwsm-app`
   shim 이 `gtk-launch` 로 위임하는지 M3에서 실측 후 결정. 로그가 요구할 때만.
4. **IPC 오류 문자열 실측** — §5 함정의 `case` 패턴이 실제 quickshell 출력과 일치하는지
   M3에서 확인. 빗나가면 silent success 위험.
5. **메뉴 명령 감사** — 메뉴에서 보이는 `omarchy-*` 명령을
   `SAFE`/`ADAPTED`/`DISABLED` 로 분류(§42.3, §43). 위험 명령은 비활성.
6. **바 억제 결정 시점** — M5 `cachy-omarchy-init` 작업과 묶어 결정. M3 데모는
   샌드박스/임시 `bar-off` 로 우회 가능하나, 실설치는 한계 1 해결이 선행.