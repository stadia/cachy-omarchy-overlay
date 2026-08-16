#!/usr/bin/env bash
# R03 재확인 / R04 런처 토글 열림 / R05 Escape 닫힘.
# 불린 IPC 만으로 렌더를 주장하지 않는다 — omarchy-menu layer 기하로 판정.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/lib/runtime.sh"

command -v jq >/dev/null || { echo "skip: jq 없음"; exit 0; }
command -v hyprctl >/dev/null || { echo "skip: hyprctl 없음"; exit 0; }
command -v wtype >/dev/null || { echo "skip: wtype 없음 (R05 Escape)"; exit 0; }
[[ ${COO_RUN_LIVE:-0} == 1 ]] || { echo "skip: 라이브 키 주입 (COO_RUN_LIVE=1 필요)"; exit 0; }
coo_live_runtime_usable || { echo "skip: 라이브 Wayland 런타임 없음 (quickshell/qs/systemd-cat 사용 불가 또는 WAYLAND_DISPLAY 소켓 없음)"; exit 0; }
coo_pkg_artifact >/dev/null || { echo "skip: build/*.pkg.tar.zst 없음"; exit 0; }

[[ ${HOME:-} == "${COO_TEST_SANDBOX:?}" ]] || {
  printf 'FAIL: HOME 이 샌드박스가 아니다 — 사용자 상태를 건드릴 수 있어 중단한다\n' >&2
  exit 1
}

dest="$COO_TEST_SANDBOX/pkg"
coo_extract_pkg "$dest" || { echo "skip: 추출 실패"; exit 0; }
root=$(coo_upstream_root "$dest")

mkdir -p "$HOME/.local/state/omarchy/toggles"
: > "$HOME/.local/state/omarchy/toggles/bar-off"

L="$REPO_ROOT/overlay/bin/cachy-omarchy-launcher"
W="$REPO_ROOT/overlay/bin/cachy-omarchy-shell"
export COO_OMARCHY_PATH="$root"
export OMARCHY_PATH="$root"

journal_log="$COO_TEST_SANDBOX/shell.journal"
cursor=$(journalctl --user -n 0 --show-cursor 2>/dev/null | sed -n 's/^-- cursor: //p')
since=$(date '+%Y-%m-%d %H:%M:%S')

"$W" --run >/dev/null 2>&1 &
shell_pid=$!

menu_layers() {
  hyprctl -j layers 2>/dev/null | jq -c \
    '[ to_entries[].value.levels | to_entries[].value[] | select(.namespace == "omarchy-menu") ]' \
    || echo '[]'
}

menu_onscreen() {
  local layers mons
  layers=$(menu_layers)
  mons=$(hyprctl -j monitors 2>/dev/null | jq -c '[ .[] | select(.disabled | not) ]') || mons='[]'
  jq -r -n --argjson l "$layers" --argjson m "$mons" '
    [ $l[] as $layer | $m[] as $mon
      | select($layer.x < ($mon.x + $mon.width / $mon.scale)
           and ($layer.x + $layer.w) > $mon.x
           and $layer.y < ($mon.y + $mon.height / $mon.scale)
           and ($layer.y + $layer.h) > $mon.y)
      | $layer.namespace ] | unique | join(",")'
}

wait_menu() {
  local want=$1 i layers
  for i in $(seq 1 40); do
    layers=$(menu_layers)
    if [[ $want == open ]]; then
      [[ $(jq -r 'length' <<<"$layers") -gt 0 ]] && return 0
    else
      [[ $(jq -r 'length' <<<"$layers") -eq 0 ]] && return 0
    fi
    sleep 0.25
  done
  return 1
}

