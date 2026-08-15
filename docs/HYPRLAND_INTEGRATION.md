# Hyprland 통합 규약

이 문서는 `cachy-omarchy-overlay`가 사용자의 Hyprland 설정에 자신의 관리 블록(managed block)을
주입하는 방식을 규정한다. 여기 적힌 내용은 추정이 아니라 **Hyprland 0.56.2에서 실제로 측정하고
검증한 결과**이며, 검증 코드는 `tests/installer/test_hypr_overlay_loads.sh`에 남아 있다.

측정 환경:

```text
Hyprland 0.56.2
commit efb50993780079460b0cbed1363e2166a2de1d9f
branch v0.56.2, 2026-08-05
Lua VM: Lua 5.5
backend: aquamarine (wlroots 아님)
```

---

## 1. 감지되는 설정 포맷과 우선순위

Hyprland는 **루트 설정 파일을 정확히 하나만** 읽는다. 0.56 계열은 두 가지 포맷을 지원한다.

| 포맷 | 파일 | 문법 |
|---|---|---|
| Lua | `$XDG_CONFIG_HOME/hypr/hyprland.lua` | Lua 5.5 스크립트, 전역 `hl` API |
| classic | `$XDG_CONFIG_HOME/hypr/hyprland.conf` | Hyprland 고유 키=값 문법 |

`lib/env.sh`의 `coo_detect_hypr_config()`는 **`.lua`를 먼저 찾고, 없으면 `.conf`를 찾는다.**
둘 다 없으면 아무것도 출력하지 않고 종료 코드 `1`을 반환한다.

`.lua`가 우선인 이유는 Hyprland 자신의 우선순위와 일치시키기 위해서다. 두 파일이 모두 존재하는
상태에서 설치기가 `.conf`를 고르면, 실제로 로드되는 것은 `.lua`이므로 관리 블록은 조용히 무시되고
사용자에게는 "설치는 됐는데 아무 일도 일어나지 않는" 상태가 된다.

`coo_hypr_config_format(path)`는 확장자만 보고 `lua` 또는 `conf`를 출력한다. `.lua`가 아닌 모든
것은 `conf`로 간주한다.

> **참고 (레퍼런스 머신):** 이 프로젝트의 개발 머신에는 `hyprland.conf`가 **존재하지 않는다.**
> `~/.config/hypr/hyprland.lua` 하나뿐이다. `SPEC.md` §17이 전제하던 "루트 설정에 `source = ...`를
> 넣는다"는 방식은 이 머신에서 **문법 오류**다. 이 문서 전체가 그 문제를 해결하기 위해 존재한다.

---

## 2. 포맷별 관리 블록

설치기가 사용자 루트 설정에 덧붙이는 텍스트는 아래가 전부다. **정확히 한 개의 관리 소스만**
import 하며, 그 외에 `~/.config/hypr` 안의 어떤 것도 다시 쓰지 않는다.

### 2.1 `.conf` 포맷

```conf
# >>> cachy-omarchy-overlay >>>
source = /home/u/.config/cachy-omarchy-overlay/hypr/overlay.conf
# <<< cachy-omarchy-overlay <<<
```

### 2.2 `.lua` 포맷

```lua
-- >>> cachy-omarchy-overlay >>>
dofile("/home/u/.config/cachy-omarchy-overlay/hypr/overlay.lua")
-- <<< cachy-omarchy-overlay <<<
```

위 두 블록은 `tests/installer/test_hypr_overlay_loads.sh`가 통과시킨 것과 **글자 그대로 동일한**
형태다. 경로만 실제 설치 경로로 치환된다.

### 2.3 주석 문법은 포맷마다 다르다 (실측으로 발견한 버그)

`lib/common.sh`의 `COO_MARKER_BEGIN` / `COO_MARKER_END`는 `#`로 시작한다. `#`는 `.conf`에서는
주석이지만 **Lua에서는 길이 연산자**다. 따라서 `#` 마커를 `.lua` 설정의 (첫 줄이 아닌) 어느
줄에든 넣으면 파일 전체가 파싱에 실패한다. Hyprland 0.56.2가 직접 내놓은 진단은 다음과 같다.

