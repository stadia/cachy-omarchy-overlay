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
| `config/omarchy/shell.json` | `shell.qml` `defaultsPath` | 공식은 settings | OPTIONAL | n/a | yes | `builtinShellConfig` | ENVIRONMENT — v0.1은 `disabledPlugins`가 있는 최소 json을 패키징하는 편이 안전 |
| `themes/` | 공식 `omarchy`가 설치. QML에서 경로 문자열 미검출 | 공식 `omarchy` | OPTIONAL | n/a | yes | 셸 내장 Color | NONE initially |
| `bin/omarchy-launch-shell` | 장기 프로세스 | 공식 `omarchy` | REQUIRED(logic) | n/a | no | systemd ExecStart가 `quickshell` 직접 호출 | WRAPPER — `cachy-omarchy-shell --run` |
| `bin/omarchy-shell` | IPC. 기동하지 않음 | 공식 `omarchy` | REQUIRED(logic) | n/a | no | `qs ipc` 직접 | WRAPPER — `cachy-omarchy-launcher` 등 |
| `perl` | `omarchy-menu-select` 의 select payload JSON | CachyOS `perl` | REQUIRED for keybindings menu | installed (JSON::PP 확인) | no(키바인딩 UI 한정) | 없음 | NONE — **M4 실측**: `omarchy-menu-select` 가 `perl -MEncode -MJSON::PP` 를 2회 호출해 payload 를 만든다. **M2 실측: 기동 경로 미사용** 유지 |
| `jq` | `omarchy-menu-keybindings` `lua_string()` (dispatch 경로) | CachyOS `jq` | OPTIONAL | 1.8.2-1.1 | yes for menu open | 메뉴는 QML이 JSONC 파싱 | NONE — **M4 실측**: 선택한 bind 를 `hyprctl dispatch` 할 때만 `jq -Rnr @json` 으로 Lua 문자열 인용. 목록/`--print` 경로는 미사용. **M2 실측: 기동 경로 미사용** 유지 |
| `gum` | 다수 헬퍼 TUI | CachyOS `gum` | OPTIONAL | installed | yes for menu open | 없음 | NONE — **M4 실측: 키바인딩 경로 미사용** — `omarchy-menu-keybindings` / `omarchy-menu-select` / `omarchy-cmd-present` 에 `gum` 0 매치(grep). 선택 UI 는 gum 이 아니라 `summon omarchy.menu` select mode. **M2 실측: 기동 경로 미사용** 유지 |
| `xkbcli` | `omarchy-menu-keybindings` `parse_keycodes` — `xkbcli compile-keymap` | CachyOS `libxkbcommon` | OPTIONAL | installed | no(목록 품질 저하) | 하드코딩 code: 폴백 테이블 | NONE — **M4 실측**: 없으면 `code:NNN` bind 가 심볼로 안 풀릴 뿐 스크립트는 동작 |
| `lua` | `omarchy-menu-keybindings` Lua bind 캐시 (`hyprland.lua` 소스 파서) | CachyOS `lua` | OPTIONAL | 5.5.1-1 | no(목록 품질 저하) | `omarchy-cmd-present lua` 가드가 캐시를 끈다 | NONE — **M4 실측**: `lua` 가 없어도 스크립트 자체는 동작(Lua bind 메타만 빈 캐시) |
| `uwsm` / `uwsm-app` | `AppLibrary.launch`: `uwsm-app -- gtk-launch <id>.desktop` | Arch `uwsm` 패키지 — `cachy-omarchy-shell` hard depends | REQUIRED | 0.26.6-1 | no | 없음 | NONE — shim 은 삭제됐다. uwsm-app 은 uwsm 패키지가 소유하는 실제 바이너리이며, 어느 레이어도 PATH 를 조작하지 않는다(§45 개정). doctor 가 `pacman -Qqo` 로 소유권을 검사한다 |
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

## 클로저 전수 (생성)

이 표는 손으로 고치지 않는다. `tests/runtime/closure_check.py --emit-table` 이
생성하며, `tests/runtime/test_dependency_closure.sh` 가 파일 내용과 생성 결과가
일치하는지 검사한다(표를 손으로 고치면 그 테스트가 RED 로 잡는다). 등급 판정
규칙은 설계 문서 §4.2 에 있다.

**이 표는 `BASE` 등급을 뺀다.** `tests/data/command-packages.tsv` 의 전체
행수와 `BASE` 행수는 세어서 확인한다(하드코딩 금지):

