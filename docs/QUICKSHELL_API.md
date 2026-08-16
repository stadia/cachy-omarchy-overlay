# Quickshell CLI 표면 (검증됨)

이 문서는 `cachy-omarchy-overlay`가 호출하는 `qs`/`quickshell` CLI의 실제 동작을 기록한다.
여기 적힌 내용은 추정이 아니라 **이 머신에 설치된 Quickshell 0.3.0에서 실제로 실행하고
측정한 결과**이며, 검증 코드는 `tests/installer/test_quickshell_detect.sh`에 남아 있다.

Task 5, 6, 7은 이 문서에 기록된 형태를 따른다. `SPEC.md`의 상위 계획이나 업스트림
(`vendor/omarchy`)이 이 문서와 다르게 말하는 부분이 있으면, **이 문서가 우선한다.**

측정 환경:

```text
$ pacman -Q quickshell
quickshell 0.3.0-2.1

$ qs --version
Quickshell 0.3.0 (revision , distributed by Arch Linux)

$ readlink -f /usr/bin/qs /usr/bin/quickshell
/usr/bin/quickshell
/usr/bin/quickshell
```

`/usr/bin/qs`는 `/usr/bin/quickshell`의 심링크다. 즉 어느 이름으로 불러도 동일한 바이너리이며,
`--version` 출력도 완전히 같다. `lib/env.sh`의 `coo_quickshell_bin()`은 그래도 `qs`를 먼저
찾는다 -- 업스트림 문서와 `omarchy-shell`이 이 이름을 쓰기 때문이다.

---

## 1. 결론: 업스트림 호출 중 무엇이 살아남았는가

`vendor/omarchy/bin/omarchy-shell:58` (커밋 `b724f7615630d7a7aca76dce070d469f43a3bfec`)의
호출은 다음과 같다.

```bash
qs ipc -n -p "$OMARCHY_PATH/shell" call -- "$@"
```

Quickshell 0.3.0에서 검증한 결과:

| 조각 | 살아남았는가 | 비고 |
|---|---|---|
| `qs ipc` | ✅ 그대로 | `ipc`는 여전히 서브커맨드다. |
| `-n` | ⚠️ **문맥에 따라 의미가 다르다** | `qs` 최상위 옵션의 `-n`은 `--no-duplicate`(중복 인스턴스면 즉시 종료)다. 하지만 `qs ipc`의 `-n`은 **`--newest`**(가장 최근에 실행된 인스턴스를 대상으로 함)로, 완전히 다른 옵션이다. 업스트림 호출은 `ipc` 뒤에 `-n`을 두므로 여기서는 `--newest`를 뜻하고, 이 의미는 실제로 유효하다. 즉 **글자는 같지만 우연이 아니라 의도된 것으로 보이며, `ipc` 서브커맨드 문맥에서는 그대로 동작한다.** |
| `-p "$OMARCHY_PATH/shell"` | ✅ 그대로, 단 디렉터리/파일 모두 허용 | `--path TEXT`: "Path to a QML file or config folder." 디렉터리를 주면 그 안의 `shell.qml`을 찾는다 (`--help` 예시: `qs -p ~/myshell`가 `~/myshell/shell.qml`을 실행). |
| `call` | ✅ 그대로 | `qs ipc call [target] [function] [arguments...]` -- 서브서브커맨드로 유지. |
| `--` | ✅ 있어도 무해, 없어도 됨 | `call`의 인자는 `[target] [function] [arguments...]` 세 개의 순수 positional이다. `--`를 넣어도(옵션 파서 종료 마커로 소비되고) 결과는 동일했다. 실사용에는 영향 없음. |

**요약: 업스트림 호출 형태는 이 버전에서도 그대로 쓸 수 있다.** 다만 `-n`이 `--newest`를
의미한다는 것, 그리고 `-p`에는 `shell.qml`을 담은 **디렉터리**를 주면 된다는 것을 Task 5는
명시적으로 알고 있어야 한다 (최상위 `qs -n`과 헷갈리면 안 됨).

---

## 2. `qs --help` (원문 그대로)

