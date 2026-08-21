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
| `config/omarchy/shell.json` | `shell.qml` `defaultsPath` | 공식은 settings | OPTIONAL | n/a | yes | `builtinShellConfig` | ENVIRONMENT — **실제 배포본은 `overlay/defaults/shell.json`, `disabledPlugins` 없음 → 전 플러그인 활성**(방향 전환 2026-08-17, `docs/PLUGIN_AUDIT.md` 참고). v0.1 시절 "최소 json이 안전" 판단은 뒤집혔다 |
| `themes/` | 공식 `omarchy`가 설치. QML에서 경로 문자열 미검출 | 공식 `omarchy` | OPTIONAL | n/a | yes | 셸 내장 Color | NONE initially |
| `bin/omarchy-launch-shell` | 장기 프로세스 | 공식 `omarchy` | REQUIRED(logic) | n/a | no | systemd ExecStart가 `quickshell` 직접 호출 | WRAPPER — `cachy-omarchy-shell --run` |
| `bin/omarchy-shell` | IPC. 기동하지 않음 | 공식 `omarchy` | REQUIRED(logic) | n/a | no | `qs ipc` 직접 | WRAPPER — `cachy-omarchy-launcher` 등 |
| `perl` | `omarchy-menu-select` 의 select payload JSON | CachyOS `perl` | REQUIRED for keybindings menu | installed (JSON::PP 확인) | no(키바인딩 UI 한정) | 없음 | NONE — **M4 실측**: `omarchy-menu-select` 가 `perl -MEncode -MJSON::PP` 를 2회 호출해 payload 를 만든다. **M2 실측: 기동 경로 미사용** 유지 |
| `jq` | `omarchy-menu-keybindings` `lua_string()` (dispatch 경로) | CachyOS `jq` | OPTIONAL | 1.8.2-1.1 | yes for menu open | 메뉴는 QML이 JSONC 파싱 | NONE — **M4 실측**: 선택한 bind 를 `hyprctl dispatch` 할 때만 `jq -Rnr @json` 으로 Lua 문자열 인용. 목록/`--print` 경로는 미사용. **M2 실측: 기동 경로 미사용** 유지 |
| `gum` | 다수 헬퍼 TUI | CachyOS `gum` | OPTIONAL | installed | yes for menu open | 없음 | NONE — **M4 실측: 키바인딩 경로 미사용** — `omarchy-menu-keybindings` / `omarchy-menu-select` / `omarchy-cmd-present` 에 `gum` 0 매치(grep). 선택 UI 는 gum 이 아니라 `summon omarchy.menu` select mode. **M2 실측: 기동 경로 미사용** 유지 |
| `xkbcli` | `omarchy-menu-keybindings` `parse_keycodes` — `xkbcli compile-keymap` | CachyOS `libxkbcommon` | OPTIONAL | installed | no(목록 품질 저하) | 하드코딩 code: 폴백 테이블 | NONE — **M4 실측**: 없으면 `code:NNN` bind 가 심볼로 안 풀릴 뿐 스크립트는 동작 |
| `lua` | `omarchy-menu-keybindings` Lua bind 캐시 (`hyprland.lua` 소스 파서) | CachyOS `lua` | OPTIONAL | 5.5.1-1 | no(목록 품질 저하) | `omarchy-cmd-present lua` 가드가 캐시를 끈다 | NONE — **M4 실측**: `lua` 가 없어도 스크립트 자체는 동작(Lua bind 메타만 빈 캐시) |
| `uwsm` / `uwsm-app` | `AppLibrary.launch`: `uwsm-app -- gtk-launch <id>.desktop` | Arch `uwsm` 패키지 — `cachy-omarchy-shell` hard depends | REQUIRED | 0.26.6-1 | no | 없음 | NONE — shim 은 삭제됐다. uwsm-app 은 uwsm 패키지가 소유하는 실제 바이너리이며, 어느 레이어도 PATH 를 조작하지 않는다(§45 개정). doctor 가 `pacman -Qqo` 로 소유권을 검사한다 |
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