```console
$ awk -F'\t' '!/^#/ && NF' tests/data/command-packages.tsv | wc -l
107
$ awk -F'\t' '!/^#/ && NF && $3=="BASE"' tests/data/command-packages.tsv | wc -l
63
```

135행이 아니라 107행이며, 그중 63행이 `BASE` 다(2026-08-21 실측 — 위 명령을 다시
돌리면 갱신된다). `BASE` 는 "기반 시스템 — 부재할 수 없는 패키지"(`coreutils`,
`bash`, `systemd` 등)라서 아예 declare 대상이 아니고, 그래서 표에서 빠진다. 그중
일부(`gsettings` 등)는 우리가 **직접 호출하는** 명령이기도 하다 — BASE 라는
등급이 "우리가 안 쓴다"는 뜻이 아니라 "declare 할 필요가 없다"는 뜻이라는 것을
혼동하지 말 것.

<!-- CLOSURE_BEGIN -->
| command | package | class | 근거 |
| --- | --- | --- | --- |
| `asdcontrol` | `asdcontrol` | UNPACKAGED | Apple Studio Display 밝기 제어(하드웨어 한정, omarchy-brightness-display-apple 이 sudo asdcontrol 을 부른다) — 공식 리포에도 AUR 에도 제공자가 없다(AUR RPC info/search 둘 다 0건 실측). 어디에도 선언하지 않는다; 사용자가 직접 빌드해야 하며, 없으면 그 헬퍼 하나만 동작하지 않는다. (미설치 — 검증 생략) |
| `brightnessctl` | `brightnessctl` | OPT | 내장 백라이트 — 이미 optdepends (미설치 — 검증 생략) |
| `checkupdates` | `pacman-contrib` | OPT | 업데이트 확인 메뉴 항목 |
| `ddcutil` | `ddcutil` | OPT | 외부 모니터 밝기 — 이미 optdepends (미설치 — 검증 생략) |
| `discord` | `discord` | OPT | Discord 커뮤니티 실행 메뉴 항목 |
| `dropbox-cli` | `dropbox-cli` | AUR | Dropbox 패널 대상 애플리케이션 — 사용자가 Dropbox 를 가짐으로써 선택하는 능력, C1 4번째 패턴에서 신규 발견. 리포엔 없고 AUR 전용(AUR RPC info 1건 실측). (미설치 — 검증 생략) |
| `ffmpeg` | `ffmpeg` | OPT | 화면 녹화 인코딩 |
| `git` | `git` | HARD | 테마 git clone/update 경로 — 기본 경로에서 도달하나 depends 없음 |
| `gpu-screen-recorder` | `gpu-screen-recorder` | OPT | 화면 녹화 메뉴 항목 (미설치 — 검증 생략) |
| `grim` | `grim` | HARD | 스크린샷 캡처 행의 구동 기계(§4.2 개정) — grim 없이는 그 메뉴 행 자체가 동작 못 함 |
| `gtk-update-icon-cache` | `gtk-update-icon-cache` | OPT | 웹앱 아이콘 설치 후처리 |
| `gum` | `gum` | HARD | 테마/온보딩 TUI 프롬프트 — 기본 경로에서 도달하나 depends 없음 |
| `hyprctl` | `hyprland` | HARD | 이미 depends(hyprland) |
| `hyprpicker` | `hyprpicker` | OPT | 색상 선택 메뉴 항목 (미설치 — 검증 생략) |
| `hyprsunset` | `hyprsunset` | HARD | nightlight 서비스가 기본 활성 — depends 없음 (미설치 — 검증 생략) |
| `iw` | `iw` | OPT | Wi-Fi 진단 메뉴 항목 |
| `jq` | `jq` | HARD | 클립보드/리마인더/OSD JSON — 이미 depends |
| `killall` | `psmisc` | OPT | 터미널/에디터 리로드 시그널 테마 훅 — omarchy-restart-terminal, omarchy-restart-opencode 가 killall -SIGUSR1/2 를 쓴다. 이미 depends(psmisc) |
| `mpv` | `mpv` | OPT | 미디어 미리보기 메뉴 항목 (미설치 — 검증 생략) |
| `nmcli` | `networkmanager` | OPT | 네트워크 관리 메뉴 항목 |
| `notify-send` | `libnotify` | HARD | omarchy-notification-send 폴백 경로 |
| `pactl` | `libpulse` | HARD | pactl 실소유 패키지는 pipewire-pulse 아닌 libpulse(pacman -Qqo 실측) — depends 는 pipewire-pulse 만 있음, MISSING_HARD_DEP 로 드러나는 진짜 결함 |
| `perl` | `perl` | HARD | 텍스트 처리 헬퍼 — 기본 경로에서 도달하나 depends 없음 |
| `pgrep` | `procps-ng` | HARD | 이미 depends |
| `pkill` | `procps-ng` | HARD | 이미 depends |
| `powerprofilesctl` | `power-profiles-daemon` | OPT | 전원 프로필 메뉴 항목 |
| `ps` | `procps-ng` | HARD | 이미 depends |
| `python3` | `python` | OPT | Dropbox 패널의 번들 상태 스크립트(status.py) 실행기 — Dropbox 통합을 선택한 사용자에게만 의미 있음, C1 4번째 패턴에서 신규 발견 |
| `slurp` | `slurp` | HARD | 스크린샷 영역 선택 행의 구동 기계(§4.2 개정) — grim과 짝을 이루는 동일 기능 |
| `sudo` | `sudo` | HARD | cachy-omarchy-init 이 락스크린 PAM 서비스 설정을 omarchy-apply-lock 에 위임하며 그것이 root 를 요구한다 — 메뉴 행이 아니라 우리 설치 경로에서 도달(컨트롤러 룰링, task-2) |
| `tailscale` | `tailscale` | OPT | Tailscale 패널 대상 애플리케이션 — QML .js command: 배열에서 도달(C1 수정 후 신규 발견), 사용자가 tailscale 을 가짐으로써 선택하는 능력 |
| `tensaku-edit` | `tensaku` | AUR | 클립보드/스크린샷 편집기 기본값(omarchy-clipboard-open:33) — 미설치 시 폴백 없음. 바이너리명 tensaku-edit 는 패키지명이 아니다 — 실제 AUR 패키지는 tensaku(AUR RPC info 1건 실측, tensaku-bin/tensaku-git 도 별도 존재). (미설치 — 검증 생략) |
| `tesseract` | `tesseract` | OPT | OCR 메뉴 항목 |
| `tmux` | `tmux` | OPT | tmux 테마 훅 — 이미 optdepends |
| `usbreset` | `usbutils` | OPT | USB 오디오 장치 복구 메뉴 항목 |
| `uwsm-app` | `uwsm` | HARD | 이미 depends(uwsm) |
| `v4l2-ctl` | `v4l-utils` | OPT | 웹캠 설정 메뉴 항목 |
| `which` | `which` | HARD | Tailscale 패널의 존재 확인 구동 기계(C1 4번째 패턴 .command= 에서 신규 발견) — 대상이 아니라 패널 자체가 이 명령 없이는 상태를 못 읽음 |
| `wl-copy` | `wl-clipboard` | HARD | 이미 depends |
| `wtype` | `wtype` | HARD | 이미 depends |
| `xdg-mime` | `xdg-utils` | HARD | 이미 depends |
| `xdg-settings` | `xdg-utils` | HARD | 이미 depends |
| `xdg-terminal-exec` | `xdg-terminal-exec` | AUR | 터미널 실행의 구동 기계(HARD 성격) — omarchy-launch-tui/omarchy-launch-terminal/omarchy-launch-floating-terminal-with-presentation 전부 이것 없이는 실패한다. 그럼에도 리포엔 없고 AUR 전용(pacman -Si 0건, AUR RPC info 1건 실측)이라 depends 로 못 두고 optdepends 로 내린다 — pacman -U 는 depends 를 리포/설치된 패키지로만 해결하므로(bin/install-packages:55) AUR 전용을 depends 에 넣으면 우리 패키지 자체가 설치 불가해진다. xdg-utils 는 이 바이너리를 제공하지 않는다(pacman -Ql 실측). (미설치 — 검증 생략) |
| `zbarimg` | `zbar` | OPT | QR 코드 스캔 메뉴 항목 |