```text
qs [OPTIONS] [SUBCOMMAND]


OPTIONS:
  -h,     --help              Print this help message and exit
  -V,     --version           Print quickshell's version and exit.
  -n,     --no-duplicate      Exit immediately if another instance of the given config is
                              running.
  -d,     --daemonize         Detach from the controlling terminal.
[Option Group: Config Selection]
  Quickshell detects configurations as named directories under each XDG config
  directory as `<xdg dir>/quickshell/<config name>/shell.qml`.
  
  If `<xdg dir>/quickshell/shell.qml` exists, it will be registered as the
  'default' configuration, and no subdirectories will be considered. If --config
  is not passed, 'default' will be assumed.
  
  Alternatively, a config can be selected by path with --path.
  
  Examples:
  - `~/.config/quickshell/shell.qml` can be run with `qs`
  - `/etc/xdg/quickshell/myconfig/shell.qml` can be run with `qs -c myconfig`
  - `~/myshell/shell.qml` can be run with `qs -p ~/myshell`
  - `~/myshell/randomfile.qml` can be run with `qs -p ~/myshell/randomfile.qml`
  
  
OPTIONS:
  -p,     --path TEXT (Env:QS_CONFIG_PATH) Excludes: --config --manifest 
                              Path to a QML file or config folder.
  -c,     --config TEXT (Env:QS_CONFIG_NAME) Excludes: --path 
                              Name of a quickshell configuration to run.
  -m,     --manifest TEXT (Env:QS_MANIFEST) Excludes: --path 
                              [DEPRECATED] Path to a quickshell manifest.
                              If a manifest is specified, configs named by -c will point to its
                              entries.
                              Defaults to $XDG_CONFIG_HOME/quickshell/manifest.conf
[Option Group: Logging]
  
OPTIONS:
          --no-color          Disables colored logging.
                              Colored logging can also be disabled by specifying a non empty
                              value for the NO_COLOR environment variable.
          --log-times         Log timestamps with each message.
          --log-rules TEXT    Log rules to apply, in the format of QT_LOGGING_RULES.
  -v,     --verbose           Increases log verbosity.
                              -v will show INFO level internal logs.
                              -vv will show DEBUG level internal logs.
[Option Group: Debugging]
  Options for QML debugging.
  
  
OPTIONS:
          --debug INT:INT in [0 - 65535] 
                              Open the given port for a QML debugger connection.
          --waitfordebug Needs: --debug 
                              Wait for a QML debugger to connect before executing the
                              configuration.

SUBCOMMANDS:
  log                         Print quickshell logs.
  list                        List running quickshell instances.
  kill                        Kill quickshell instances.
  ipc                         Communicate with other Quickshell instances.
  msg                         [DEPRECATED] Moved to `ipc call`.
```

---

## 3. `qs ipc --help` (원문 그대로)

```text
Communicate with other Quickshell instances.


qs ipc [OPTIONS] SUBCOMMANDS


OPTIONS:
  -h,     --help              Print this help message and exit
[Option Group: Instance Selection]
  
OPTIONS:
  -i,     --id TEXT           The instance id to operate on.
                              You may also use a substring the id as long as it is unique, for
                              example "abc" will select "abcdefg".
          --pid INT           The process id of the instance to operate on.
[Option Group: Config Selection]
  Quickshell detects configurations as named directories under each XDG config
  directory as `<xdg dir>/quickshell/<config name>/shell.qml`.
  
  If `<xdg dir>/quickshell/shell.qml` exists, it will be registered as the
  'default' configuration, and no subdirectories will be considered. If --config
  is not passed, 'default' will be assumed.
  
  Alternatively, a config can be selected by path with --path.
  
  Examples:
  - `~/.config/quickshell/shell.qml` can be run with `qs`
  - `/etc/xdg/quickshell/myconfig/shell.qml` can be run with `qs -c myconfig`
  - `~/myshell/shell.qml` can be run with `qs -p ~/myshell`
  - `~/myshell/randomfile.qml` can be run with `qs -p ~/myshell/randomfile.qml`
  
  
OPTIONS:
  -p,     --path TEXT (Env:QS_CONFIG_PATH) Excludes: --config --manifest 
                              Path to a QML file or config folder.
  -c,     --config TEXT (Env:QS_CONFIG_NAME) Excludes: --path 
                              Name of a quickshell configuration to run.
  -m,     --manifest TEXT (Env:QS_MANIFEST) Excludes: --path 
                              [DEPRECATED] Path to a quickshell manifest.
                              If a manifest is specified, configs named by -c will point to its
                              entries.
                              Defaults to $XDG_CONFIG_HOME/quickshell/manifest.conf
  -n,     --newest            Operate on the most recently launched instance instead of the
                              oldest
          --any-display       If passed, instances will not be filtered by the display
                              connection they were launched on.

SUBCOMMANDS:
  show                        Print information about available IPC targets.
  call                        Call an IpcHandler function.
  wait                        Wait for one IpcHandler signal.
  listen                      Listen for IpcHandler signals.
  prop                        Manipulate IpcHandler properties.
```

