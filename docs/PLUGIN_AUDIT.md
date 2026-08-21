# 플러그인 감사

출처: `build/omarchy/shell/plugins/README.md` + 각 `manifest.json`.
정책: 파일은 지우지 않는다. 활성/비활성은 `disabledPlugins[]`로 끈다.

**단일 정의: `overlay/defaults/shell.json`.** 이 파일이 패키지가 배포하는
기본 `shell.json` 그 자체다(더는 "권장안"이 아니다). 이 절을 쓰는 시점 실측:

```console
$ grep -c disabledPlugins overlay/defaults/shell.json
0
```

`disabledPlugins` 키가 없다 — **모든 플러그인이 기동 시 로드된다.** 업스트림
규칙상 first-party non-bar 플러그인은 `plugins: []`만으로는 꺼지지 않고
`disabledPlugins`에 명시적으로 올려야 꺼지는데, 그 목록이 비어 있으므로 아래
표의 "v0.1" / "DISABLE" 칸은 **더 이상 현재 배포 상태를 나타내지 않는다**.
이하 표는 각 플러그인의 정체성(kind, 과거 판단 근거)을 남기기 위한 이력이며,
지금 무엇이 켜져 있는지의 답은 표가 아니라 `overlay/defaults/shell.json`이다.
`omarchy.bar`도 예외가 아니다 — 그 파일은 실제 `bar.layout`(left/center/right)을
채운 업스트림 바 레이아웃을 담고 있다(§ "Bar direction" 개정, 2026-08-17).

---

## 1st-party 전체 (이력 — 과거 v0.1 판단)

| id | kinds | v0.1 당시 판단 | 비고 |
| --- | --- | --- | --- |
| `omarchy.menu` | menu, bar-widget | ENABLE | `keepLoaded: true`. IPC `shell toggle omarchy.menu` |
| `omarchy.bar` | bar | ~~DISABLE~~ → 현재 활성 | 방향 전환(2026-08-17)으로 업스트림 bar 기본 활성. `overlay/defaults/shell.json`의 `bar.layout`이 근거 |
| `omarchy.notifications` | service | DISABLE (당시 판단) | `disabledPlugins`에 없으므로 현재는 활성 |
| `omarchy.lock` | service | DISABLE (당시 판단) | 현재는 활성 |
| `omarchy.osd` | panel | DISABLE unless 앱 런치 OSD에 필요 (당시 판단) | 현재는 활성. AppLibrary가 `omarchy-shell osd show`를 부름. **M2 실측(당시)**: 끈 채 기동해도 셸 기동·IPC 정상 — 그 실측은 "꺼도 안전하다"는 것이지 "지금 꺼져 있다"는 뜻이 아니다 |
| `omarchy.idle` | service | DISABLE (당시 판단) | 현재는 활성 — screensaver/lock 헬퍼 호출 |
| `omarchy.battery` | service | DISABLE (당시 판단) | 현재는 활성 |
| `omarchy.nightlight` | service | DISABLE (당시 판단) | 현재는 활성 |
| `omarchy.media` | service, bar-widget | DISABLE (당시 판단) | 현재는 활성 |
| `omarchy.polkit` | service | DISABLE (당시 판단) | 현재는 활성 — 시스템 polkit과 충돌 가능하다는 우려는 남아 있음, 재검토 필요 |
| `omarchy.clipboard` | overlay | AVAILABLE | 현재도 활성 |
| `omarchy.emojis` | overlay | AVAILABLE | 현재도 활성 |
| `omarchy.image-picker` | overlay | AVAILABLE | 현재도 활성 — 테마 스위처가 씀 |
| `omarchy.reminders` | overlay | DISABLE (당시 판단) | 현재는 활성 |
| `omarchy.audio` | bar-widget | DISABLE (당시 판단) | 현재는 활성. `overlay/defaults/shell.json`의 `bar.layout.right`에 있음 |
| `omarchy.bluetooth` | bar-widget | DISABLE (당시 판단) | 현재는 활성. bar.layout.right |
| `omarchy.clock` | bar-widget | DISABLE (당시 판단) | 현재는 활성. bar.layout.center |
| `omarchy.monitor` | bar-widget | DISABLE (당시 판단) | 현재는 활성. bar.layout.right |
| `omarchy.network` | bar-widget | DISABLE (당시 판단) | 현재는 활성. bar.layout.right |
| `omarchy.power` | bar-widget | DISABLE (당시 판단) | 현재는 활성. bar.layout.right |
| `omarchy.tailscale` | bar-widget | UNSUPPORTED (당시 판단) | `bar.layout`에 없음 — 코드상 활성이나 바에 배치되지 않음 |
| `omarchy.agents` | bar-widget | DISABLE (당시 판단) | 현재는 활성. bar.layout.right |
| `omarchy.weather` | bar-widget | DISABLE (당시 판단) | 현재는 활성. bar.layout.center |
| `omarchy.background` | (Background.qml) | DISABLE (당시 판단) | 현재는 활성 — 기존 배경/Waybar와 겹칠 수 있다는 우려는 남아 있음, 재검토 필요 |
| panels: wifiqr, speedtest, disk-speedtest, dropbox | panel | DISABLE / UNSUPPORTED (당시 판단) | `disabledPlugins`에 없으므로 코드상 활성 |

bar-only 위젯(`omarchy.workspaces` 등)은 bar가 꺼지면 실질 비활성이지만, 지금은
bar 자체가 활성이므로 이 조건도 적용되지 않는다.

---

## 실제 배포 파일

패키지가 배포하는 기본값은 `overlay/defaults/shell.json` 그 자체이며, 문서에
따로 예시를 싣지 않는다 — 예시와 실제 파일이 갈라지는 것이 이 절이 고치는
바로 그 문제이기 때문이다. 확인은 파일을 직접 읽는다:

```console
$ cat overlay/defaults/shell.json
```

사용자 오버라이드 경로(`~/.config/omarchy/shell.json`)와의 관계는
`docs/RUNTIME_STARTUP.md`를 따른다. **패키지가 사용자의 `~/.config/omarchy`를
덮어쓰지 말 것.**

---

## 삭제 금지

비활성 플러그인을 트리에서 지우면 업스트림 범프마다 패치가 커진다. 의존·충돌이 파일 존재만으로 발생한다는 증거가 있을 때만 삭제(SPEC §18).