스캐너가 헬퍼로 인정하지 않은 이름: 20개 (핀된 업스트림 bin/ 에 없음 — 파일 이름, 알림 hint 키, grep 패턴, 안내 문구 등 명령이 아닌 문자열)
- `omarchy-action`
- `omarchy-agent-usage`
- `omarchy-background`
- `omarchy-bar-drag-ghost`
- `omarchy-bar-move-ghost`
- `omarchy-battery`
- `omarchy-clipboard`
- `omarchy-emojis`
- `omarchy-exec`
- `omarchy-glyph`
- `omarchy-image-selector`
- `omarchy-lock-fingerprint`
- `omarchy-lock-password`
- `omarchy-lock-preview`
- `omarchy-notifications`
- `omarchy-polkit`
- `omarchy-reminders`
- `omarchy-system`
- `omarchy-theme`
- `omarchy-webapp-handler`
<!-- CLOSURE_END -->

### 스캐너의 알려진 한계 — 이 표가 완전성을 주장하지 않는 이유

이 표는 감사의 상한이 아니라 정적 분석이 잡아낼 수 있는 것의 스냅샷이다. 아래
세 가지는 코드 주석(`tests/runtime/closure_check.py`)에 이미 있는 한계를 그대로
옮긴 것이며, 부드럽게 쓰지 않는다.