## 클로저 전수 (생성)

이 표는 손으로 고치지 않는다. `tests/runtime/closure_check.py --emit-table` 이
생성하며, `tests/runtime/test_dependency_closure.sh` 가 파일 내용과 생성 결과가
일치하는지 검사한다(표를 손으로 고치면 그 테스트가 RED 로 잡는다). 표 바로
아래 행수/`BASE` 개수 요약 줄도 같은 생성 출력의 일부다 — 손으로 옮겨 적은
숫자가 아니라 표와 함께 단언된다.

**이 표는 `BASE` 등급을 뺀다.** `BASE` 는 "기반 시스템 — 부재할 수 없는
패키지"(`coreutils`, `bash`, `systemd` 등)라서 아예 declare 대상이 아니고,
그래서 표에서 빠진다. 그중 일부(`gsettings` 등)는 우리가 **직접 호출하는**
명령이기도 하다 — BASE 라는 등급이 "우리가 안 쓴다"는 뜻이 아니라 "declare 할
필요가 없다"는 뜻이라는 것을 혼동하지 말 것. 정확한 개수는 표 바로 아래
생성된 요약 줄을 본다(마커 안이라 맵이 바뀌면 함께 갱신된다).

### 등급 규칙 — `BASE` / `HARD` / `OPT` / `AUR` / `UNPACKAGED`

실행 중 이 등급 체계가 개정됐다. 아래 표의 근거 열에 붙는 "(§4.2 개정)" 표기가
가리키는 것이 이 개정이다 — 설계 문서 자체는 `docs/superpowers/`(gitignore 됨)
아래 있어 저장소를 물려받는 사람은 읽을 수 없으므로, 그 요지를 여기 직접 적는다.

원래는 "메뉴에서 도달하면 HARD"였다. 그 규칙은 성립하지 않았다 — discord/mpv
처럼 메뉴 항목에서 도달해도 하드 의존으로 볼 수 없는 사례가 나와
`BASE`/`HARD`/`OPT` 3분기로 개정했다:

- **BASE** — 기반 시스템 패키지(`coreutils`/`bash`/`systemd` 등). 부재할 수
  없으므로 declare 하지 않는다. 위 표에서 제외된다.
- **HARD** — 기동/기본 활성 경로에서 도달하는 명령. `depends` 로 선언한다
  (이미 선언돼 있으면 근거 열에 "이미 depends"로 남는다).
- **OPT** — 사용자가 그 기능을 명시적으로 선택해야 도달하는 명령(메뉴 항목,
  패널 대상 애플리케이션 등). `optdepends` 로 선언한다.
- **AUR** — 실제 Arch 패키지가 존재하지만 공식 리포가 아니라 AUR 에만 있다.
  `pacman -U` 는 `depends` 를 리포/이미 설치된 패키지로만 해결하므로
  (`bin/install-packages:55`), AUR 전용 패키지를 `depends` 에 넣으면 우리
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
(`tests/data/upstream-helpers.txt`)을 ground truth 로 쓴다 — 이름이 그 목록에
없으면 헬퍼로 인정하지 않는다(아래 "스캐너가 헬퍼로 인정하지 않은 이름" 목록).
핀을 옮길 때 이 인벤토리를 함께 재생성해야 하는 이유와 절차는 `UPSTREAM.md`
"Moving the pin" 절에 있다.

