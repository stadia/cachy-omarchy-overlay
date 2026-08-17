#!/usr/bin/env bash
# R01 셸 프로세스 기동 / R02 IPC ping. SPEC 46.3, 48, 55.
#
# 패키지를 설치하지 않는다 — 빌드된 아티팩트를 추출해 그 트리를 띄운다.
# 사용자의 라이브 Hyprland 세션 위에서 도는 유일한 테스트다. 화면을 점유하는
# 표면을 만들지 않는 것이 통과 조건의 일부다 (SPEC 4.3, 66).
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/lib/runtime.sh"

command -v jq >/dev/null || { echo "skip: jq 없음"; exit 0; }
coo_live_runtime_usable || { echo "skip: 라이브 Wayland 런타임 없음 (quickshell/qs/systemd-cat 사용 불가 또는 WAYLAND_DISPLAY 소켓 없음)"; exit 0; }
coo_pkg_artifact >/dev/null || { echo "skip: build/*.pkg.tar.zst 없음"; exit 0; }

dest="$COO_TEST_SANDBOX/pkg"
coo_extract_pkg "$dest" || { echo "skip: 추출 실패"; exit 0; }
root=$(coo_upstream_root "$dest")
defaults="$REPO_ROOT/overlay/defaults/shell.json"

# ---------------------------------------------------------------- 안전 장치
#
# FINDING (Task 5): `disabledPlugins` 는 내장 바를 끄지 못한다. 업스트림은
# bar 종류 플러그인을 "끌 수 없고 후임으로만 교체 가능"하게 설계했고
# (services/PluginRegistry.qml:110-138, canDisable=false), shell.qml 의
# defaultBarLoader 는 activeBarId === "omarchy.bar" 이면 무조건 active 다.
# 따라서 기동만 하면 layer-shell 표면 `omarchy-bar` 가 매핑되고, 기본값으로는
# ExclusionMode.Auto 로 화면 상단 26px 를 예약해 사용자 창을 전부 밀어낸다.
#
# 여기서 쓰는 `bar-off` 토글은 업스트림 자신의 숨김 경로(`omarchy-toggle-bar`,
# plugins/bar/Bar.qml:935-949)다. 표면은 그대로 두되 exclusion 을 끄고 화면
# 밖으로 주차시킨다. HOME 은 tests/test.sh 가 샌드박스로 바꿔 두므로 사용자의
# 실제 상태는 건드리지 않는다. 패키지 기본값이 바를 정말로 없애기 전까지의
# 임시 방편이며, 아래 "화면 점유" 단언이 그 임시 방편이 실제로 듣는지 검증한다.
#
# 아래 쓰기는 전적으로 $HOME 에 의존한다. 지금 안전한 이유는 tests/test.sh 가
# HOME 을 샌드박스로 덮어써 주기 때문일 뿐이고, 그건 이 파일 밖의 사정이다.
# 이 파일을 직접 실행하거나 순서를 바꾸면 사용자의 진짜
# ~/.local/state/omarchy/ 에 쓰게 된다. 우연이 아니라 구조로 막는다.
[[ ${HOME:-} == "${COO_TEST_SANDBOX:?}" ]] || {
  printf 'FAIL: HOME 이 샌드박스가 아니다 — 사용자 상태를 건드릴 수 있어 중단한다\n' >&2
  printf '      HOME=%q COO_TEST_SANDBOX=%q\n' "${HOME:-}" "$COO_TEST_SANDBOX" >&2
  exit 1
}

mkdir -p "$HOME/.local/state/omarchy/toggles"
: > "$HOME/.local/state/omarchy/toggles/bar-off"

W="$REPO_ROOT/overlay/bin/cachy-omarchy-shell"
export COO_OMARCHY_PATH="$root"