```text
$ Hyprland --verify-config -c hash.lua

======== Config parsing result:

hash.lua:2: unexpected symbol near '#'
```

이것은 사소한 문제가 아니다. 관리 블록 하나 때문에 **사용자의 Hyprland 설정 전체가 죽는다.**
마커 한 줄이 잘못되면 오버레이가 안 켜지는 정도가 아니라, 모니터·키바인딩·자동 실행이 전부
날아간 상태로 세션이 뜬다.

(Lua 표준 인터프리터가 파일 **첫 줄**의 `#`만 shebang으로 건너뛰기 때문에, 마커를 1번 줄에 두고
테스트하면 이 버그를 놓치게 된다. 실제 관리 블록은 항상 파일 끝에 추가되므로 첫 줄일 수 없다.)

해결책은 `lib/env.sh`의 `coo_hypr_marker_begin(format)` / `coo_hypr_marker_end(format)`이다.

| 포맷 | 시작 마커 | 종료 마커 |
|---|---|---|
| `conf` | `# >>> cachy-omarchy-overlay >>>` | `# <<< cachy-omarchy-overlay <<<` |
| `lua` | `-- >>> cachy-omarchy-overlay >>>` | `-- <<< cachy-omarchy-overlay <<<` |

**주석 도입부만 바뀌고, 마커 본문(`>>> cachy-omarchy-overlay >>>`)은 두 포맷에서 바이트 단위로
동일하다.** 덕분에 §3의 멱등성 스캔은 포맷별로 규칙을 나눌 필요 없이 하나로 유지된다.

### 2.4 왜 `require`가 아니라 `dofile`인가

Hyprland가 배포하는 기본 `hyprland.lua`는 설정 분할 방법으로 `require("myColors")`를 안내한다.
하지만 `require`는 `package.path`에 의존하고, 그 값은 Hyprland가 정한다. 중첩 인스턴스에서 실제로
측정한 값은 다음과 같다.

```text
package.path = <루트 설정 파일이 있는 디렉터리>/?.lua;
               <루트 설정 파일이 있는 디렉터리>/?/init.lua;
               /usr/local/share/lua/5.5/?.lua; ... ; ./?.lua; ./?/init.lua
```

즉 `require`로 도달할 수 있는 것은 **루트 설정 파일과 같은 디렉터리(= `~/.config/hypr`)** 뿐이다.
이 프로젝트의 오버레이는 `~/.config/cachy-omarchy-overlay/hypr/`에 있으므로 `require`로는 닿지
않는다. 닿게 하려면 사용자 설정 안에서 `package.path`를 조작해야 하는데, 그것은 "사용자 설정은
사용자의 것"이라는 원칙에 정면으로 어긋난다.

`dofile`은 파일시스템 절대 경로를 그대로 받으며 `package.path`를 전혀 보지 않는다. 그리고 실측
결과 Hyprland 0.56.2의 Lua VM에는 표준 라이브러리가 그대로 살아 있다.

```text
io=table  dofile=function  loadfile=function  require=function  package=table
_VERSION=Lua 5.5
```

`dofile` 방식이 실제로 오버레이를 실행한다는 것은 Hyprland가 직접 확인해 준다.

```text
$ Hyprland --verify-config -c dash.lua

======== Config parsing result:

config ok

$ ls VC_MARKER
VC_MARKER        # 오버레이 안의 순수 Lua io.open 이 실행된 증거
```

---

## 3. 멱등성 규칙

`SPEC.md` §5.6에 따른다.

1. 루트 설정에서 시작 마커와 종료 마커 사이의 영역을 찾는다.
2. **있으면** 그 영역 전체를 새 블록으로 **치환**한다.
3. **없으면** 파일 끝에 **한 번만 추가**한다.
4. 어떤 경우에도 **두 번째 블록을 추가하지 않는다.**
5. 쓰기 전에 원본을 백업한다. 제거(uninstall)는 같은 영역을 삭제하는 것으로 끝난다.