<!-- CLOSURE_BEGIN -->
| command | package | class | 근거 |
| --- | --- | --- | --- |
| `asdcontrol` | `asdcontrol` | UNPACKAGED | Apple Studio Display 밝기 제어(하드웨어 한정, omarchy-brightness-display-apple 이 sudo asdcontrol 을 부른다) — 공식 리포에도 AUR 에도 제공자가 없다(AUR RPC info/search 둘 다 0건 실측). 어디에도 선언하지 않는다; 사용자가 직접 빌드해야 하며, 없으면 그 헬퍼 하나만 동작하지 않는다. |
| `awk` | `gawk` | BASE | 기반 |
| `base64` | `coreutils` | BASE | 기반 |
| `basename` | `coreutils` | BASE | 기반 |
| `bash` | `bash` | BASE | 기반 |
| `bluetoothctl` | `bluez-utils` | OPT | 블루투스 컨트롤러 부재 환경(데스크톱) 존재 — 위젯은 가드로 숨는다 |
| `brightnessctl` | `brightnessctl` | OPT | 내장 백라이트 — 이미 optdepends |
| `busctl` | `systemd` | BASE | 기반 |
| `cat` | `coreutils` | BASE | 기반 |
| `checkupdates` | `pacman-contrib` | OPT | 업데이트 확인 메뉴 항목 |
| `chmod` | `coreutils` | BASE | 기반 |
| `cmp` | `diffutils` | BASE | 기반(base 그룹) |
| `cp` | `coreutils` | BASE | 기반 |
| `curl` | `curl` | BASE | 이미 선언된 의존의 전이 의존(§4.2 개정) |
| `cut` | `coreutils` | BASE | 기반 |
| `date` | `coreutils` | BASE | 기반 |
| `ddcutil` | `ddcutil` | OPT | 외부 모니터 밝기 — 이미 optdepends |
| `dirname` | `coreutils` | BASE | 기반 |
| `discord` | `discord` | OPT | Discord 커뮤니티 실행 메뉴 항목 |
| `dropbox-cli` | `dropbox-cli` | AUR | Dropbox 패널 대상 애플리케이션 — 사용자가 Dropbox 를 가짐으로써 선택하는 능력, C1 4번째 패턴에서 신규 발견. 리포엔 없고 AUR 전용(AUR RPC info 1건 실측). |
| `env` | `coreutils` | BASE | 기반 |
| `fc-list` | `fontconfig` | BASE | 이미 선언된 의존의 전이 의존(§4.2 개정) |
| `fc-match` | `fontconfig` | BASE | 이미 선언된 의존의 전이 의존(§4.2 개정) |
| `ffmpeg` | `ffmpeg` | OPT | 화면 녹화 인코딩 |
| `file` | `file` | BASE | 기반(base 그룹) |
| `find` | `findutils` | BASE | 기반 |
| `flock` | `util-linux` | BASE | 기반 |
| `git` | `git` | HARD | 테마 git clone/update 경로 — 기본 경로에서 도달하나 depends 없음 |
| `gpu-screen-recorder` | `gpu-screen-recorder` | OPT | 화면 녹화 메뉴 항목 |
| `grep` | `grep` | BASE | 기반 |
| `grim` | `grim` | HARD | 스크린샷 캡처 행의 구동 기계(§4.2 개정) — grim 없이는 그 메뉴 행 자체가 동작 못 함 |
| `gsettings` | `glib2` | BASE | hyprland/quickshell/uwsm 이 모두 전이로 끌어온다(pactree 실측) — 이미 선언된 의존의 전이 의존(§4.2 개정). GNOME/GTK 색 구성 테마 훅(omarchy-theme-set-gnome)에서 도달 |
| `gtk-update-icon-cache` | `gtk-update-icon-cache` | OPT | 웹앱 아이콘 설치 후처리 |
| `gum` | `gum` | HARD | 테마/온보딩 TUI 프롬프트 — 기본 경로에서 도달하나 depends 없음 |
| `head` | `coreutils` | BASE | 기반 |
| `hyprctl` | `hyprland` | HARD | 이미 depends(hyprland) |
| `hyprpicker` | `hyprpicker` | OPT | 색상 선택 메뉴 항목 |
| `hyprsunset` | `hyprsunset` | HARD | nightlight 서비스가 기본 활성 — depends 없음 |
| `id` | `coreutils` | BASE | 기반 |
| `install` | `coreutils` | BASE | 기반 |
| `ip` | `iproute2` | BASE | base 그룹 — 이미 선언된 의존의 전이 의존(§4.2 개정) |
| `iw` | `iw` | OPT | Wi-Fi 진단 메뉴 항목 |
| `jq` | `jq` | HARD | 클립보드/리마인더/OSD JSON — 이미 depends |
| `kill` | `util-linux` | BASE | 기반 |
| `killall` | `psmisc` | OPT | 터미널/에디터 리로드 시그널 테마 훅 — omarchy-restart-terminal, omarchy-restart-opencode 가 killall -SIGUSR1/2 를 쓴다. 이미 depends(psmisc) |
| `list.sh` | `cachy-omarchy-shell` | BASE | image-picker 플러그인이 함께 배포하는 번들 스크립트 — Arch 패키지가 아니라 같은 패키지 파일트리 안의 파일이라 항상 존재, C1 4번째 패턴에서 신규 발견 |
| `ln` | `coreutils` | BASE | 기반 |
| `ls` | `coreutils` | BASE | 기반 |
| `md5sum` | `coreutils` | BASE | 기반 |
| `mkdir` | `coreutils` | BASE | 기반 |
| `mktemp` | `coreutils` | BASE | 기반 |
| `modprobe` | `kmod` | BASE | 기반(base 그룹) |
| `mpv` | `mpv` | OPT | 미디어 미리보기 메뉴 항목 |
| `mv` | `coreutils` | BASE | 기반 |
| `nmcli` | `networkmanager` | OPT | 네트워크 관리 메뉴 항목 |
| `nohup` | `coreutils` | BASE | 기반 |
| `notify-send` | `libnotify` | HARD | omarchy-notification-send 폴백 경로 |
| `nproc` | `coreutils` | BASE | 기반 |
| `pactl` | `libpulse` | HARD | pactl 실소유 패키지는 pipewire-pulse 아닌 libpulse(pacman -Qqo 실측) — depends 는 pipewire-pulse 만 있음, MISSING_HARD_DEP 로 드러나는 진짜 결함 |
| `perl` | `perl` | HARD | 텍스트 처리 헬퍼 — 기본 경로에서 도달하나 depends 없음 |
| `pgrep` | `procps-ng` | HARD | 이미 depends |
| `pkexec` | `polkit` | BASE | 이미 선언된 의존의 전이 의존(§4.2 개정) |
| `pkill` | `procps-ng` | HARD | 이미 depends |
| `powerprofilesctl` | `power-profiles-daemon` | OPT | 전원 프로필 메뉴 항목 |
| `printf` | `coreutils` | BASE | 기반 |
| `ps` | `procps-ng` | HARD | 이미 depends |
| `python3` | `python` | OPT | Dropbox 패널의 번들 상태 스크립트(status.py) 실행기 — Dropbox 통합을 선택한 사용자에게만 의미 있음, C1 4번째 패턴에서 신규 발견 |
| `readlink` | `coreutils` | BASE | 기반 |
| `realpath` | `coreutils` | BASE | 기반 |
| `rfkill` | `util-linux` | BASE | 기반 |
| `rm` | `coreutils` | BASE | 기반 |
| `rmdir` | `coreutils` | BASE | 기반 |
| `sed` | `sed` | BASE | 기반 |
| `setpriv` | `util-linux` | BASE | 기반 |
| `setsid` | `util-linux` | BASE | 기반 |
| `sleep` | `coreutils` | BASE | 기반 |
| `slurp` | `slurp` | HARD | 스크린샷 영역 선택 행의 구동 기계(§4.2 개정) — grim과 짝을 이루는 동일 기능 |
| `sort` | `coreutils` | BASE | 기반 |
| `stat` | `coreutils` | BASE | 기반 |
| `sudo` | `sudo` | HARD | cachy-omarchy-init 이 락스크린 PAM 서비스 설정을 omarchy-apply-lock 에 위임하며 그것이 root 를 요구한다 — 메뉴 행이 아니라 우리 설치 경로에서 도달(컨트롤러 룰링, task-2) |
| `systemctl` | `systemd` | BASE | 기반 |
| `systemd-run` | `systemd` | BASE | 기반 |
| `tac` | `coreutils` | BASE | 기반 |
| `tailscale` | `tailscale` | OPT | Tailscale 패널 대상 애플리케이션 — QML .js command: 배열에서 도달(C1 수정 후 신규 발견), 사용자가 tailscale 을 가짐으로써 선택하는 능력 |
| `tee` | `coreutils` | BASE | 기반 |
| `tensaku-edit` | `tensaku` | AUR | 클립보드/스크린샷 편집기 기본값(omarchy-clipboard-open:33) — 미설치 시 폴백 없음. 바이너리명 tensaku-edit 는 패키지명이 아니다 — 실제 AUR 패키지는 tensaku(AUR RPC info 1건 실측, tensaku-bin/tensaku-git 도 별도 존재). |
| `tesseract` | `tesseract` | OPT | OCR 메뉴 항목 |
| `timedatectl` | `systemd` | BASE | 기반 |
| `timeout` | `coreutils` | BASE | 기반 |
| `tmux` | `tmux` | OPT | tmux 테마 훅 — 이미 optdepends |
| `top` | `procps-ng` | HARD | procps-ng 가 제공(pacman -Ql 실측) — omarchy-system-stats CPU 통계 경로. procps-ng 는 이미 depends |
| `touch` | `coreutils` | BASE | 기반 |
| `tr` | `coreutils` | BASE | 기반 |
| `update-desktop-database` | `desktop-file-utils` | OPT | webapp 제거 후 desktop DB 갱신(omarchy-webapp-remove) — 이전에는 BASE 로 적혀 있었으나 선언된 depends 의 전이 폐포에도 base/base-devel 에도 없다(BASE 정당성 검사 실측) |
| `upower` | `upower` | HARD | Power 패널 구동 기계 — Panel.qml:210이 omarchy-battery-status --shell을 무조건 실행 |
| `usbreset` | `usbutils` | OPT | USB 오디오 장치 복구 메뉴 항목 |
| `uwsm-app` | `uwsm` | HARD | 이미 depends(uwsm) |
| `v4l2-ctl` | `v4l-utils` | OPT | 웹캠 설정 메뉴 항목 |
| `which` | `which` | HARD | Tailscale 패널의 존재 확인 구동 기계(C1 4번째 패턴 .command= 에서 신규 발견) — 대상이 아니라 패널 자체가 이 명령 없이는 상태를 못 읽음 |
| `wl-copy` | `wl-clipboard` | HARD | 이미 depends |
| `wpctl` | `wireplumber` | HARD | 오디오 입력/싱크 헬퍼 구동 기계 — wireplumber 이미 depends |
| `wtype` | `wtype` | HARD | 이미 depends |
| `xargs` | `findutils` | BASE | 기반 |
| `xdg-mime` | `xdg-utils` | HARD | 이미 depends |
| `xdg-settings` | `xdg-utils` | HARD | 이미 depends |
| `xdg-terminal-exec` | `xdg-terminal-exec` | AUR | 터미널 실행의 구동 기계(HARD 성격) — omarchy-launch-tui/omarchy-launch-terminal/omarchy-launch-floating-terminal-with-presentation 전부 이것 없이는 실패한다. 그럼에도 리포엔 없고 AUR 전용(pacman -Si 0건, AUR RPC info 1건 실측)이라 depends 로 못 두고 optdepends 로 내린다 — pacman -U 는 depends 를 리포/설치된 패키지로만 해결하므로(bin/install-packages:55) AUR 전용을 depends 에 넣으면 우리 패키지 자체가 설치 불가해진다. xdg-utils 는 이 바이너리를 제공하지 않는다(pacman -Ql 실측). |
| `xkbcli` | `libxkbcommon` | BASE | 이미 선언된 의존의 전이 의존(§4.2 개정) |
| `zbarimg` | `zbar` | OPT | QR 코드 스캔 메뉴 항목 |