# --run 은 systemd-cat 으로 감싸므로 stdout/stderr 은 저널로 간다. 여기서
# 리다이렉트한 파일은 (정상이라면) 비어 있고, 그것을 기동 로그로 착각하면
# "오류 0줄" 이 언제나 참이 된다. 실제 로그는 저널에서 태그로 읽는다.
stdout_log="$COO_TEST_SANDBOX/shell.stdout"
journal_log="$COO_TEST_SANDBOX/shell.journal"
cursor=$(journalctl --user -n 0 --show-cursor 2>/dev/null | sed -n 's/^-- cursor: //p')
since=$(date '+%Y-%m-%d %H:%M:%S')

"$W" --run > "$stdout_log" 2>&1 &
shell_pid=$!
# cleanup() 이 재진입 방지로 shell_pid 를 비우므로, 종료 후 잔여물 검사가
# 참조할 PID 는 여기서 별도로 보존해 둔다 (아래 "잔여물 없음" 절 참고).
our_shell_pid=$shell_pid

# 라이브 세션 위에서 도는 테스트이므로 정리는 중단 경로에서도 반드시 돈다.
# EXIT 만 걸면 Ctrl-C 가 사용자의 진짜 데스크톱에 quickshell 과 그 layer 표면을
# 그대로 두고 간다 (SPEC 66). 그리고 wait 는 자식이 TERM 을 무시하면 영원히
# 막히므로 2초 감시자로 상한을 준다. 죽이는 대상은 언제나 우리 PID 하나뿐이다
# — pkill/killall 은 사용자의 컴포지터까지 잡는다.
cleanup() {
  [[ -n ${shell_pid:-} ]] || return 0
  local pid=$shell_pid
  shell_pid=""
  kill -TERM "$pid" 2>/dev/null
  { sleep 2; kill -KILL "$pid" 2>/dev/null; } &
  local watchdog=$!
  wait "$pid" 2>/dev/null
  # 감시자와 그 sleep 자식까지 PID 로만 정리한다. 서브셸만 죽이면 sleep 이
  # 고아로 2초 더 떠 있는다.
  local sleeper
  sleeper=$(ps -o pid= --ppid "$watchdog" 2>/dev/null | tr -d ' ')
  kill "$watchdog" 2>/dev/null
  [[ -n $sleeper ]] && kill "$sleeper" 2>/dev/null
  wait "$watchdog" 2>/dev/null
  return 0
}
# INT/TERM 은 정리 후 즉시 빠져나간다. bash 는 트랩이 끝나면 원래 자리로
# 돌아가므로, exit 를 붙이지 않으면 중단된 실행이 남은 단언을 계속 돌려
# 초록으로 끝난다. EXIT 트랩이 cleanup 을 한 번 더 부르지만 멱등이다.
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# 대기 상한. ping 이 즉답하는 정상 경로에서는 40 x 250ms = 10s 이지만, IPC 가
# 매번 걸리면 한 번의 --ipc 가 COO_IPC_TIMEOUT(기본 2s) 을 다 쓴다:
# 40 x (2s + 250ms) = 90s, timeout 의 --kill-after=1s 유예까지 매번 소진되면
# 40 x (3s + 250ms) = 130s 가 최악이다. 실무에서는 아래 kill -0 이 죽은
# 프로세스를 즉시 잡아내 루프를 끊는다. 실측은 2회차(~0.5s)에 응답.
reply=""
for _ in $(seq 1 40); do
  reply=$("$W" --ipc shell ping 2>/dev/null) && [[ -n $reply ]] && break
  kill -0 "$shell_pid" 2>/dev/null || break
  sleep 0.25
done

# R01 — 프로세스가 살아 있다.
kill -0 "$shell_pid" 2>/dev/null && alive=0 || alive=1
assert_eq "$alive" "0" "R01 셸 프로세스 기동"

# R02 — IPC ping 이 응답한다.
assert_eq "$reply" "ok" "R02 IPC ping 응답"

