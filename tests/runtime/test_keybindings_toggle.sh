#!/usr/bin/env bash
# M4 Task 3: upstream select-mode keybinding UI opens through our public helper.
# Render proof is omarchy-menu layer geometry; never select a live binding.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/lib/runtime.sh"

command -v quickshell >/dev/null || { echo "skip: quickshell 없음"; exit 0; }
command -v jq >/dev/null || { echo "skip: jq 없음"; exit 0; }
command -v hyprctl >/dev/null || { echo "skip: hyprctl 없음"; exit 0; }
command -v wtype >/dev/null || { echo "skip: wtype 없음 (Escape)"; exit 0; }
[[ -n ${WAYLAND_DISPLAY:-} ]] || { echo "skip: WAYLAND_DISPLAY 없음"; exit 0; }
coo_pkg_artifact >/dev/null || { echo "skip: build/*.pkg.tar.zst 없음"; exit 0; }

[[ ${HOME:-} == "${COO_TEST_SANDBOX:?}" ]] || {
  printf 'FAIL: HOME 이 샌드박스가 아니다 — 사용자 상태를 건드릴 수 있어 중단한다\n' >&2
  exit 1
}

# tests/test.sh changes HOME to the sandbox. The Lua source cache must instead
# inspect a read-only copy of the config that produced the live hyprctl binds.
passwd_home=$(getent passwd "${USER:?}" 2>/dev/null | awk -F: 'NR == 1 { print $6 }')
HOST_HYPR_LUA=${COO_HOST_HYPR_LUA:-$passwd_home/.config/hypr/hyprland.lua}
[[ -f $HOST_HYPR_LUA ]] || { echo "skip: 실사용 hyprland.lua 없음: $HOST_HYPR_LUA"; exit 0; }
install -D -m444 "$HOST_HYPR_LUA" "$HOME/.config/hypr/hyprland.lua"

dest="$COO_TEST_SANDBOX/pkg"
coo_extract_pkg "$dest" || { echo "skip: 추출 실패"; exit 0; }
root=$(coo_upstream_root "$dest")

mkdir -p "$HOME/.local/state/omarchy/toggles"
: > "$HOME/.local/state/omarchy/toggles/bar-off"

K="$REPO_ROOT/overlay/bin/cachy-omarchy-keybindings"
W="$REPO_ROOT/overlay/bin/cachy-omarchy-shell"
export COO_OMARCHY_PATH="$root"
export COO_COMPAT_BIN="$REPO_ROOT/overlay/compat/bin"
export COO_SHELL_BIN="$W"
export OMARCHY_PATH="$root"

# This milestone adds no QML viewer. The only task diff must remain shell test code.
qml_changes=$(git -C "$REPO_ROOT" diff --name-only d700681 -- '*.qml' 2>/dev/null || true)
assert_eq "$qml_changes" "" "Task 3 에 새 QML 키바인드 뷰어 변경 없음"

journal_log="$COO_TEST_SANDBOX/shell.journal"
cursor=$(journalctl --user -n 0 --show-cursor 2>/dev/null | sed -n 's/^-- cursor: //p')
since=$(date '+%Y-%m-%d %H:%M:%S')

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

stop_pid() {
  local pid=${1:-} watchdog sleeper
  [[ -n $pid ]] || return 0
  kill -0 "$pid" 2>/dev/null || return 0
  kill -TERM "$pid" 2>/dev/null || true
  { sleep 2; kill -KILL "$pid" 2>/dev/null || true; } &
  watchdog=$!
  wait "$pid" 2>/dev/null || true
  sleeper=$(ps -o pid= --ppid "$watchdog" 2>/dev/null | tr -d ' ')
  kill "$watchdog" 2>/dev/null || true
  [[ -n $sleeper ]] && kill "$sleeper" 2>/dev/null || true
  wait "$watchdog" 2>/dev/null || true
}

shell_pid=""
helper_pid=""
cleanup() {
  "$W" --ipc shell hide omarchy.menu >/dev/null 2>&1 || true
  stop_pid "${helper_pid:-}"
  helper_pid=""
  stop_pid "${shell_pid:-}"
  shell_pid=""
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

"$W" --run >/dev/null 2>&1 &
shell_pid=$!

reply=""
for _ in $(seq 1 40); do
  reply=$("$W" --ipc shell ping 2>/dev/null) && [[ -n $reply ]] && break
  kill -0 "$shell_pid" 2>/dev/null || break
  sleep 0.25
done
assert_eq "$reply" "ok" "셸 ping (키바인드 UI 전)"

before=$(jq -r 'length' <<<"$(menu_layers)")
[[ $before =~ ^[0-9]+$ ]] || before=0
assert_eq "$before" "0" "헬퍼 전 omarchy-menu layer 없음"

# Direct helper invocation is intentional: Task 4 owns the managed SUPER+K bind.
"$K" >/dev/null 2>&1 &
helper_pid=$!

wait_menu open && opened=0 || opened=1
assert_eq "$opened" "0" "키바인드 UI omarchy-menu layer 가 나타났다"
onscreen=$(menu_onscreen)
assert_eq "$onscreen" "omarchy-menu" "키바인드 UI 표면이 화면에 있다 (layer 기하)"
printf '      FINDING: 열린 keybindings layer = %s\n' "$(menu_layers)"

# The cache proves real bind rows were available. It is supplementary evidence;
# the layer geometry above is the render proof. Never press Return or select.
cache_file=$(find "$HOME/.cache/omarchy" -maxdepth 1 -type f -name 'keybindings-*.records' -print -quit 2>/dev/null || true)
assert_file_exists "${cache_file:-/missing/keybindings.records}" "샌드박스 keybindings 캐시가 생겼다"
cache_count=0
if [[ -n $cache_file && -f $cache_file ]]; then
  cache_count=$(wc -l <"$cache_file" | tr -d ' ')
fi
assert_eq "$cache_count" "48" "실사용 CachyOS Lua 바인드 48개가 모두 수집됐다"
printf '      FINDING: keybindings cache records = %s\n' "$cache_count"

# Allow the select menu to receive exclusive focus, then cancel only.
sleep 0.3
wtype -k Escape
wait_menu closed && closed=0 || closed=1
assert_eq "$closed" "0" "Escape 취소 후 omarchy-menu layer 가 사라졌다"
assert_eq "$(menu_onscreen)" "" "Escape 후 메뉴 표면이 화면에서 사라졌다"

helper_code=999
for _ in $(seq 1 40); do
  if ! kill -0 "$helper_pid" 2>/dev/null; then
    if wait "$helper_pid"; then helper_code=0; else helper_code=$?; fi
    helper_pid=""
    break
  fi
  sleep 0.25
done
[[ $helper_code != 999 ]] && helper_exited=0 || helper_exited=1
assert_eq "$helper_exited" "0" "Escape 취소 뒤 helper PID 가 종료한다"
printf '      FINDING: helper cancellation exit = %s\n' "$helper_code"

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
assert_eq "$errs" "0" "키바인드 UI 경로에 QML 오류 없음"
fatal=$(grep -cE "ERROR" "$journal_log")
assert_eq "$fatal" "0" "키바인드 UI 경로에 ERROR 레벨 없음"

remaining=$(hyprctl layers 2>/dev/null | grep -ci "omarchy-menu" || true)
assert_eq "$remaining" "0" "종료 후 omarchy-menu 가 남지 않는다"

exit "$ASSERT_FAILURES"