`qs ipc call --help`도 함께 기록한다 (positional 인자 순서가 Task 5 코드에 그대로 들어가므로):

```text
Call an IpcHandler function.


qs ipc call [OPTIONS] [target] [function] [arguments...]


POSITIONALS:
  target TEXT                 The target to message.
  function TEXT               The function to call in the target.
  arguments TEXT ...          Arguments to the called function.

OPTIONS:
  -h,     --help              Print this help message and exit
```

---

## 4. `qs --version` (원문 그대로)

```text
Quickshell 0.3.0 (revision , distributed by Arch Linux)
```

`lib/env.sh`의 `coo_quickshell_version()`은 이 문자열에서 `grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?'`
로 `0.3.0`만 뽑아낸다. `revision` 필드가 비어 있는 것은 배포판 패키징이 커밋 해시를 채우지
않았기 때문으로 보이며, 파싱에는 영향 없다 (첫 번째 dotted 숫자만 취하므로).

---

## 5. 인스턴스가 없을 때: `qs ipc`는 정말 exit 0로 조용히 실패하는가?

Task 4 지시서는 "계획서가 IPC 레벨 실패를 stdout + exit 0로 예상하는데, 이건 CLI가 처리해야
할 함정일 수 있다"고 경고했다. 아래는 **가짜 `shell.qml`을 만들고 데몬을 띄우지 않은 채** 직접
측정한 결과다 (Hyprland 세션과 무관하게, 어떤 프로세스도 남기지 않고 실행함).

| 명령 | stdout | exit code |
|---|---|---|
| `qs ipc -p <no-such-dir> call t f` (설정 자체를 못 찾음) | `Could not open config file at "..."` | **255** |
| `qs ipc -p <valid-dir-with-shell.qml> call t f` (설정은 있으나 인스턴스 없음) | `No running instances for "<path>/shell.qml"` | **255** |
| `qs ipc -p <valid-dir> show` (동일 상황) | `No running instances for "<path>/shell.qml"` | **255** |
| `qs list -p <valid-dir>` (동일 상황) | `No running instances for "<path>/shell.qml"` + `Use --all to list all instances.` | **0** |
| `qs list --all` (인스턴스 전무) | `No running instances.` | **0** |

**결론 (중요, Task 5/7이 반드시 알아야 함):**

- `qs ipc call` / `qs ipc show`는 이 버전에서는 **실패 메시지를 stdout에 쓰지만, exit code는
  0이 아니라 255다.** 즉 계획서가 우려한 "exit 0라서 성공으로 착각한다"는 함정은 **`ipc call`/
  `ipc show`에는 해당하지 않는다** -- `$?`만 확인해도 실패를 구분할 수 있다. 다만 실패 원인
  ("설정을 못 찾음" vs "인스턴스가 없음")은 stdout 문자열을 봐야 구분되며, exit code는 둘 다
  255로 동일하다.