tests/data/command-packages.tsv: 전체 112행, 위 표에는 도달한 108행이 모두 실린다(BASE 59행 포함 — BASE 는 declare 대상이 아닐 뿐 검사 대상에서 빠지지 않는다)

docs/COMMAND_AUDIT.md 의 DISABLED 행으로 메뉴 루트에서 억제된 이름: 92개 (의도적으로 미지원인 Omarchy OS 스택 — 예외 파일과 달리 사유·신선도 검사가 없는 통로다)
- `omarchy-branding-about`
- `omarchy-branding-screensaver`
- `omarchy-channel-current`
- `omarchy-channel-set`
- `omarchy-default-agent`
- `omarchy-drive-password`
- `omarchy-emacs`
- `omarchy-games-retro-install`
- `omarchy-hw-fingerprint`
- `omarchy-hw-hybrid-gpu`
- `omarchy-install-ai-chatgpt`
- `omarchy-install-and-launch`
- `omarchy-install-app`
- `omarchy-install-browser`
- `omarchy-install-chromium-google-account`
- `omarchy-install-dev-env`
- `omarchy-install-docker-dbs`
- `omarchy-install-editor-emacs`
- `omarchy-install-editor-helix`
- `omarchy-install-editor-vscode`
- `omarchy-install-editor-zed`
- `omarchy-install-font`
- `omarchy-install-gaming-battlenet`
- `omarchy-install-gaming-geforce-now`
- `omarchy-install-gaming-heroic`
- `omarchy-install-gaming-lutris`
- `omarchy-install-gaming-retroarch`
- `omarchy-install-gaming-steam`
- `omarchy-install-gaming-xbox-cloud`
- `omarchy-install-gaming-xbox-controllers`
- `omarchy-install-preinstalls`
- `omarchy-install-service-1password`
- `omarchy-install-service-dropbox`
- `omarchy-install-service-nordvpn`
- `omarchy-install-service-once`
- `omarchy-install-service-signal`
- `omarchy-install-service-spotify`
- `omarchy-install-service-tailscale`
- `omarchy-install-terminal`
- `omarchy-launch-about`
- `omarchy-launch-floating-terminal-with-presentation`
- `omarchy-launch-screensaver`
- `omarchy-menu-herdr-keybindings`
- `omarchy-menu-plugin`
- `omarchy-menu-share`
- `omarchy-pkg-aur-install`
- `omarchy-pkg-install`
- `omarchy-pkg-present`
- `omarchy-pkg-remove`
- `omarchy-plugin-add`
- `omarchy-plymouth-reset`
- `omarchy-plymouth-set-by-theme`
- `omarchy-plymouth-switcher`
- `omarchy-refresh-hyprland`
- `omarchy-refresh-hyprsunset`
- `omarchy-refresh-plymouth`
- `omarchy-refresh-shell`
- `omarchy-refresh-tmux`
- `omarchy-remove-browser`
- `omarchy-remove-dev-env`
- `omarchy-remove-gaming-battlenet`
- `omarchy-remove-gaming-geforce-now`
- `omarchy-remove-gaming-heroic`
- `omarchy-remove-gaming-lutris`
- `omarchy-remove-gaming-minecraft`
- `omarchy-remove-gaming-retroarch`
- `omarchy-remove-gaming-steam`
- `omarchy-remove-gaming-xbox-cloud`
- `omarchy-remove-gaming-xbox-controllers`
- `omarchy-remove-preinstalls`
- `omarchy-remove-security-fido2`
- `omarchy-remove-security-fingerprint`
- `omarchy-remove-security-sshd`
- `omarchy-remove-service-dropbox`
- `omarchy-remove-service-tailscale`
- `omarchy-restart-hyprsunset`
- `omarchy-restart-xcompose`
- `omarchy-setup-direct-boot`
- `omarchy-setup-security-fido2`
- `omarchy-setup-security-fingerprint`
- `omarchy-setup-security-sshd`
- `omarchy-system-factory-reset`
- `omarchy-theme-bg-install`
- `omarchy-toggle-crash-capture`
- `omarchy-toggle-hybrid-gpu`
- `omarchy-transcode`
- `omarchy-update`
- `omarchy-update-firmware`
- `omarchy-voxtype-install`
- `omarchy-voxtype-remove`
- `omarchy-webapp-handler`
- `omarchy-windows-vm`

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
네 가지는 코드 주석(`tests/runtime/closure_check.py`)에 이미 있는 한계를 그대로
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

