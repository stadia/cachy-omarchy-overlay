# 런타임 의존 감사

범위: 핀된 트리에서 **셸 기동 + `omarchy.menu` 토글 + 일반 데스크톱 앱 실행**. 공식 `omarchy` `depends=()`를 복사하지 않음.

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
| `config/omarchy/shell.json` | `shell.qml` `defaultsPath` | 공식은 settings | OPTIONAL | n/a | yes | `builtinShellConfig` | ENVIRONMENT — v0.1은 `disabledPlugins`가 있는 최소 json을 패키징하는 편이 안전 |
| `themes/` | 공식 `omarchy`가 설치. QML에서 경로 문자열 미검출 | 공식 `omarchy` | OPTIONAL | n/a | yes | 셸 내장 Color | NONE initially |
| `bin/omarchy-launch-shell` | 장기 프로세스 | 공식 `omarchy` | REQUIRED(logic) | n/a | no | systemd ExecStart가 `quickshell` 직접 호출 | WRAPPER — `cachy-omarchy-shell --run` |
| `bin/omarchy-shell` | IPC. 기동하지 않음 | 공식 `omarchy` | REQUIRED(logic) | n/a | no | `qs ipc` 직접 | WRAPPER — `cachy-omarchy-launcher` 등 |
| `perl` | `omarchy-menu-select` 의 select payload JSON | CachyOS `perl` | REQUIRED for keybindings menu | installed (JSON::PP 확인) | no(키바인딩 UI 한정) | 없음 | NONE — **M4 실측**: `omarchy-menu-select` 가 `perl -MEncode -MJSON::PP` 를 2회 호출해 payload 를 만든다. **M2 실측: 기동 경로 미사용** 유지 |
| `jq` | `omarchy-menu-keybindings` `lua_string()` (dispatch 경로) | CachyOS `jq` | OPTIONAL | 1.8.2-1.1 | yes for menu open | 메뉴는 QML이 JSONC 파싱 | NONE — **M4 실측**: 선택한 bind 를 `hyprctl dispatch` 할 때만 `jq -Rnr @json` 으로 Lua 문자열 인용. 목록/`--print` 경로는 미사용. **M2 실측: 기동 경로 미사용** 유지 |
| `gum` | 다수 헬퍼 TUI | CachyOS `gum` | OPTIONAL | installed | yes for menu open | 없음 | NONE — **M4 실측: 키바인딩 경로 미사용** — `omarchy-menu-keybindings` / `omarchy-menu-select` / `omarchy-cmd-present` 에 `gum` 0 매치(grep). 선택 UI 는 gum 이 아니라 `summon omarchy.menu` select mode. **M2 실측: 기동 경로 미사용** 유지 |
| `xkbcli` | `omarchy-menu-keybindings` `parse_keycodes` — `xkbcli compile-keymap` | CachyOS `libxkbcommon` | OPTIONAL | installed | no(목록 품질 저하) | 하드코딩 code: 폴백 테이블 | NONE — **M4 실측**: 없으면 `code:NNN` bind 가 심볼로 안 풀릴 뿐 스크립트는 동작 |
| `lua` | `omarchy-menu-keybindings` Lua bind 캐시 (`hyprland.lua` 소스 파서) | CachyOS `lua` | OPTIONAL | 5.5.1-1 | no(목록 품질 저하) | `omarchy-cmd-present lua` 가드가 캐시를 끈다 | NONE — **M4 실측**: `lua` 가 없어도 스크립트 자체는 동작(Lua bind 메타만 빈 캐시) |
| `uwsm` / `uwsm-app` | `AppLibrary.launch`: `uwsm-app -- gtk-launch <id>.desktop` | 공식 depends | OPTIONAL | 설치 여부에 따라 동작이 갈림 | 가능 | `gtk-launch` | WRAPPER — `overlay/compat/bin/uwsm-app` 이 실제 `uwsm-app` 을 PATH 에서 찾아(자기 자신 제외) 있으면 원래 인자(`--` 포함) 그대로 위임하고, 없으면 `--` 뒤 나머지를 직접 `exec`. 셸 프로세스 PATH 에만 붙음(§45) |
| `inotifywait` / `inotify-tools` | `services/PluginRegistry.qml:638` `localPluginWatcher` 가 `~/.config/omarchy/plugins` 감시 | CachyOS `inotify-tools` | **REQUIRED(정상 기동) / OPTIONAL(기능)** | **미설치(실측)** | no(로그 정상화 시) | 없음 — 없으면 1초마다 WARN 반복 | NONE — **M2 실측으로 신규 추가**. `PKGBUILD depends` 누락. 기능은 정상이나 로그 스팸 → `depends` 에 `inotify-tools` 추가 권장 |
| `gtk-launch` | 앱 실행 | `glib2` | REQUIRED for app launch | yes | no | `gio launch` | NONE or WRAPPER |
| `systemd --user` | 우리 유닛 계획 | systemd | REQUIRED for M2 | yes | no | 수동 기동 | WRAPPER |
| `omarchy-settings` | 공식 하드 의존 | 공식 | UNSAFE | not installed | must | 필요한 파일만 추출 | NONE — 패키지 자체 금지 |
| `limine*` / `snapper` | 공식 `omarchy` depends | 공식 | UNSAFE | — | must | 없음 | NONE |
| `sddm` | 공식 depends | 공식 | UNSAFE | — | must | 기존 로그인 유지 | NONE |
| `plymouth` | settings depends | 공식 | UNSAFE | — | must | 없음 | NONE |
| `omarchy-keyring` | 공식 depends | 공식 미러 | OPTIONAL | 20251027-1 pre-existing | yes | 로컬 `makepkg` | NONE — 미러 추가 전제 아니면 불필요 |
| `ttf-jetbrains-mono-nerd*` | 공식 UI 폰트 | 공식/AUR 계열 | OPTIONAL | 확인 필요 | yes | 시스템 폰트 | ENVIRONMENT |

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

메뉴 Apps는 `DesktopEntries` + `uwsm-app -- gtk-launch`. 전체 Omarchy 테마/설치 명령 없이 일반 `.desktop` 실행이 가능하다. `uwsm`이 설치돼 있으면 shim이 실제 `uwsm-app`에 위임해 앱을 자체 systemd scope로 격리하고, 없으면 `gtk-launch`만 직접 부른다 (`WRAPPER`, `REIMPLEMENT` 아님 — 두 경우 모두).

---

## M2 실측 메모 (Task 5 라이브 기동 기준)

> 측정한 것과 추론한 것을 구분. 라이브 기동 로그(`journalctl --user -t cachy-omarchy-shell`)와
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
- **`uwsm-app` shim 은 설치 여부에 조건부로 반응한다** — `overlay/compat/bin/uwsm-app` 이 PATH 에서
  자기 자신을 제외한 실제 `uwsm-app` 을 찾아, 있으면 원래 인자(`--` 포함) 그대로 위임하고(스코프
  격리를 실제 도구에 넘김), 없으면 `--` 뒤 나머지를 직접 `exec`(M3 R06 마커 실측). 이 호스트는 이제
  `uwsm` 이 설치돼 있어(`pacman -Q uwsm`) 위임 경로가 실사용된다 — "미설치" 로 단정하던 이전 기록은
  더 이상 사실이 아니므로 여기서 정정한다.
- **`omarchy.osd` 기동 불필요 확정** — 비활성 상태로 기동 정상. 상세는 `PLUGIN_AUDIT.md`.
