# 공식 패키지 감사

핀: Omarchy **4.0.0** / `f0020448ca87329199de7cb12f2015ebc4a3e5e7` (`upstream.lock`).

공식 PKGBUILD는 `basecamp/omarchy` 트리에 없다. 출처는 `https://github.com/omacom-io/omarchy-pkgs` (`pkgbuilds/`). 이 감사는 해당 저장소 `master` @ `7e448b90313fea4fb78da9a78607287691d3b241` (2026-08-15)에서 읽은 파일을 쓴다. 호스트에 `omarchy` / `omarchy-settings`를 설치하지 않았다.

**복사 금지:** 아래 `depends=()`를 `cachy-omarchy-shell` PKGBUILD에 그대로 옮기지 말 것.

---

## 1. `omarchy` 4.0.0-1

| 항목 | 값 |
| --- | --- |
| `_commit` | `f0020448ca87329199de7cb12f2015ebc4a3e5e7` (우리 핀과 동일) |
| `pkgver` / `pkgrel` | 4.0.0 / 1 |
| `arch` | any |
| `conflicts` | `omarchy-dev` |
| `source` | `git+https://github.com/basecamp/omarchy.git#commit=${_commit}` |
| 설치 루트 | `/usr/share/omarchy` + `/usr/bin/omarchy-*` |

### 1.1 의존 (공식 목록 — 참고만)

| 패키지 | 우리 분류 | 이유 |
| --- | --- | --- |
| `omarchy-keyring` | OPTIONAL | 공식 미러 서명용. 우리 패키지는 자체 빌드하면 불필요. 이 호스트에는 이미 설치됨(이 작업으로 설치하지 않음). |
| `omarchy-settings=${pkgver}` | UNSAFE | 버전 핀된 하드 의존. `/etc` 덮어쓰기·부트/로그인 스택과 한 쌍. |
| `limine`, `limine-mkinitcpio-hook`, `limine-snapper-sync`, `snapper` | UNSAFE | 부트로더/스냅샷. SPEC §5·§21. |
| `hyprland` | REQUIRED | 컴포지터. CachyOS에 있음. |
| `quickshell` | REQUIRED | 셸 런타임. CachyOS `0.3.0-2.1`. |
| `uwsm` | REQUIRED (개정) | 앱 실행이 `uwsm-app -- gtk-launch`를 씀. **개정: `cachy-omarchy-shell` 의 hard depends 가 됐고 `/usr/bin/uwsm-app` 은 uwsm 패키지 소유다 — M1 시점의 OPTIONAL/ADAPT(compat shim) 판정은 폐기.** 셸 기동 자체에는 불필요. |
| `sddm` | UNSAFE | 로그인 매니저 교체. |
| `xdg-desktop-portal-hyprland` | OPTIONAL | 포털. 메뉴 기동에 필수 아님. |
| `wireplumber`, `pipewire` | OPTIONAL | 오디오 플러그인용. |
| `gnome-keyring` | DISABLE | 전체 데스크톱 가정. |
| `gum` | OPTIONAL | 헬퍼 TUI. IPC/기동 경로에는 없음. |
| `jq` | OPTIONAL | 스크립트. `omarchy-shell` IPC는 `qs`+`timeout`. |
| `git` | OPTIONAL | 업데이트/체크아웃. |
| `perl` | REQUIRED(공식 주석) | 공식은 `/usr/bin/omarchy-shell`이 perl을 부른다고 함. **핀된 `bin/omarchy-shell`은 bash+`qs ipc`만 사용.** 재실측 후 M1에서 제외 가능. |
| `fakeroot`, `pacman-contrib` | DISABLE | 공식 업데이트 검사. |
| `ttf-jetbrains-mono-nerd-basic` | OPTIONAL | UI 폰트 가정. |

### 1.2 `package()`가 설치하는 것

- `bin/*` → `/usr/bin/<name>` + `/usr/share/omarchy/bin/<name>` 심볼릭. 제외: `omarchy-debug`, `omarchy-debug-idle`, `omarchy-upload-log`(settings가 담당).
- `default/libalpm/hooks/{00-omarchy-update-guard,10-omarchy-hyprland-reload-pause,90-omarchy-hyprland-reload-resume}.hook`
- `install/`, `themes/`, `migrations/`, `shell/` → `/usr/share/omarchy/`
- `version` → `/usr/share/omarchy/version`
- `migrations/*.sh` 마커 → `/etc/skel/.local/state/omarchy/migrations/`

`config/`는 이 패키지가 복사하지 않는다. 기본 `shell.json`·메뉴 JSONC는 settings/`default/` 쪽.

### 1.3 CachyOS에 가져오면 안 되는 것

- `omarchy-settings` 의존
- Limine/Snapper/SDDM
- libalpm 훅(공식 업데이트 가드·Hyprland reload pause)
- `/etc/skel` 마이그레이션 마커
- `install/`, `migrations/` 전체(ISO·재설치·전체 OS 가정)

---

## 2. `omarchy-settings` 4.0.0-1

같은 `_commit` / `pkgver`. `install=omarchy-settings.install`.

### 2.1 의존

`bash`, `curl`, `gum`, `hicolor-icon-theme`, `plymouth`.