4. **가장 큰 억제 통로는 이 문서가 아니라 `docs/COMMAND_AUDIT.md` 에 있다.**
   스캐너는 메뉴 루트(`omarchy-menu.jsonc`)에서 이름을 수확할 때,
   `docs/COMMAND_AUDIT.md` 에서 `DISABLED` 로 표시된 행을 정규식으로 긁어
   **차감한다**. 현재 실측 92개다 — `tests/data/closure-exceptions.tsv` 의
   예외 행보다 훨씬 크다. 차감되는 이름 대부분은 우리가 의도적으로 취하지 않는
   Omarchy OS 스택(공장 초기화, plymouth, 채널, install-gaming 계열)이므로
   결정 자체는 정당하다.

   정당하지 않았던 것은 **장부**다. 예외 파일은 사유가 파싱으로 강제되고
   `STALE_EXCEPTION` 으로 신선도가 검사되며 이 문서에서 논의된다. 반면 이
   `DISABLED` 통로는 사유가 필수가 아니고, 스테이징되거나 도달 불가가 되어도
   아무도 알려주지 않으며, 생성 문서에 전혀 나타나지 않았다. 이번 wave 에서
   개수와 이름을 위 생성 블록이 함께 내보내도록 바꿔 **숫자가 서술이 아니라
   단언**이 되게 했지만, 사유 강제와 신선도 검사는 여전히 없다. 이 통로를 통해
   무엇이 사라지는지 알고 싶으면 위 생성 블록의 마지막 목록을 읽어야 한다.