- **`qs list`는 다르다.** 인스턴스가 0개여도 이건 "목록 조회 성공, 결과가 빈 목록"으로 취급되어
  **exit 0**를 반환하고, 실패 여부는 오직 stdout 문자열("No running instances")로만 알 수 있다.
  Task 7이 "Quickshell이 실행 중인가"를 `qs list`로 판별하려 한다면, 종료 코드가 아니라 stdout을
  파싱해야 한다 -- 계획서가 우려한 함정은 **`list`에는 실제로 존재한다.**
- stderr는 위 모든 경우에서 비어 있었다. 진단 메시지는 전부 stdout으로 간다.

---

## 6. 여러 인스턴스 중에서 고르는 방법

`qs ipc`와 `qs list`/`qs kill`은 모두 같은 "Instance Selection" / "Config Selection" 옵션
그룹을 공유한다:

- `-i, --id TEXT`: 인스턴스 id (유일하다면 부분 문자열도 허용).
- `--pid INT`: 대상 프로세스의 PID.
- `-c, --config TEXT` / `-p, --path TEXT` (상호 배타): 어떤 설정의 인스턴스들을 대상으로 할지.
- `-n, --newest`: 여러 인스턴스가 매치되면 가장 최근에 띄운 것을 선택 (기본은 가장 오래된 것).
- `--any-display`: 기본적으로는 현재 디스플레이 연결에서 띄운 인스턴스만 후보가 되는데, 이걸
  끈다.

즉 아무 옵션도 주지 않으면 "해당 설정의, 현재 디스플레이에서 띄운 인스턴스들 중 가장 오래된
것"이 대상이 된다. `-n`을 주면 그중 가장 최근 것이 된다. 인스턴스가 정확히 하나뿐인 일반적인
오버레이 사용 시나리오에서는 `-n` 유무가 결과에 영향을 주지 않지만, 업스트림이 붙여둔 이유는
아마도 "이전 인스턴스를 재시작 중 잠깐 두 개가 겹치는 순간에도 새 것을 향하도록" 하기 위함으로
보인다 -- Task 5는 이 옵션을 그대로 유지하는 것이 안전하다.

---

## 7. 우리가 의존하는 플래그 (SPEC.md §39.17-18)

Task 5, 6, 7이 실제로 사용하는 (또는 사용할 것으로 예정된) `qs` 플래그는 이것뿐이다. 이 목록에
없는 플래그를 나중에 추가하려면 이 문서를 먼저 갱신할 것.

| 플래그 | 어느 서브커맨드 | 의미 (이 버전에서 검증됨) |
|---|---|---|
| `ipc` | `qs` | IPC 서브커맨드 진입점. |
| `-p`, `--path TEXT` | `qs ipc` | 대상 인스턴스의 설정 위치. `shell.qml`이 있는 디렉터리 경로를 준다. `--config`/`--manifest`와 배타. |
| `-n`, `--newest` | `qs ipc` (top-level `qs`의 `-n`과 다른 옵션!) | 매치되는 인스턴스가 여럿이면 가장 최근 것을 대상으로 함. |
| `call` | `qs ipc` | `qs ipc call [target] [function] [arguments...]` -- IpcHandler 함수 호출. |
| `--` | `qs ipc call` | 선택적 옵션 종료 마커. 없어도 동작 동일하지만 업스트림 관례를 유지하기 위해 보존. |
| `list` | `qs` | 실행 중 인스턴스 목록. exit code가 아니라 stdout 문자열로 "no instance" 여부를 판별해야 함 (§5 참조). |
| `-p`, `--path TEXT` | `qs list` | 위와 동일한 의미. |
| `--all` | `qs list` | 특정 설정이 아니라 전체 인스턴스를 나열. |
| `-V`, `--version` | `qs` | 버전 문자열 출력. `lib/env.sh`의 `coo_quickshell_version()`이 파싱. |

---

## 8. 불확실하거나 후속 검증이 필요한 부분

- `--pid`, `--id`를 이용한 특정 인스턴스 선택은 실제로 두 개 이상의 인스턴스를 띄운 상태에서
  검증하지 않았다 (이 작업은 데몬을 띄우지 않는 범위로 한정됨). Task 5/7이 다중 인스턴스 선택
  로직을 필요로 하게 되면 별도로 검증할 것.
