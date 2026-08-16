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

command -v quickshell >/dev/null || { echo "skip: quickshell 없음"; exit 0; }
command -v jq >/dev/null || { echo "skip: jq 없음"; exit 0; }
[[ -n ${WAYLAND_DISPLAY:-} ]] || { echo "skip: WAYLAND_DISPLAY 없음"; exit 0; }
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

cleanup() {
  [[ -n ${shell_pid:-} ]] || return 0
  kill "$shell_pid" 2>/dev/null
  wait "$shell_pid" 2>/dev/null
}
trap cleanup EXIT

# 유계 대기: 40 x 250ms = 10s 상한.
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
# SPEC 4.3 — 우리 셸이 사용자 화면을 가져가면 안 된다. 네임스페이스 이름이
# 아니라 기하학으로 판정한다: 우리 PID 의 layer 표면 중 어떤 모니터의 가시
# 영역과 겹치는 것이 있으면 실패다.
our_layers='[]'
onscreen=""
if command -v hyprctl >/dev/null && (( alive == 0 )); then
  our_layers=$(hyprctl -j layers 2>/dev/null | jq -c --argjson pid "$shell_pid" \
    '[ to_entries[].value.levels | to_entries[].value[] | select(.pid == $pid) ]') || our_layers='[]'
  mons=$(hyprctl -j monitors 2>/dev/null | jq -c '[ .[] | select(.disabled | not) ]') || mons='[]'
  onscreen=$(jq -r -n --argjson l "$our_layers" --argjson m "$mons" '
    [ $l[] as $layer | $m[] as $mon
      | select($layer.x < ($mon.x + $mon.width / $mon.scale)
           and ($layer.x + $layer.w) > $mon.x
           and $layer.y < ($mon.y + $mon.height / $mon.scale)
           and ($layer.y + $layer.h) > $mon.y)
      | $layer.namespace ] | unique | join(",")')
  assert_eq "$onscreen" "" "우리 셸의 layer 표면이 화면을 점유하지 않는다 (SPEC 4.3)"
  printf '      FINDING: 매핑된 layer 표면 = %s\n' "$(jq -c '[.[] | {namespace, x, y, w, h}]' <<<"$our_layers")"
fi

# ------------------------------------------------------------------ 기동 로그
kill "$shell_pid" 2>/dev/null
wait "$shell_pid" 2>/dev/null
shell_pid=""
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
if command -v hyprctl >/dev/null; then
  remaining=$(hyprctl layers 2>/dev/null | grep -ci "omarchy" || true)
  assert_eq "$remaining" "0" "종료 후 omarchy layer 표면이 남지 않는다"
fi

if (( ASSERT_FAILURES )); then
  printf '      --- shell.journal 마지막 40줄 ---\n'
  tail -40 "$journal_log" | sed 's/^/      /'
  printf '      --- shell.stdout (systemd-cat 이 저널로 보내므로 보통 비어 있다) ---\n'
  tail -10 "$stdout_log" | sed 's/^/      /'
fi

exit "$ASSERT_FAILURES"