마커 본문이 포맷과 무관하게 동일하므로, 스캔은 `>>> cachy-omarchy-overlay >>>` 라는 단일
문자열로 수행할 수 있다. 다만 **다시 쓸 때는 반드시 해당 포맷의 마커를 써야 한다.** `.conf`에서
`.lua`로 마이그레이션한 사용자의 파일에 `#` 마커가 남아 있을 수 있으므로, 스캔은 두 도입부를 모두
인식하고 출력은 항상 현재 포맷에 맞춰야 한다.

관리 블록 밖의 사용자 설정은 절대 건드리지 않는다. 실질적인 내용은 전부 프로젝트가 소유한
`overlay.conf` / `overlay.lua` 안에 들어가며, 루트 설정에 남는 것은 위의 세 줄뿐이다.

---

## 4. 키바인딩 탐색 전략

키바인딩 뷰어(Milestone 6)가 어디서 데이터를 얻어야 하는지에 대한 결론이다.

### 4.1 `hyprctl binds -j`로 알 수 있는 것

`hyprctl binds -j`는 **키 자체에 대해서는 권위 있는 소스**이며, `.conf`와 `.lua` 설정에서
동일하게 동작한다. 신뢰할 수 있는 필드는 다음과 같다.

```text
modmask, key, keycode, locked, release, repeat, mouse,
longPress, non_consuming, catch_all, submap, submap_universal
```

### 4.2 `.conf` 설정에서 추가로 알 수 있는 것

`.conf` 설정에서는 `dispatcher`, `arg`, 그리고 (`bindd`를 쓴 경우) `description`까지 쓸 만한
값이 나온다. 즉 `.conf`만 놓고 보면 `hyprctl binds -j` 하나로 뷰어를 만들 수 있다.

### 4.3 `.lua` 설정에서는 동작을 알 수 없다

레퍼런스 머신의 `hyprland.lua`에 대해 측정한 결과, **48개 바인드 전부**가 다음과 같이 보고된다.

```json
{
  "modmask": 64, "key": "Return", "keycode": 0,
  "dispatcher": "__lua", "arg": "6",
  "description": "", "has_description": false,
  "locked": false, "mouse": false, "release": false, "repeat": false
}
```

- `dispatcher`는 48개 모두 `"__lua"` — 실제 디스패처가 아니라 "Lua 콜백"이라는 표식일 뿐이다.
- `arg`는 불투명한 정수 문자열(`"6"`, `"8"`, `"16"` …) — Lua 쪽 콜백 테이블의 인덱스이며
  바깥에서 해석할 수 없다.
- `description`은 48개 모두 빈 문자열이다.

**결론: `.lua` 설정에서는 `hyprctl binds`만으로 어떤 바인딩이 무슨 일을 하는지 절대 알 수 없다.**

### 4.4 그래서 뷰어는 조인(join)한다

뷰어는 두 소스를 `(modmask, key)`를 키로 조인한다.

```text
hyprctl binds -j   ->  키 조합 (권위 있음, 항상 정확)
설정 파일 파싱      ->  동작과 설명 (사람이 읽을 수 있는 의미)
```

- `.conf` 파싱은 `SPEC.md` §16.3 / §16.5를 따른다 (`bind`, `binde`, `bindl`, `bindm`, `bindr`,
  `bindd`, 재귀적 `source`). 픽스처: `tests/fixtures/hypr/simple.conf`.
- `.lua` 파싱은 `hl.bind("<MOD> + <KEY>", hl.dsp.<dispatcher>(<args>))` 형태를 추출하고,
  `local mainMod = "SUPER"`, `local menu = "walker"` 같은 **1단계 지역 문자열 변수**를 해석한다.
  픽스처: `tests/fixtures/hypr/simple.lua`.

**`hyprctl binds`에는 있는데 파싱으로 설명하지 못한 바인딩도 목록에 그대로 남긴다.** 설명만 비워
둔다. 파서가 이해하지 못했다는 이유로 실재하는 바인딩을 목록에서 빼서는 안 된다 — 그러면 뷰어가
거짓말을 하게 되고, 충돌 감지(§6)도 함께 망가진다.

