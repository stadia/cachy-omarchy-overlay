# 플러그인 감사

출처: `build/omarchy/shell/plugins/README.md` + 각 `manifest.json`.  
정책: 파일은 지우지 않는다. `~/.config/cachy-omarchy/`(또는 업스트림이 읽는 `~/.config/omarchy/shell.json`)의 `disabledPlugins[]`로 끈다. 경로 브리지는 M2.

First-party non-bar는 **명시적으로 disable하기 전엔 기동 시 로드**된다. `plugins: []`만으로는 메뉴/락/알림이 꺼지지 않는다.

---

## v0.1 목표

| id | kinds | class | notes |
| --- | --- | --- | --- |
| `omarchy.menu` | menu, bar-widget | ENABLE | `keepLoaded: true`. IPC `shell toggle omarchy.menu` |
| 키바인딩 UI | (플러그인 아님) | ENABLE or ADAPT | `omarchy-menu-keybindings` 헬퍼 |

---

## 전체 1st-party

| id | kinds | v0.1 | 패키지에서 삭제? |
| --- | --- | --- | --- |
| `omarchy.menu` | menu, bar-widget | ENABLE | no |
| `omarchy.bar` | bar | DISABLE | no — 기본 bar 옵션. 다른 bar가 없으면 레이아웃이 살아남음. `shell.json` bar.layout을 비우거나 우리 기본 json으로 막음 |
| `omarchy.notifications` | service | DISABLE | no |
| `omarchy.lock` | service | DISABLE | no |
| `omarchy.osd` | panel | DISABLE unless 앱 런치 OSD에 필요 | no. AppLibrary가 `omarchy-shell osd show`를 부름 — 없으면 실행은 되고 OSD만 실패할 수 있음. M2에서 실측 |
| `omarchy.idle` | service | DISABLE | no — screensaver/lock 헬퍼 호출 |
| `omarchy.battery` | service | DISABLE | no |
| `omarchy.nightlight` | service | DISABLE | no |
| `omarchy.media` | service, bar-widget | DISABLE | no |
| `omarchy.polkit` | service | DISABLE | no — 시스템 polkit과 충돌 가능 |
| `omarchy.clipboard` | overlay | AVAILABLE | no |
| `omarchy.emojis` | overlay | AVAILABLE | no |
| `omarchy.image-picker` | overlay | AVAILABLE | no — 테마 스위처가 씀. 테마 DISABLE이면 호출 안 함 |
| `omarchy.reminders` | overlay | DISABLE | no |
| `omarchy.audio` | bar-widget | DISABLE | no |
| `omarchy.bluetooth` | bar-widget | DISABLE | no |
| `omarchy.clock` | bar-widget | DISABLE | no |
| `omarchy.monitor` | bar-widget | DISABLE | no |
| `omarchy.network` | bar-widget | DISABLE | no |
| `omarchy.power` | bar-widget | DISABLE | no |
| `omarchy.tailscale` | bar-widget | UNSUPPORTED | no |
| `omarchy.agents` | bar-widget | DISABLE | no |
| `omarchy.weather` | bar-widget | DISABLE | no |
| `omarchy.background` | (Background.qml) | DISABLE | no — 기존 배경/Waybar와 겹침 |
| panels: wifiqr, speedtest, disk-speedtest, dropbox | panel | DISABLE / UNSUPPORTED | no |

bar-only 위젯(`omarchy.workspaces` 등)은 bar가 꺼지면 실질 비활성.

---

## 권장 기본 `shell.json` (M2, 구현은 하지 않음)

```json
{
  "version": 1,
  "bar": {
    "layout": { "left": [], "center": [], "right": [] }
  },
  "plugins": [],
  "disabledPlugins": [
    "omarchy.bar",
    "omarchy.notifications",
    "omarchy.lock",
    "omarchy.osd",
    "omarchy.idle",
    "omarchy.battery",
    "omarchy.nightlight",
    "omarchy.media",
    "omarchy.polkit",
    "omarchy.reminders",
    "omarchy.background"
  ]
}
```

`omarchy.menu`는 이 목록에 넣지 않는다.

사용자 파일이 `~/.config/omarchy/shell.json`을 읽는다. CachyOS 오버레이는 복사/심볼릭 또는 `HOME` 하위 브리지를 M2에서 정한다. **패키지가 `~/.config/omarchy`를 덮어쓰지 말 것.**

---

## 삭제 금지

비활성 플러그인을 트리에서 지우면 업스트림 범프마다 패치가 커진다. 의존·충돌이 파일 존재만으로 발생한다는 증거가 있을 때만 삭제(SPEC §18).