1. **동적으로 조립되는 이름은 열거할 수 없다.** `"omarchy-installed-service-$service"`
   같은 문자열 연결/변수 보간 계열은 정적 분석으로 값 집합을 알 수 없다.
   `omarchy-bar:165` 가 실제로 이 형태로 헬퍼를 호출한다 — 그 호출은 이 표에
   나타나지 않는다.
2. **QML/JS 는 문자열 리터럴만 읽는다.** `"omarchy-" + kind` 같은 문자열 연결이나
   템플릿 리터럴로 조립되는 이름은 수확기가 보지 못한다. 현재 핀 트리에는 이
   용법이 0건이다(grep 확인, 2026-08-21) — 업스트림이 이 형태를 도입하면 조용히
   빠진다.
3. **인벤토리는 업스트림 `bin/` 만 덮는다.** `tests/data/upstream-helpers.txt` 는
   핀된 업스트림 커밋의 `bin/` 디렉터리를 스냅샷한 것이다. 업스트림이 헬퍼를 다른
   디렉터리로 옮기면, 인벤토리 재생성 테스트는 통과하면서도 그 헬퍼는 조용히
   "헬퍼 아님"으로 분류되어 그래프에서 빠진다 — `UNSTAGED_REACHABLE` 로도 잡히지
   않는다.

### `docs/COMMAND_AUDIT.md` 와의 범위 차이

`docs/COMMAND_AUDIT.md` 는 메뉴/셸이 도달하는 헬퍼를 감사 대상으로 삼고, 이 절의
클로저 스캐너는 다른 도달성 정의(BFS 루트 + 인벤토리)를 쓴다. 그래서
`tests/data/closure-exceptions.tsv` 의 예외 31건 중 21건은 `COMMAND_AUDIT.md` 에
자기 행이 아예 없다(측정 명령 아래). 이것은 결함이 아니라 **범위 차이**이며, 다음
사람이 21건을 "감사 누락"으로 오해하지 않도록 여기에 명시한다.

```console
$ awk -F'\t' '!/^#/ && NF {print $1}' tests/data/closure-exceptions.tsv | while read -r name; do
    grep -qE "^\| \`$name\` \|" docs/COMMAND_AUDIT.md || echo "$name"
  done | wc -l
21
```

또한 `tests/runtime/test_command_audit.sh` 는 `closure-exceptions.tsv` 를 읽지
않는다. 즉 이 두 문서가 서로 모순되지 않는지는 **기계가 아니라 사람이** 지킨다 —
이 절의 표가 코드와 동기화된다는 보장은 있어도, `COMMAND_AUDIT.md` 와의 정합은
그 보장 밖이다.

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
- **`uwsm-app` shim 은 삭제됐다** — M2/M3 시절 compat shim 이 실제 `uwsm-app` 유무에
  따라 위임/폴백했으나(M3 R06 마커 실측), `uwsm` 이 `cachy-omarchy-shell` 의 hard
  depends 가 되면서 제거했다. 이 호스트에는 `uwsm` 이 설치돼 있고(`pacman -Q uwsm`)
  `/usr/bin/uwsm-app` 은 uwsm 패키지 소유다 — doctor 가 `pacman -Qqo` 로 검사한다.
- **`omarchy.osd` 기동 불필요 확정** — 비활성 상태로 기동 정상. 상세는 `PLUGIN_AUDIT.md`.