cleanup() {
  "$W" --ipc shell hide omarchy.menu >/dev/null 2>&1 || true
  [[ -n ${shell_pid:-} ]] || return 0
  local pid=$shell_pid
  shell_pid=""
  kill -TERM "$pid" 2>/dev/null
  { sleep 2; kill -KILL "$pid" 2>/dev/null; } &
  local watchdog=$!
  wait "$pid" 2>/dev/null
  local sleeper
  sleeper=$(ps -o pid= --ppid "$watchdog" 2>/dev/null | tr -d ' ')
  kill "$watchdog" 2>/dev/null
  [[ -n $sleeper ]] && kill "$sleeper" 2>/dev/null
  wait "$watchdog" 2>/dev/null
  return 0
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

reply=""
for _ in $(seq 1 40); do
  reply=$("$W" --ipc shell ping 2>/dev/null) && [[ -n $reply ]] && break
  kill -0 "$shell_pid" 2>/dev/null || break
  sleep 0.25
done
assert_eq "$reply" "ok" "셸 ping (토글 전)"

plugins=$("$W" --ipc shell listPlugins 2>/dev/null) || plugins='[]'
menu_kinds=$(jq -r '[ .[] | select(.id == "omarchy.menu") | .kinds | join(",") ] | .[0] // "absent"' <<<"$plugins")
assert_eq "$menu_kinds" "menu,bar-widget" "R03 omarchy.menu 가 레지스트리에 있다"

before=$(jq -r 'length' <<<"$(menu_layers)")
[[ $before =~ ^[0-9]+$ ]] || before=0
assert_eq "$before" "0" "토글 전 omarchy-menu layer 없음"

out=$("$L" 2>&1); code=$?
assert_eq "$code" "0" "런처 토글 호출 exit 0"

wait_menu open && opened=0 || opened=1
assert_eq "$opened" "0" "R04 omarchy-menu layer 가 나타났다"
onscreen=$(menu_onscreen)
assert_eq "$onscreen" "omarchy-menu" "R04 메뉴 표면이 화면에 있다 (layer 기하)"
printf '      FINDING: 열린 메뉴 layer = %s\n' "$(menu_layers)"

# 완전한 layer 키보드 포커스 필드는 hyprctl layers 에 없지만, 최소한
# 메뉴 layer 매핑을 다시 단정한 뒤에만 Escape 를 보낸다.
assert_eq "$(jq -r 'length' <<<"$(menu_layers)")" "1" "R05 wtype 전 omarchy-menu layer 가 매핑됐다"
[[ $(jq -r 'length' <<<"$(menu_layers)") -eq 1 ]] || exit "$ASSERT_FAILURES"
sleep 0.3
wtype -k Escape
wait_menu closed && closed=0 || closed=1
assert_eq "$closed" "0" "R05 Escape 후 omarchy-menu layer 가 사라졌다"
assert_eq "$(menu_onscreen)" "" "R05 메뉴 표면이 화면에서 사라졌다"

cleanup
sleep 0.5
if [[ -n $cursor ]]; then
  journalctl --user --after-cursor "$cursor" -t cachy-omarchy-shell --no-pager -o cat > "$journal_log" 2>/dev/null
else
  journalctl --user --since "$since" -t cachy-omarchy-shell --no-pager -o cat > "$journal_log" 2>/dev/null
fi
[[ -f $journal_log ]] || : > "$journal_log"
assert_eq "$(grep -c "Configuration Loaded" "$journal_log")" "1" "기동 로그를 저널에서 수집했다"
errs=$(grep -ciE "ReferenceError|TypeError|is not a type|Cannot assign|unavailable" "$journal_log")
assert_eq "$errs" "0" "토글 경로에 QML 오류 없음"
fatal=$(grep -cE "ERROR" "$journal_log")
assert_eq "$fatal" "0" "토글 경로에 ERROR 레벨 없음"

remaining=$(hyprctl layers 2>/dev/null | grep -ci "omarchy-menu" || true)
assert_eq "$remaining" "0" "종료 후 omarchy-menu 가 남지 않는다"

exit "$ASSERT_FAILURES"