- `qs msg` (`ipc call`로 대체된 deprecated 서브커맨드)는 이 문서에서 다루지 않는다 -- 새 코드는
  `ipc call`만 쓴다.
- "revision" 필드가 비어 있는 것이 이 Arch 패키지에 국한된 것인지, 업스트림 빌드 일반의 특성인지
  확인하지 않았다. 버전 파싱에는 영향 없으므로 중요도는 낮음.

---

## 9. 인스턴스가 "부팅 중이지만 아직 준비 안 됨" 상태일 때: `qs ipc call`은 무엇을 반환하는가

Task 7이 참조하는 pinned upstream `bin/omarchy-shell`은 IPC 호출 실패 시 `Not ready to
accept queries yet`라는 메시지를 stdout에 exit 0로 낸다고 가정하는 것으로 보인다. 이 절은
Task 5의 실제 호스트(`shell/shell.qml`, `dev/run-shell.sh`)를 띄우면서 그 부팅 구간을
직접 겨냥해 측정한 결과다.

**측정 방법**: `dev/run-shell.sh`를 백그라운드로 띄운 직후부터 `qs ipc -n -p
<repo>/shell call -- shell ping`을 200ms 간격으로(별도 시도로는 지연 없이 곧바로,
그리고 실행 시작과 동시에 20개를 병렬로 쏘는 방식으로도) 반복 호출해 `ok`가 나올 때까지의
모든 중간 응답을 기록했다. 15회의 순차 트라이얼(트라이얼당 최대 40회 시도)과 병렬 버스트
시도를 합쳐 수십~수백 회의 "부팅 중" 호출을 관측했다.

**결과**: 부팅이 끝나기 전 호출은 예외 없이 인스턴스가 아예 없을 때와 **완전히 동일한**
응답을 반환했다.

```text
$ qs ipc -n -p <repo>/shell call -- shell ping
No running instances for "<repo>/shell/shell.qml"
Dead instances:
 - <id1>
 - <id2>
 ...
```

exit code는 항상 **255**. `Not ready to accept queries yet`처럼 "부팅 중"임을 알려주는
구분된 메시지는 어디에도 나타나지 않았고, exit 0인 경우도 전혀 없었다 (성공 시의 `ok`,
exit 0을 제외하면). 즉 Quickshell은 IPC 소켓/타겟이 완전히 등록된 시점 이전에는 클라이언트
입장에서 "이 설정의 인스턴스는 아직 하나도 없다"는 상태와 **구별 불가능**하게 보인다 --
프로세스가 이미 fork되어 실행 중이더라도 마찬가지다. (`Dead instances:` 목록은 이 저장소를
반복 실행/종료한 과거 트라이얼들이 남긴 죽은 인스턴스 id들이며, 부팅 중 여부와는 무관한
부가 정보다.)

이 저장소의 최소 `shell.qml`은 부팅이 매우 빨라서(측정상 최대 2회 x 200ms ≈ 400ms 이내에
`ok`가 나옴), 이 구간을 붙잡기 위해 순차 폴링뿐 아니라 20개 동시 호출로 미는 버스트 테스트도
시도했다. 두 방법 모두에서 관측된 실패 응답은 모두 위와 동일한 "No running instances" +
exit 255였다 -- 다른 메시지나 exit 0 케이스는 한 번도 재현되지 않았다.

**결론 (Task 7이 알아야 함)**: 계획서가 기대하는 `Not ready to accept queries yet` /
exit 0 폴백은 **이 버전(Quickshell 0.3.0)의 `qs ipc call`에서는 존재하지 않는다.** Task 7의
실패 처리는 "부팅 중"과 "인스턴스가 아예 없음"을 같은 경로로 다뤄야 한다: 두 상황 모두
stdout에 `No running instances...`류 메시지, exit 255로 나타난다. 부팅 중인지 아닌지
구분하고 싶다면 exit code나 stdout 문자열이 아니라 (a) 자신이 방금 그 프로세스를 fork했다는
사실을 스스로 기억하고 있거나, (b) §5의 방식대로 재시도-후-타임아웃 폴링을 하는 수밖에 없다.