# ------------------------------------------------- 비활성 집합이 실제로 먹혔나
#
# "바가 안 보인다" 는 부재 증명이고, 플러그인이 전부 로드 실패해도 똑같이
# 성립한다. 그래서 존재로 증명한다: 실효 설정과 레지스트리를 직접 물어본다.
cfg='{}'; plugins='[]'
if (( alive == 0 )); then
  cfg=$("$W" --ipc shell listShellConfig 2>/dev/null) || cfg='{}'
  plugins=$("$W" --ipc shell listPlugins 2>/dev/null) || plugins='[]'
  [[ -n $cfg ]] || cfg='{}'
  [[ -n $plugins ]] || plugins='[]'
fi

want_disabled=$(jq -r '.disabledPlugins | sort | join(",")' "$defaults")
got_disabled=$(jq -r '(.disabledPlugins // []) | sort | join(",")' <<<"$cfg" 2>/dev/null)
assert_eq "$got_disabled" "$want_disabled" "실효 shell.json 이 스테이징된 disabledPlugins 를 그대로 싣는다"

# 레지스트리가 실제로 스캔에 성공했다는 증거. 0개면 아래 enabled 단언이
# 공짜로 통과하므로 먼저 확인한다.
registered=$(jq -r 'length' <<<"$plugins" 2>/dev/null)
[[ $registered =~ ^[0-9]+$ ]] || registered=0
assert_eq "$(( registered > 20 ? 1 : 0 ))" "1" "플러그인 레지스트리 스캔 성공 (등록 $registered개)"

