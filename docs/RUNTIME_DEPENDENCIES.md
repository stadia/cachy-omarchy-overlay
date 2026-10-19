# 런타임 의존 감사

범위: 이 표는 **셸 기동 + `omarchy.menu` 토글 + 일반 데스크톱 앱 실행**의 최소
집합만 다룬다(M2 시점 축). `/usr/bin` 에 노출된 helper 전체의 외부 명령 클로저는
아래 "클로저 전수(생성)" 절이 다루며, 그쪽이 기계 판정이다. 공식 `omarchy` `depends=()`를 복사하지 않음.

분류: `REQUIRED` | `OPTIONAL` | `DISABLE` | `UNSAFE`  
적응: `NONE` | `ENVIRONMENT` | `WRAPPER` | `PATCH` | `REIMPLEMENT`

---

| name | where referenced | provider | class | CachyOS | disable? | fallback | adaptation |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `OMARCHY_PATH` | `bin/omarchy-shell`, `bin/omarchy-launch-shell`, `shell/shell.qml`, 플러그인 | 세션 env | REQUIRED | n/a | no | 없음. 미설정 시 IPC 실패 | ENVIRONMENT — 래퍼/유닛이 `/usr/share/cachy-omarchy/upstream` 설정 |
| `/usr/share/omarchy` | 공식 패키지 설치 경로, 테스트 픽스처 | 공식 `omarchy` | DISABLE as install root | n/a | yes | `OMARCHY_PATH` | ENVIRONMENT. QML에 하드코딩 없음 → `ENV-COMPATIBLE` |
| `quickshell` / `qs` | `omarchy-launch-shell`: `quickshell -n -p "$OMARCHY_PATH/shell"`; `omarchy-shell`: `qs ipc -n -p ... call` | Arch/CachyOS `quickshell` | REQUIRED | 0.3.0-2.1 | no | 없음 | NONE |
| `hyprland` / `hyprctl` | `omarchy-launch-shell` compositor probe; 키바인드 UI | CachyOS `hyprland` | REQUIRED | 0.56.2-1 | no | 없음 | NONE |
| `timeout` | `omarchy-shell` IPC | `coreutils` | REQUIRED | yes | no | 없음 | NONE |
| `shell/shell.qml` | IPC·기동 경로 검사 | 우리 셸 패키지 | REQUIRED | n/a | no | builtin config로 일부 폴백 | NONE — `shell/` 전체 패키징 |
| `shell/plugins/menu/` | `omarchy.menu` | 우리 셸 패키지 | REQUIRED | n/a | no | 없음 | NONE |
| `default/omarchy/omarchy-menu.jsonc` | `Menu.qml` `defaultMenuPath` | 공식은 settings가 설치 | REQUIRED | n/a | no | 빈 메뉴(앱 행만) | ENVIRONMENT — 셸 패키지에 파일만 포함. settings 금지 |
| `config/omarchy/shell.json` | `shell.qml` `defaultsPath` | 공식은 settings | OPTIONAL | n/a | yes | `builtinShellConfig` | ENVIRONMENT — **실제 배포본은 `overlay/defaults/shell.json`, `disabledPlugins` 없음 → 전 플러그인 활성**(방향 전환 2026-08-17). v0.1 시절 "최소 json이 안전" 판단은 뒤집혔다 |
| `themes/` | 공식 `omarchy`가 설치. QML에서 경로 문자열 미검출 | 공식 `omarchy` | OPTIONAL | n/a | yes | 셸 내장 Color | NONE initially |
| `bin/omarchy-launch-shell` | 장기 프로세스 | 공식 `omarchy` | REQUIRED(logic) | n/a | no | systemd ExecStart가 `quickshell` 직접 호출 | SAFE — verbatim 스테이징(#11). autostart 가 직접 부른다 |
| `bin/omarchy-shell` | IPC. 기동하지 않음 | 공식 `omarchy` | REQUIRED(logic) | n/a | no | `qs ipc` 직접 | SAFE — verbatim 스테이징(#11) |
| `perl` | `omarchy-menu-select` 의 select payload JSON | CachyOS `perl` | REQUIRED for keybindings menu | installed (JSON::PP 확인) | no(키바인딩 UI 한정) | 없음 | NONE — **M4 실측**: `omarchy-menu-select` 가 `perl -MEncode -MJSON::PP` 를 2회 호출해 payload 를 만든다. **M2 실측: 기동 경로 미사용** 유지 |
| `jq` | `omarchy-menu-keybindings` `lua_string()` (dispatch 경로) | CachyOS `jq` | OPTIONAL | 1.8.2-1.1 | yes for menu open | 메뉴는 QML이 JSONC 파싱 | NONE — **M4 실측**: 선택한 bind 를 `hyprctl dispatch` 할 때만 `jq -Rnr @json` 으로 Lua 문자열 인용. 목록/`--print` 경로는 미사용. **M2 실측: 기동 경로 미사용** 유지 |
| `gum` | 다수 헬퍼 TUI | CachyOS `gum` | OPTIONAL | installed | yes for menu open | 없음 | NONE — **M4 실측: 키바인딩 경로 미사용** — `omarchy-menu-keybindings` / `omarchy-menu-select` / `omarchy-cmd-present` 에 `gum` 0 매치(grep). 선택 UI 는 gum 이 아니라 `summon omarchy.menu` select mode. **M2 실측: 기동 경로 미사용** 유지 |
| `xkbcli` | `omarchy-menu-keybindings` `parse_keycodes` — `xkbcli compile-keymap` | CachyOS `libxkbcommon` | OPTIONAL | installed | no(목록 품질 저하) | 하드코딩 code: 폴백 테이블 | NONE — **M4 실측**: 없으면 `code:NNN` bind 가 심볼로 안 풀릴 뿐 스크립트는 동작 |
| `lua` | `omarchy-menu-keybindings` Lua bind 캐시 (`hyprland.lua` 소스 파서) | CachyOS `lua` | REQUIRED (depends) | 5.5.1-1 | yes for menu open | 패치된 헬퍼가 lua 부재 시 stderr 한 줄과 알림 후 exit 1 | NONE — Lua 설정에서는 모든 bind 가 `__lua` 로만 보고돼 lua 없이는 시트가 비므로 hard depends 로 승격(#13 리뷰) |
| `uwsm` / `uwsm-app` | `AppLibrary.launch`: `uwsm-app -- gtk-launch <id>.desktop` | Arch `uwsm` 패키지 — `cachy-omarchy-shell` hard depends | REQUIRED | 0.26.6-1 | no | 없음 | NONE — shim 은 삭제됐다. uwsm-app 은 uwsm 패키지가 소유하는 실제 바이너리이며, 어느 레이어도 PATH 를 조작하지 않는다(§45 개정). 우리 패키지가 소유하지 않음은 `tests/package/test_usr_bin_helpers.sh` 가 검사한다 |
| `inotifywait` / `inotify-tools` | `services/PluginRegistry.qml:638` `localPluginWatcher` 가 `~/.config/omarchy/plugins` 감시 | CachyOS `inotify-tools` | REQUIRED(정상 기동) | **`PKGBUILD depends`에 있음**(`packages/cachy-omarchy-shell/PKGBUILD`) | no | 없음 — 없으면 1초마다 WARN 반복 | NONE — **M2 실측으로 신규 추가, 이후 depends 에 반영됨**(당시 발견된 누락은 해소됨) |
| `gtk-launch` | 앱 실행 | `glib2` | REQUIRED for app launch | yes | no | `gio launch` | NONE or WRAPPER |
| `systemd --user` | 우리 유닛 계획 | systemd | REQUIRED for M2 | yes | no | 수동 기동 | WRAPPER |
| `omarchy-settings` | 공식 하드 의존 | 공식 | UNSAFE | not installed | must | 필요한 파일만 추출 | NONE — 패키지 자체 금지 |
| `limine*` / `snapper` | 공식 `omarchy` depends | 공식 | UNSAFE | — | must | 없음 | NONE |
| `sddm` | 공식 depends | 공식 | UNSAFE | — | must | 기존 로그인 유지 | NONE |
| `plymouth` | settings depends | 공식 | UNSAFE | — | must | 없음 | NONE |
| `omarchy-keyring` | 공식 depends | 공식 미러 | OPTIONAL | 20251027-1 pre-existing | yes | 로컬 `makepkg` | NONE — 미러 추가 전제 아니면 불필요 |
| `ttf-jetbrains-mono-nerd*` | 공식 UI 폰트 | 공식/AUR 계열 | OPTIONAL | 확인 필요 | yes | 시스템 폰트 | ENVIRONMENT |

---

## 클로저 전수

명령 → 패키지 → 등급 판정은 `tests/runtime/closure_check.py` 가 매번 계산하고
`tests/runtime/test_dependency_closure.sh` 가 위반 여부를 검사한다. 표 자체는
이 문서에 싣지 않는다 — 생성 결과를 체크인하면 핀이 움직일 때마다 문서를 다시
써야 했고, 그 동기화가 `bin/update-upstream` 을 여러 번 돌리게 만든 원인 중
하나였다. 필요하면 아래 명령으로 뽑는다.

**`BASE` 등급은 declare 대상이 아니다.** `BASE` 는 "기반 시스템 — 부재할 수 없는
패키지"(`coreutils`, `bash`, `systemd` 등)다. 그중 일부(`gsettings` 등)는 우리가
**직접 호출하는** 명령이기도 하다 — BASE 라는 등급이 "우리가 안 쓴다"는 뜻이
아니라 "declare 할 필요가 없다"는 뜻이라는 것을 혼동하지 말 것.

### 등급 규칙 — `BASE` / `HARD` / `OPT` / `AUR` / `UNPACKAGED`

실행 중 이 등급 체계가 개정됐다. `command-packages.tsv` 근거 열에 붙는 "(§4.2 개정)" 표기가
가리키는 것이 이 개정이다 — 설계 문서 자체는 `docs/superpowers/`(gitignore 됨)
아래 있어 저장소를 물려받는 사람은 읽을 수 없으므로, 그 요지를 여기 직접 적는다.

원래는 "메뉴에서 도달하면 HARD"였다. 그 규칙은 성립하지 않았다 — discord/mpv
처럼 메뉴 항목에서 도달해도 하드 의존으로 볼 수 없는 사례가 나와
`BASE`/`HARD`/`OPT` 3분기로 개정했다:

- **BASE** — 기반 시스템 패키지(`coreutils`/`bash`/`systemd` 등). 부재할 수
  없으므로 declare 하지 않는다. `base` 패키지 폐포(`pactree -s base` +
  `pacman -Ql`)가 소유한 명령은 스캐너가 직접 도출하므로 `command-packages.tsv`
  에 적지 않는다. 이 도출은 `pacman-contrib`(pactree)가 있어야 한다 — 없으면
  경고를 내고 그 명령들이 `UNMAPPED_COMMAND` 로 실패한다. `base-devel` 은 사용자
  시스템에 있다는 보장이 없어 도출 대상이 아니다(예: `cmp` 는 `diffutils` 를
  HARD 로 선언한다).
- **HARD** — 기동/기본 활성 경로에서 도달하는 명령. `depends` 로 선언한다
  (이미 선언돼 있으면 근거 열에 "이미 depends"로 남는다).
- **OPT** — 사용자가 그 기능을 명시적으로 선택해야 도달하는 명령(메뉴 항목,
  패널 대상 애플리케이션 등). **v0.12.1 정책 전환**: 공식 리포에 있는 OPT 는
  `depends` 로 선언한다 — 이 오버레이는 큐레이팅된 데스크톱을 출하하며 메뉴·패널
  항목이 설치 직후 동작하지 않는 상태를 기본값으로 두지 않는다. 분류 자체는
  도달성 사실이라 그대로 OPT 이고, 바뀐 것은 선언 위치다. 스캐너는 OPT 를
  `depends`·`optdepends` 어느 쪽으로도 만족시킨다(`closure_check.py`). 리포에
  없는 것(AUR)과 기본 데스크톱과 무관한 개별 애플리케이션(discord·tailscale·
  tesseract 등)은 계속 `optdepends` 다.
- **AUR** — 실제 Arch 패키지가 존재하지만 공식 리포가 아니라 AUR 에만 있다.
  `pacman -U` 는 `depends` 를 리포/이미 설치된 패키지로만 해결하므로
  (`bin/install-packages`), AUR 전용 패키지를 `depends` 에 넣으면 우리
  패키지 자체가 설치 불가해진다 — HARD 성격이라도 `optdepends` 로 내린다
  (예: `xdg-terminal-exec`).
- **UNPACKAGED** — 공식 리포에도 AUR 에도 제공자가 없다. 선언할 곳이 없으므로
  아무 곳에도 선언하지 않고, 이 표에만 기록해 존재를 드러낸다(예: `asdcontrol`).

`AUR`/`UNPACKAGED` 두 클래스가 추가된 이유: 원래 체계는 "모든 외부 명령에 리포
제공자가 있다"를 암묵 전제했는데, 실행 중 이 전제가 세 번 깨졌다.

위반 접두사는 원래 `UNMAPPED_COMMAND`/`MISSING_HARD_DEP`/`MISSING_OPT_DEP`/
`STALE_EXCEPTION` 4종이었고, 실행 중 `UNMATCHED_DISABLED_PLUGIN`(존재하지 않는
플러그인 id 를 `disabledPlugins` 가 가리킴), `AUR_IN_DEPENDS`(AUR 전용 패키지가
`depends` 에 잘못 들어감) 2종이 늘었다(`STALE_EXCEPTION` 은 처음부터 있었으나
"예외가 이미 스테이징됐거나 더는 도달 불가"로 판정 기준이 넓어졌다).

판별 근거 자체도 바뀌었다. 원래는 "이름의 모양"(정규식)으로 헬퍼 여부를
추론했는데, 그 방식이 여섯 라운드에 걸쳐 나온 모든 오탐의 단일 원인이었다
(QML 네임스페이스, `reloadableId`, 우리 자신의 `cachy-omarchy-*`, 설정 파일
이름, 알림 hint 키, grep 패턴, echo 안내문). 지금은 핀된 업스트림 `bin/` 목록
(`bin/list-upstream-helpers` 가 `build/omarchy` 에서 핀 커밋의 `git ls-tree` 로 그때그때
뽑는다)을 ground truth 로 쓴다 — 이름이 그 목록에 없으면 헬퍼로 인정하지
않는다(아래 "스캐너가 헬퍼로 인정하지 않은 이름" 목록). 목록은 체크인하지 않으므로
핀과 어긋날 수 없다.

명령 → 패키지 → 등급 표와 "스캐너가 헬퍼로 인정하지 않은 이름" 목록은 체크인하지
않는다. 필요할 때 현재 빌드에서 뽑는다:

```bash
python3 tests/runtime/closure_check.py --tree <추출한 트리> --repo . \
  --map tests/data/command-packages.tsv \
  --upstream-helpers <(bin/list-upstream-helpers) \
  --exceptions tests/data/closure-exceptions.tsv --emit-table
```

`<추출한 트리>` 는 `tests/runtime/test_dependency_closure.sh` 가 만드는 것과 같다
(`coo_extract_pkg` 로 셸 패키지를, `coo_extract_overlay <트리>/overlay` 로 오버레이를
같은 루트에 푼다).

### 스캐너의 알려진 한계 — 이 감사가 완전성을 주장하지 않는 이유

이 감사는 상한이 아니라 정적 분석이 잡아낼 수 있는 것의 스냅샷이다. 아래
네 가지는 코드 주석(`tests/runtime/closure_check.py`)에 이미 있는 한계를 그대로
옮긴 것이며, 부드럽게 쓰지 않는다.

1. **동적으로 조립되는 이름은 열거할 수 없다.** `"omarchy-installed-service-$service"`
   같은 문자열 연결/변수 보간 계열은 정적 분석으로 값 집합을 알 수 없다.
   `omarchy-bar:165` 가 실제로 이 형태로 헬퍼를 호출한다 — 그 호출은 스캔
   결과에 나타나지 않는다.
2. **QML/JS 는 문자열 리터럴만 읽는다.** `"omarchy-" + kind` 같은 문자열 연결이나
   템플릿 리터럴로 조립되는 이름은 수확기가 보지 못한다. 현재 핀 트리에는 이
   용법이 0건이다(grep 확인, 2026-08-21) — 업스트림이 이 형태를 도입하면 조용히
   빠진다.
3. **인벤토리는 업스트림 `bin/` 만 덮는다.** `bin/list-upstream-helpers` 는
   핀된 업스트림 커밋의 `bin/` 디렉터리만 읽는다. 업스트림이 헬퍼를 다른
   디렉터리로 옮기면 그 헬퍼는 조용히
   "헬퍼 아님"으로 분류되어 그래프에서 빠진다 — `UNSTAGED_REACHABLE` 로도 잡히지
   않는다.

4. **가장 큰 억제 통로는 이 문서가 아니라 `docs/COMMAND_AUDIT.md` 에 있다.**
   스캐너는 메뉴 루트(`omarchy-menu.jsonc`)에서 이름을 수확할 때,
   `docs/COMMAND_AUDIT.md` 에서 `DISABLED` 로 표시된 행을 정규식으로 긁어
   **차감한다**. 개수는 `--emit-table` 이 낸다(`tests/data/closure-exceptions.tsv` 의
   예외 행보다 훨씬 크다). 차감되는 이름 대부분은 우리가 의도적으로 취하지 않는
   Omarchy OS 스택(공장 초기화, plymouth, 채널, install-gaming 계열)이므로
   결정 자체는 정당하다.

   정당하지 않았던 것은 **장부**다. 예외 파일은 사유가 파싱으로 강제되고
   `STALE_EXCEPTION` 으로 신선도가 검사되며 이 문서에서 논의된다. 반면 이
   `DISABLED` 통로는 사유가 필수가 아니고, 스테이징되거나 도달 불가가 되어도
   아무도 알려주지 않는다. `--emit-table` 이 개수와 이름을 내보내지만, 사유 강제와
   신선도 검사는 여전히 없다. 이 통로를 통해 무엇이 사라지는지 알고 싶으면
   `--emit-table` 출력의 해당 목록을 읽어야 한다.

### `docs/COMMAND_AUDIT.md` 와의 범위 차이

`docs/COMMAND_AUDIT.md` 는 메뉴/셸이 도달하는 헬퍼를 감사 대상으로 삼고, 이 절의
클로저 스캐너는 다른 도달성 정의(BFS 루트 + 인벤토리)를 쓴다. 그래서
`tests/data/closure-exceptions.tsv` 의 잔여 예외 16건 중 11건은 `COMMAND_AUDIT.md` 에
자기 행이 아예 없다(측정 명령 아래). 이것은 결함이 아니라 **범위 차이**이며, 다음
사람이 11건을 "감사 누락"으로 오해하지 않도록 여기에 명시한다. 행 수는 주석을
제외한 `closure-exceptions.tsv` 데이터 행이다(v0.9 의 31건에서 줄어 현재 16건이다).

```console
$ awk -F'\t' '!/^#/ && NF {print $1}' tests/data/closure-exceptions.tsv | while read -r name; do
    grep -qE "^\| \`$name\` \|" docs/COMMAND_AUDIT.md || echo "$name"
  done | wc -l
11
```

또한 `tests/runtime/test_command_audit.sh` 는 `closure-exceptions.tsv` 를 읽지
않는다. 즉 이 두 문서가 서로 모순되지 않는지는 **기계가 아니라 사람이** 지킨다 —
`COMMAND_AUDIT.md` 와의 정합은 어떤 테스트의 보장 밖이다.

v0.10.0 이 `omarchy-battery-status` 를 포함한 가시 UI 헬퍼 9개를 스테이징하면서,
이전에 여기 적혀 있던 Power 패널 배터리 상세 행 결손은 닫혔다. weather 위젯의
외부 요청(wttr.in IP 조회는 비저장, 패널은 Open-Meteo 예보/지오코딩도 사용)은
스테이징 결손이 아니라 문서화된 표면이다(README "Weather widget"). 남은
사용자가 체감하는 격차는 `xdg-terminal-exec` 가 AUR 전용이라는 점이며, 방향
결정은 v0.11 선행 과제다.

---

## 기동 최소 집합

```text
OMARCHY_PATH=<upstream root>
quickshell -n -p "$OMARCHY_PATH/shell"
```

필요 트리:

```text
$OMARCHY_PATH/shell/          # 전체. 메뉴만 잘라내지 말 것 (SPEC §13)
$OMARCHY_PATH/default/omarchy/omarchy-menu.jsonc
$OMARCHY_PATH/version         # doctor/핀 표시
$OMARCHY_PATH/config/omarchy/shell.json   # 권장: bar/lock/osd를 disabledPlugins로
```

IPC:

```text
qs ipc -n -p "$OMARCHY_PATH/shell" call -- shell toggle omarchy.menu '{"menu":"root"}'
```

`/usr/share/omarchy` 심볼릭은 감사 상 **불필요**(QML `ENV-COMPATIBLE`). 헬퍼가 경로를 하드코딩하면 그때 `PATCH` 또는 compat.

---

## 앱 실행

메뉴 Apps는 `DesktopEntries` + `uwsm-app -- gtk-launch`. 전체 Omarchy 테마/설치 명령 없이 일반 `.desktop` 실행이 가능하다. `uwsm-app` 은 uwsm 패키지(hard depends)의 실제 바이너리가 담당하며 앱을 자체 systemd scope(`app-graphical.slice`)로 격리한다. M3 시절의 compat shim(`gtk-launch` 폴백 WRAPPER)은 uwsm 이 필수 의존이 되면서 삭제됐다.

---

## M2 실측 메모 (Task 5 라이브 기동 기준)

> 측정한 것과 추론한 것을 구분. 라이브 기동 로그(`journalctl --user -t omarchy-shell`)와
> `listPlugins`/`listShellConfig` IPC 로 관측.

- **기동 경로에서 실제로 발생한 missing-binary WARN: `inotifywait` 단 한 종류.**
  `perl`/`jq`/`gum`/기타 업스트림 헬퍼는 기동 로그에 WARN 이 없으므로 **기동에 사용되지 않음**
  (측정). 이들은 메뉴 동작·헬퍼(M3/M4) 용이지 기동 의존이 아니다.
  **M4 실측**: 키바인딩 경로는 `perl`(JSON::PP)·`jq`(dispatch 한정)·`xkbcli`·`lua` 를
  쓰고 `gum` 은 쓰지 않는다 — 위 표의 M4 행 참조.
- **`inotify-tools` 누락 (§28 감사 누락)** — `PluginRegistry.qml:638` 이 `inotifywait` 를
  1초마다 재시작하며 WARN 을 반복. 기능은 정상(37개 플러그인 등록)이나 정상 기동(로그 정숙)을
  위해 `REQUIRED`. **`PKGBUILD depends=('quickshell' 'hyprland')` 에 `inotify-tools` 추가 권장**
  (M7 신뢰성 마일스톤 전, 또는 M3 전). 추론 아닌 실측.
- **`uwsm-app` shim 은 삭제됐다** — M2/M3 시절 compat shim 이 실제 `uwsm-app` 유무에
  따라 위임/폴백했으나(M3 R06 마커 실측), `uwsm` 이 `cachy-omarchy-shell` 의 hard
  depends 가 되면서 제거했다. 이 호스트에는 `uwsm` 이 설치돼 있고(`pacman -Q uwsm`)
  `/usr/bin/uwsm-app` 은 uwsm 패키지 소유다(`pacman -Qqo` 실측) — 우리 패키지가
  소유하지 않음은 `tests/package/test_usr_bin_helpers.sh` 가 검사한다.
- **`omarchy.osd` 기동 불필요 확정** — 비활성 상태로 기동 정상.