이 규칙이 특히 중요한 경우:

- `for i = 1, 10 do ... end` 루프가 만들어내는 워크스페이스 바인딩 (소스 4줄 → 바인딩 20개)
- 디스패처 대신 익명 함수를 넘긴 바인딩
- 조건문이나 다른 파일(`require`)에서 생성된 바인딩

---

## 5. `modmask` 디코딩 표

`modmask`는 비트마스크다. 레퍼런스 머신에서 관측된 값은 `0`(10개), `64`(27개), `65`(11개)이며,
`64`가 SUPER, `65`가 SUPER+SHIFT라는 사실은 설정 파일과 대조해 확인했다.

| 비트 | 값 | 수정자 |
|---|---|---|
| 0 | 1 | SHIFT |
| 1 | 2 | CAPS |
| 2 | 4 | CTRL |
| 3 | 8 | ALT |
| 4 | 16 | MOD2 |
| 5 | 32 | MOD3 |
| 6 | 64 | SUPER |
| 7 | 128 | MOD5 |

`modmask = 0`은 수정자 없음을 뜻한다 (예: `XF86AudioMute` 같은 미디어 키).

이 표는 X11/xkb의 관례적인 수정자 순서를 따르지만 Hyprland 내부 구현에 묶여 있다.
**Hyprland 메이저 업데이트마다 재검증해야 한다.** 검증 방법은 간단하다: 설정 파일에서 수정자
조합이 명확한 바인딩을 하나 고르고, `hyprctl binds -j`가 그 키에 대해 보고하는 `modmask`와
대조한다.

---

## 6. 이 머신의 충돌 목록

| 키 조합 | 현재 소유자 | 근거 | 상태 |
|---|---|---|---|
| `SUPER + SPACE` | `walker` | `~/.config/hypr/hyprland.lua:295`, 변수는 42행 `local menu = "walker"` | **충돌** |
| `SUPER + K` | (없음) | `hyprctl binds -j`에 `key == "K"` 항목 없음 | 사용 가능 |

`SUPER + SPACE`는 `SPEC.md` §18이 기술하는 충돌의 실제 사례다. 주의할 점은, 이 충돌을
`hyprctl binds -j`만으로는 **설명할 수 없다**는 것이다. `hyprctl`은 `{"modmask": 64, "key":
"space", "dispatcher": "__lua", "arg": "16"}`이라고만 알려준다. "누가 이 키를 가져갔는가"에
답하려면 §4.4의 Lua 파싱이 반드시 필요하다. 충돌 감지는 파서의 부가 기능이 아니라 파서가 있어야만
가능한 기능이다.

동작 규칙 (`SPEC.md` §18):

- **기본값:** 이미 점유된 키 조합은 **경고를 출력하고 건너뛴다.** `SUPER + SPACE`는 설치되지 않는다.
- **`--force-bindings`:** `unbind` + `bindd`를 **프로젝트 소유 설정 파일 안에만** 기록한다.
  사용자의 `hyprland.lua` / `hyprland.conf`는 어떤 경우에도 수정하지 않는다.

---

## 7. Milestone 7을 위한 미해결 과제

이번 스파이크에서 결론을 내지 못했거나, 설치기 설계 단계에서 반드시 결정해야 하는 항목들이다.