# 내장 바를 뺀 비활성 대상은 전부 enabled=false 여야 한다.
leaked=$(jq -r --slurpfile d "$defaults" '
  ($d[0].disabledPlugins - ["omarchy.bar"]) as $ids
  | [ .[] | select(.enabled == true) | select(.id as $i | $ids | index($i)) | .id ]
  | sort | join(",")' <<<"$plugins" 2>/dev/null)
assert_eq "$leaked" "" "비활성 목록의 플러그인이 하나도 켜져 있지 않다 (내장 바 제외)"

# jq 의 `//` 는 false 도 비어 있는 것으로 쳐서 기본값으로 갈아치운다. 여기서는
# false 와 "없음" 을 반드시 구분해야 하므로 배열로 받아 길이로 판정한다.
plugin_field() {
  jq -r --arg id "$1" --arg f "$2" \
    '[ .[] | select(.id == $id) | .[$f] ]
     | if length == 0 then "absent"
       elif (.[0] | type) == "array" then (.[0] | join(","))
       else (.[0] | tostring) end' <<<"$plugins" 2>/dev/null
}

# 내장 바는 업스트림이 끌 수 없게 만들어 두었다. 그 사실 자체를 단언해 둔다:
# 위 예외가 우리 착각이 아니라 업스트림 계약이라는 것을 고정한다.
assert_eq "$(plugin_field omarchy.bar canDisable)" "false" \
  "업스트림은 내장 바를 비활성 불가로 선언한다 (canDisable=false)"

# 대조군: 비활성 목록에 없는 first-party 플러그인은 켜져 있어야 한다.
# 이것이 참이어야 "omarchy.menu 도 로드된다" 는 결론이 성립한다.
assert_eq "$(plugin_field omarchy.clipboard enabled)" "true" \
  "비활성 목록 밖 first-party 플러그인은 켜져 있다 (대조군)"

# omarchy.menu — Milestone 3 의 런처. 지금 로드되지 않으면 M3 에서 비싸게 안다.
# listPlugins 의 enabled 는 bar-widget 종류에 대해서는 "바에 놓였는가" 를
# 뜻하므로(shell.qml:952-976) 여기서는 false 가 정상이다. 대신 레지스트리
# 등록 사실과 비활성 목록 부재로 증명한다.
assert_eq "$(plugin_field omarchy.menu kinds)" "menu,bar-widget" "omarchy.menu 가 menu 종류로 등록됨"
assert_eq "$(plugin_field omarchy.menu firstParty)" "true" "omarchy.menu first-party 로 인식됨"
assert_eq "$(jq -r '(.disabledPlugins // []) | index("omarchy.menu") // "none"' <<<"$cfg")" "none" \
  "omarchy.menu 는 비활성 목록에 없다"

# ------------------------------------------------------------- 화면 점유 금지
#
# M8 이후 이 단언의 범위가 좁아졌다. 업스트림 기본값을 그대로 쓰기로 한 뒤
# (원칙 0) 셸은 의도적으로 화면에 그린다 — 상단 바와 전체화면 배경 레이어다.
# 그래도 이 테스트는 사용자의 진짜 데스크톱 위에서 돌기 때문에, 테스트가
# 러너의 창을 밀어내는 일만은 여전히 막아야 한다.
#
# 그래서 layer level 로 판정한다. hyprctl 의 level 0(background)·1(bottom) 은
# 모든 창 아래에 깔리므로 창을 밀어내지 않는다 — omarchy-background 가 여기
# 산다. level 2(top)·3(overlay) 만이 사용자 창 위로 올라오고 exclusion zone 을
# 잡는다 — omarchy-bar 가 여기 살며, 위쪽 bar-off 가드가 그것을 화면 밖으로
# 주차시킨다. 판정은 네임스페이스 이름이 아니라 level + 기하학으로 한다.
our_layers='[]'
onscreen=""
if command -v hyprctl >/dev/null && (( alive == 0 )); then
  our_layers=$(hyprctl -j layers 2>/dev/null | jq -c --argjson pid "$shell_pid" \
    '[ to_entries[].value.levels | to_entries[] as $lv | $lv.value[]
       | select(.pid == $pid) | . + {level: ($lv.key | tonumber)} ]') || our_layers='[]'
  mons=$(hyprctl -j monitors 2>/dev/null | jq -c '[ .[] | select(.disabled | not) ]') || mons='[]'

  # 아래 "화면 점유 없음" 은 our_layers 가 비면 아무것도 검사하지 않고 통과한다.
  # systemd-cat 이 exec 대신 fork 하거나 hyprctl JSON 모양이 바뀌면 PID 필터가
  # 조용히 빈 집합을 내고, 밀리스톤에서 제일 중요한 안전 단언이 공짜가 된다.
  # 그래서 표본이 실제로 있었다는 것부터 단언한다.
  #
  # (a) 는 JSON 파싱과 모양이 멀쩡하다는 증거로 바가 사라져도 유효하다.
  # (b) 는 오늘의 비공허성 증거이며, 내장 바가 진짜로 제거되는 날
  #     (Finding A 해결) 실패하게 된다. 그때는 다른 비공허성 증거로 교체할 것.
  total_layers=$(hyprctl -j layers 2>/dev/null | jq -r '[ to_entries[].value.levels | to_entries[].value[] ] | length')
  [[ $total_layers =~ ^[0-9]+$ ]] || total_layers=0
  assert_eq "$(( total_layers > 0 ? 1 : 0 ))" "1" "(a) hyprctl layers 를 파싱해 표면을 관측했다 (전체 $total_layers개)"

  layer_count=$(jq -r 'length' <<<"$our_layers" 2>/dev/null)
  [[ $layer_count =~ ^[0-9]+$ ]] || layer_count=0
  assert_eq "$(( layer_count > 0 ? 1 : 0 ))" "1" "(b) PID 필터가 우리 표면을 실제로 잡았다 ($layer_count개)"

  onscreen=$(jq -r -n --argjson l "$our_layers" --argjson m "$mons" '
    [ $l[] as $layer | $m[] as $mon
      | select($layer.level >= 2)
      | select($layer.x < ($mon.x + $mon.width / $mon.scale)
           and ($layer.x + $layer.w) > $mon.x
           and $layer.y < ($mon.y + $mon.height / $mon.scale)
           and ($layer.y + $layer.h) > $mon.y)
      | $layer.namespace ] | unique | join(",")')
  assert_eq "$onscreen" "" "우리 셸의 top/overlay 표면이 러너의 창을 밀어내지 않는다"

  # 반대 방향 증거: 배경 레이어는 실제로 그려져야 한다. 억제를 걷어낸 뒤
  # omarchy.background 가 살아 있다는 것이 원칙 0 이 먹혔다는 관측이다.
  below=$(jq -r '[ .[] | select(.level < 2) | .namespace ] | unique | join(",")' <<<"$our_layers")
  assert_contains "$below" "omarchy-background" \
    "억제 해제 후 배경 레이어가 창 아래(level<2)에 실제로 그려진다"

  # 상단 바가 화면 밖(y<0)에 있는 것은 패키지 기본값이 바를 없앴기 때문이
  # 아니라 이 테스트가 bar-off 가드를 켜 두었기 때문이다. 출력만 보는 사람이
  # 반대로 읽지 않도록 그 사실을 증거 옆에 붙여 둔다.
  printf '      FINDING: 매핑된 layer 표면 = %s (bar 는 bar-off 가드로 주차된 상태 — 패키지 기본값은 바를 그린다)\n' \
    "$(jq -c '[.[] | {namespace, level, x, y, w, h}]' <<<"$our_layers")"
fi

# ------------------------------------------------------------------ 기동 로그
cleanup
sleep 0.5   # journald 플러시.

if [[ -n $cursor ]]; then
  journalctl --user --after-cursor "$cursor" -t cachy-omarchy-shell --no-pager -o cat > "$journal_log" 2>/dev/null
else
  journalctl --user --since "$since" -t cachy-omarchy-shell --no-pager -o cat > "$journal_log" 2>/dev/null
fi
[[ -f $journal_log ]] || : > "$journal_log"

# 로그를 실제로 수집했다는 증거. 이게 없으면 아래 "오류 0줄" 은 공짜다.
assert_eq "$(grep -c "Configuration Loaded" "$journal_log")" "1" "기동 로그를 저널에서 수집했다"

errs=$(grep -ciE "ReferenceError|TypeError|is not a type|Cannot assign|unavailable" "$journal_log")
assert_eq "$errs" "0" "기동 로그에 QML 오류 없음"

fatal=$(grep -cE "ERROR" "$journal_log")
assert_eq "$fatal" "0" "기동 로그에 ERROR 레벨 없음"

warns=$(grep -aE "WARN" "$journal_log" | sed 's/\x1b\[[0-9;]*m//g')
[[ -n $warns ]] && printf '      FINDING: 기동 경고\n%s\n' "$(sed 's/^/        /' <<<"$warns")"

# ------------------------------------------------------------------ 잔여물 없음
#
# 이름이 아니라 우리 PID 로 판정한다 (line ~177 의 화면 점유 검사와 동일한
# 스코핑). 이름 기반(grep -i omarchy)은 사용자의 라이브 셸처럼 이 테스트가
# 만들지 않은 다른 프로세스의 omarchy-named 표면까지 우리 잔여물로 잘못
# 세어, 그 프로세스가 실제 사용 중일 때마다 이 단언만 거짓으로 실패한다.
if command -v hyprctl >/dev/null && command -v jq >/dev/null; then
  remaining=$(hyprctl -j layers 2>/dev/null | jq -r --argjson pid "$our_shell_pid" \
    '[ to_entries[].value.levels | to_entries[].value[] | select(.pid == $pid) ] | length') || remaining=""
  [[ $remaining =~ ^[0-9]+$ ]] || remaining=0
  assert_eq "$remaining" "0" "종료 후 우리 셸의 layer 표면이 남지 않는다"
fi

if (( ASSERT_FAILURES )); then
  printf '      --- shell.journal 마지막 40줄 ---\n'
  tail -40 "$journal_log" | sed 's/^/      /'
  printf '      --- shell.stdout (systemd-cat 이 저널로 보내므로 보통 비어 있다) ---\n'
  tail -10 "$stdout_log" | sed 's/^/      /'
fi

exit "$ASSERT_FAILURES"