이 결과를 재현하지 못하는 경우를 대비해 남겨두는 주의사항: 위 측정은 이 머신, 이 저장소의
최소 `shell.qml`(서비스 인스턴스화와 `IpcHandler` 하나만 있는, 렌더링할 화면이 전혀 없는
구성)에 한정된다. 무거운 QML(폰트 로딩, 이미지 디코딩 등)이 있는 실제 셸이라면 부팅 시간이
길어져 이 구간이 더 넓게 관측될 수 있으나, 관측된 실패 응답의 **형태**(exit 255 +
"No running instances")가 부팅 시간에 따라 달라질 이유는 없다 -- 소켓이 아직 등록되지
않았다는 사실 자체가 그 메시지의 원인이기 때문이다.

---

## 10. Task 6: `TestSurface.qml`이 쓰는 QML 타입/첨부 속성 검증

Task 6 계획서는 `LazyLoader`가 이 Quickshell 버전에 없을 수 있다고 경고하며, 없다면 `Loader` +
`active:`로 대체하라고 했다. `/usr/lib/qt6/qml/Quickshell*`의 `*.qmltypes`를 직접 grep해
아래 타입/첨부 속성을 전부 확인했다 -- **어느 것도 대체하지 않았다. 계획서의 QML은 이 버전에서
그대로 쓸 수 있다.**

| 타입/속성 | 선언 위치 (qmltypes) | 비고 |
|---|---|---|
| `LazyLoader` | `Quickshell/quickshell-core.qmltypes` | export `Quickshell/LazyLoader 0.0`. `active`(bool), `component`(기본 프로퍼티) 존재. 계획서 그대로 사용. |
| `PanelWindow` | `Quickshell/_Window/quickshell-window.qmltypes` (`PanelWindowInterface`) | export `Quickshell._Window/PanelWindow 0.0`. `anchors`, `exclusionMode` 확인. `color`는 상위 프로토타입(`WindowInterface`)에 있음. |
| `WlrLayershell.layer` / `.keyboardFocus` / `.namespace` | `Quickshell/Wayland/_WlrLayerShell/quickshell-wayland-layershell.qmltypes` | `WlrLayershell`은 `attachedType: "...WlrLayershell"` -- 첨부 속성으로 확인됨. 세 프로퍼티 이름 모두 정확히 일치. |
| `WlrLayer.Overlay` | 위와 동일 | enum 값: `Background, Bottom, Top, Overlay`. |
| `WlrKeyboardFocus.Exclusive` | 위와 동일 | enum 값: `None, Exclusive, OnDemand`. |
| `ExclusionMode.Ignore` | `Quickshell/_Window/quickshell-window.qmltypes` | enum 값: `Normal, Ignore, Auto`. `PanelWindow`와 `WlrLayershell` 양쪽에 동일한 `exclusionMode` 프로퍼티가 있음(레이어셸이 `PanelWindow`를 상속하지 않고 별도 프로토타입 체인이라 중복 선언됨). |

검증 방법은 정적 분석(qmltypes grep)에 그치지 않았다: `dev/run-shell.sh`로 실제 호스트를
띄우고 `qs ipc call -- test open`/`close`를 호출한 뒤 `hyprctl layers`로 namespace
`coo-test`인 레이어가 실제로 나타났다 사라지는지 확인했고(§Task 6 보고서 참조), `grim`으로
화면을 캡처해 420x140 크기의 둥근 모서리 패널이 화면 중앙에 실제로 렌더링되는 것을 육안으로도
확인했다. 즉 이 표는 "타입이 존재한다"뿐 아니라 "이 타입 조합이 실제로 레이어셸 서피스를
만든다"는 것까지 검증된 결과다.

이후 마일스톤(런처, 키바인딩 서피스)이 같은 조합을 재사용할 때는 이 표를 그대로 신뢰해도 된다.
</content>
