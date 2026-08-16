# 헬퍼 명령 감사

시작점: `bin/omarchy-shell`, `bin/omarchy-launch-shell`, `shell/`, `default/omarchy/omarchy-menu.jsonc`.

분류: `SAFE` | `ADAPTED` | `DISABLED`  
조치: `package` | `copy` | `wrapper` | `disable`

전역 `/usr/bin`에 가짜 `omarchy-*`를 대량 설치하지 말 것. 필요 시 `PATH=/usr/lib/cachy-omarchy/compat/bin:...` (SPEC §44–45).

---

## 기동·IPC (v0.1 핵심)

| command | called from | purpose | deps | class | action |
| --- | --- | --- | --- | --- | --- |
| `omarchy-launch-shell` | 세션/유닛 | `quickshell -n -p $OMARCHY_PATH/shell` + journal + hyprctl 재시도 | quickshell, hyprctl, systemd-cat | ADAPTED | wrapper — `cachy-omarchy-shell --run`. 로직 재사용 가능, 이름/경로만 우리 것 |
| `omarchy-shell` | 핫키, 메뉴, 플러그인 | 기동하지 않음. `qs ipc` 전달 | OMARCHY_PATH, qs, timeout | ADAPTED | wrapper — `cachy-omarchy-launcher`가 `shell toggle omarchy.menu` 호출 |
| `omarchy-restart-shell` | 업데이트/디버그 | 기존 qs 인스턴스 kill 후 재기동 | quickshell kill | ADAPTED | wrapper later (`cachy-omarchy-reload`). M0에서 구현 없음 |
| `quickshell` / `qs` | 위 두 명령 | 엔진 | CachyOS 패키지 | SAFE | package (의존) |

---

## 메뉴·런처

| command | called from | purpose | class | action |
| --- | --- | --- | --- | --- |
| `uwsm-app -- gtk-launch` | `AppLibrary.qml` | 앱 실행 | ADAPTED | wrapper — uwsm 없으면 `gtk-launch` |
| `omarchy-remove-launcher-entry` | `AppLibrary.remove` | 숨김 항목 | OPTIONAL / ADAPTED | copy into compat if hide-from-menu를 살릴 때 |
| 메뉴 `action` 문자열 전반 | `omarchy-menu.jsonc` | 테마/락/캡처/네트워크/업데이트 등 | 대부분 DISABLED | disable — 항목은 JSONC에 남아도 실행 시 실패. v0.1은 앱 목록 + 안전 항목만 남기거나 `when`으로 숨김 |

대표 `DISABLED` (전체 OS 가정):

```text
omarchy-theme-set / omarchy-theme-switcher
omarchy-plymouth-*
omarchy-system-lock / omarchy-launch-screensaver
omarchy-refresh-config / omarchy-reinstall-configs
omarchy-update* / omarchy-pkg-*
omarchy-launch-about (브랜딩/os-release)
```

`systemctl suspend|hibernate` 등 표준 명령은 SAFE. `omarchy-system-logout|reboot|shutdown`은 감사 후 ADAPTED 또는 disable.

---

## 키바인딩 UI

| command | called from | purpose | class | action |
| --- | --- | --- | --- | --- |
| `omarchy-menu-keybindings` | 메뉴 `learn.keybindings` | `hyprctl binds` + Lua 캐시 + 검색 메뉴 | ADAPTED | wrapper/copy — SUPER+K가 이 명령을 부르게. 데이터는 CachyOS Hyprland 설정. gum/jq/lua/xkbcli 의존 감사는 M4 |
| `omarchy-menu-tmux-keybindings` | 메뉴 | Tmux 전용 | DISABLED | disable |
| `omarchy-menu-herdr-keybindings` | 메뉴 | Herdr 전용 | DISABLED | disable |

별도 QML 키바인드 플러그인은 없다. UI는 이 헬퍼(+ 메뉴 오버레이)다.

---

## 셸 인프라 (기본 활성 플러그인이 부름)

idle/lock/osd/battery가 켜져 있으면 아래가  invok된다. v0.1은 플러그인 DISABLE이 우선.

| command | plugin | class | action |
| --- | --- | --- | --- |
| `omarchy-launch-screensaver` | idle | DISABLED | disable plugin |
| `omarchy-system-lock` | idle | DISABLED | disable plugin |
| `omarchy-system-wake` | idle | DISABLED | disable plugin |
| `omarchy-battery-low` / `omarchy-powerprofiles-set` | battery | DISABLED | disable plugin |
| `omarchy-notification-send` | 여러 패널 | DISABLED until notifications ENABLE | disable |
| `omarchy-shell osd ...` | AppLibrary 런치 OSD | OPTIONAL | osd 플러그인 정책에 따름 |

---

## 정책

1. 기동·IPC·앱 실행만 래퍼로 살린다.
2. 메뉴 JSONC의 Omarchy-OS 액션은 끄거나 실패해도 셸이 죽지 않게 둔다(업스트림이 이미 명령 실패를 어떻게 다루는지는 M3에서 실측).
3. `omarchy-settings`가 제공하는 `omarchy-debug*`는 패키징하지 않는다.
4. 공식 `bin/` 전체를 `/usr/bin`에 설치하지 않는다.