### `docs/COMMAND_AUDIT.md` 와의 범위 차이

`docs/COMMAND_AUDIT.md` 는 메뉴/셸이 도달하는 헬퍼를 감사 대상으로 삼고, 이 절의
클로저 스캐너는 다른 도달성 정의(BFS 루트 + 인벤토리)를 쓴다. 그래서
`tests/data/closure-exceptions.tsv` 의 잔여 예외 22건 중 12건은 `COMMAND_AUDIT.md` 에
자기 행이 아예 없다(측정 명령 아래). 이것은 결함이 아니라 **범위 차이**이며, 다음
사람이 12건을 "감사 누락"으로 오해하지 않도록 여기에 명시한다. 행 수는 주석을
제외한 `closure-exceptions.tsv` 데이터 행이다(v0.9 의 31건에서 가시 UI 9개를
스테이징하며 22건이 남았다).

```console
$ awk -F'\t' '!/^#/ && NF {print $1}' tests/data/closure-exceptions.tsv | while read -r name; do
    grep -qE "^\| \`$name\` \|" docs/COMMAND_AUDIT.md || echo "$name"
  done | wc -l
12
```

또한 `tests/runtime/test_command_audit.sh` 는 `closure-exceptions.tsv` 를 읽지
않는다. 즉 이 두 문서가 서로 모순되지 않는지는 **기계가 아니라 사람이** 지킨다 —
이 절의 표가 코드와 동기화된다는 보장은 있어도, `COMMAND_AUDIT.md` 와의 정합은
그 보장 밖이다.

v0.10.0 이 `omarchy-battery-status` 를 포함한 가시 UI 헬퍼 9개를 스테이징하면서,
이전에 여기 적혀 있던 Power 패널 배터리 상세 행 결손은 닫혔다. weather 위젯의
외부 요청(wttr.in IP 조회는 비저장, 패널은 Open-Meteo 예보/지오코딩도 사용)은
스테이징 결손이 아니라 문서화된 표면이다(`docs/CLOSURE_PRIORITY.md`). 남은
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