optdepends에 Limine/Snapper/zram. **부트 스택은 `omarchy` 쪽에 하드 의존으로 있음.**

### 2.2 설치 경로 (요약)

- `/etc/skel/.config/**` ← 업스트림 `config/`
- `/etc/fastfetch/config.jsonc`
- `/usr/share/omarchy/config/`, `/usr/share/omarchy/default/`, `/usr/share/omarchy/applications/`
- `/usr/share/uwsm/env.d/10-omarchy`
- `/usr/lib/environment.d/10-omarchy-fcitx.conf`
- `/etc/fonts/conf.d/50-omarchy.conf`
- 다수 `/etc/systemd/**`, `/etc/sddm.conf.d/**`, `/etc/mkinitcpio.conf.d/**`, `/etc/limine-entry-tool.d/**`
- `/etc/snapper/config-templates/omarchy`
- SDDM 테마, Plymouth 테마, `/usr/local/share/wayland-sessions/omarchy.desktop`
- `/usr/share/omarchy/etc-overrides/` + post_install로 라이브 `/etc`에 `cp -f`

`backup=()`는 패키지가 소유한 `/etc` drop-in만 보호한다. etc-overrides는 보호하지 않는다.

### 2.3 `omarchy-settings.install` (매 설치/업그레이드 파괴적)

주석 그대로: 사용자 수정을 리셋한다.

| 대상 | SPEC |
| --- | --- |
| `/etc/os-release` → NAME=Omarchy, ID=omarchy | 금지 |
| `/etc/security/faillock.conf` | 금지 |
| `/etc/nsswitch.conf` | 금지 |
| `/etc/plymouth/plymouthd.conf` | 금지 |
| `/etc/skel/.bashrc` | 금지 |
| `/etc/cups/cups-browsed.conf` (있을 때만) | 금지 |

---

## 3. 금지 경로 교집합 (SPEC §27)

`omarchy-settings`가 소유하거나 스크립트로 덮어쓰는 경로:

```text
/etc/os-release
/etc/security/faillock.conf
/etc/nsswitch.conf
/etc/plymouth/
/etc/mkinitcpio.conf.d/
/etc/limine-entry-tool.d/
/etc/sddm.conf.d/
```

`cachy-omarchy-shell`은 이 경로를 소유하면 안 된다. 공식 `omarchy` 패키지도 `/etc/skel` 마이그레이션 마커를 심는다 — 우리 패키지에서 제외.

---

## 4. `shell/`이 어느 패키지에 있는가

공식: **`omarchy`만** `cp -a shell "$pkgdir/usr/share/omarchy/"`.

런타임은 `OMARCHY_PATH` (uwsm/세션 env, 기본 가정 `/usr/share/omarchy`) + `quickshell -n -p "$OMARCHY_PATH/shell"`.

우리 선호 루트: `/usr/share/cachy-omarchy/upstream/` + 래퍼가 `OMARCHY_PATH`를 설정. QML에는 `/usr/share/omarchy` 하드코딩이 없다 (`ENV-COMPATIBLE`).

메뉴 기본 정의는 `OMARCHY_PATH/default/omarchy/omarchy-menu.jsonc` — 공식 `omarchy` 패키지는 `default/`를 설치하지 않고 **`omarchy-settings`가** `/usr/share/omarchy/default/`로 복사한다. 셸만 패키징하면 메뉴 JSONC가 빠진다. 우리 셸 패키지에 `default/omarchy/omarchy-menu.jsonc`(및 필요 시 `config/omarchy/shell.json`)를 **settings 없이** 포함해야 한다.

---

## 5. 호스트 실측 (2026-08-16)

```text
os: CachyOS Linux (ID=cachyos)
kernel: 7.1.8-1-cachyos
omarchy: not installed
omarchy-settings: not installed
omarchy-keyring: 20251027-1 (pre-existing)
quickshell: 0.3.0-2.1
hyprland: 0.56.2-1
jq: 1.8.2-1.1
perl: 5.42.2-2.1
gum: 0.17.0-1.1
```

---

## 6. Exit: minimum safe subset

What is the minimum safe subset of Omarchy Quattro required to run `omarchy.menu` on CachyOS?

**Answer:** The entire `shell/` tree from commit `f0020448…`, plus `default/omarchy/omarchy-menu.jsonc` (officially shipped by `omarchy-settings`, not by `omarchy`), a pinned `version` file, Quickshell, Hyprland, and wrappers that set `OMARCHY_PATH` and exec `quickshell -n -p "$OMARCHY_PATH/shell"` / `qs ipc … toggle omarchy.menu`. Do not install official `omarchy` or `omarchy-settings`. Disable bar/lock/notifications/idle via `disabledPlugins`. Launch apps through `gtk-launch`. **(개정: 이 절의 M1 판정 — 필요 시 `uwsm-app` 을 걷어내 적응한다 — 는 폐기다. uwsm 은 `cachy-omarchy-shell` 의 hard depends 가 됐고 `/usr/bin/uwsm-app` 은 uwsm 패키지 소유 실제 바이너리이므로 걷어내지 않는다. 위 표의 `uwsm` 행 참조.)**

한국어: 공식 메타패키지가 아니라, 핀된 셸 트리와 메뉴 JSONC와 환경 변수 래퍼만 있으면 된다.