1. **오버레이 파일이 사라졌을 때의 동작 — 두 포맷 모두 설정 오류가 된다.** 사용자가
   `~/.config/cachy-omarchy-overlay`를 수동으로 지우고 루트 설정의 관리 블록은 남겨두는 상황이다.
   실측 결과는 다음과 같다.

   ```text
   .conf:  Config error in file <root> at line N: source= globbing error: found no match
           (--verify-config 종료 코드 1. 오류가 해당 줄에 국한되고 파싱은 계속된다.)

   .lua:   cannot open <path>: No such file or directory
           stack traceback: [C]: in global 'dofile' / <root>:N: in main chunk
           (--verify-config 종료 코드 1. Lua 오류이므로 그 줄 이후의 청크 전체가 중단된다.)
   ```

   관리 블록을 항상 파일 **끝**에 두는 현재 규칙 덕분에 실제로 유실되는 설정은 없다. 하지만
   `.lua` 쪽 실패 양상이 더 나쁘고(청크 중단 + traceback), 사용자에게는 오류 오버레이만 보인다.
   현재 스니펫은 무방비한 `dofile("...")`이다. 방어 코드
   (`local ok = pcall(dofile, "...")` 또는 `loadfile`로 존재 여부 확인)를 넣을지 결정해야 한다.
   넣는다면 §2.2의 블록 본문이 바뀌므로 문서와 테스트를 함께 고쳐야 한다.

2. **`unbind`의 Lua 대응.** `hl.unbind(key)`는 API에 존재하지만, `dofile`로 로드된 오버레이가
   루트 설정보다 **먼저** 실행된다면 아직 만들어지지 않은 바인딩을 해제하려 드는 셈이 된다.
   관리 블록을 파일 **끝**에 붙이는 현재 규칙이 이 순서를 보장하지만, `--force-bindings`를
   구현하기 전에 명시적으로 검증해야 한다.

3. **`.conf` → `.lua` 마이그레이션.** 사용자가 포맷을 바꾸면 옛 포맷의 관리 블록이 옛 파일에
   그대로 남는다. 제거 경로가 두 파일을 모두 정리해야 하는지, 아니면 감지된 현재 루트 설정만
   책임지는지 정해야 한다.

4. **중첩 Hyprland 테스트의 백엔드.** `WLR_BACKENDS=headless WLR_RENDERER=pixman`은 wlroots
   시절 환경 변수이며, **aquamarine 백엔드를 쓰는 0.56.2에서는 아무 효과가 없다.** 중첩
   인스턴스는 실제로는 Wayland 백엔드로 뜨며(`Output WAYLAND-1`), 그 전에 DRM 백엔드를 먼저
   시도했다가 `libseat: failed to open a seat`으로 실패한다. 테스트는 통과하지만, 사용자 데스크톱에
   창이 잠깐 뜬다. aquamarine에는 `AQ_FORCE_BACKEND` 같은 변수가 없다(`AQ_DRM_DEVICES`,
   `AQ_NO_ATOMIC` 등만 존재). CI에서 헤드리스로 돌릴 방법을 따로 찾아야 한다.

5. **`--verify-config`를 설치 후 검증에 쓸 것.** `Hyprland --verify-config -c <path>`는 컴포지터를
   띄우지 않고 설정을 파싱해 `config ok` 또는 구체적인 오류 메시지를 출력한다. §2.3의 마커 버그를
   잡아낸 것도 이 명령이다. 설치기의 Phase 7(검증)은 관리 블록을 쓴 **직후 이 명령을 돌려야
   하며**, 실패하면 백업에서 즉시 롤백해야 한다. **주의: `.lua` 설정에 대해서는
   `--verify-config`가 설정을 실제로 실행한다** (`dofile` 대상까지 포함). 부작용이 있는 설정을
   검증할 때 이 점을 기억해야 한다. 종료 코드는 신뢰할 수 있다 — 실측 결과 정상은 `0`,
   파싱 실패는 `1`이다. 다만 `tests/installer/test_hypr_overlay_loads.sh`는 종료 코드 대신
   표준 출력의 `config ok` 문자열을 확인한다. 문자열 쪽이 더 구체적이고, 실패했을 때 원인
   메시지를 그대로 진단에 쓸 수 있기 때문이다.

6. **`~` 확장과 `$XDG_CONFIG_HOME`.** `coo_detect_hypr_config()`는 `$XDG_CONFIG_HOME`(미설정 시
   `$HOME/.config`)만 본다. Hyprland 자체가 `-c`나 `HYPRLAND_CONFIG` 환경 변수로 다른 경로를
   가리킬 수 있는데, 이 경우를 감지할지 여부는 미정이다.
