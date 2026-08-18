#!/usr/bin/env bash
# R06: dummy desktop is launched through AppLibrary (uwsm-app -- gtk-launch).
# uwsm-app is no longer a shim we ship — it comes from the uwsm package. This
# test proves the QML source calls it correctly and that a live app launch
# reaches the target through the shell (below). The real uwsm-app's process
# placement (systemd scope) is measured live by Task 7, not here.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/lib/runtime.sh"

W="$REPO_ROOT/overlay/bin/cachy-omarchy-shell"

marker=$COO_TEST_SANDBOX/r06.marker
: >"$COO_TEST_SANDBOX/r06.probe.sh"
cat >"$COO_TEST_SANDBOX/r06.probe.sh" <<EOF
#!/usr/bin/env bash
printf 'launched\n' > '$marker'
EOF
chmod +x "$COO_TEST_SANDBOX/r06.probe.sh"

command -v jq >/dev/null || { exit "$ASSERT_FAILURES"; }
command -v hyprctl >/dev/null || { exit "$ASSERT_FAILURES"; }
command -v wtype >/dev/null || { echo "skip: wtype 없음 (R06 라이브)"; exit "$ASSERT_FAILURES"; }
[[ ${COO_RUN_LIVE:-0} == 1 ]] || { echo "skip: 라이브 키 주입 (COO_RUN_LIVE=1 필요)"; exit 0; }
command -v gtk-launch >/dev/null || { echo "skip: gtk-launch 없음"; exit "$ASSERT_FAILURES"; }
coo_live_runtime_usable || { exit "$ASSERT_FAILURES"; }
coo_pkg_artifact >/dev/null || { exit "$ASSERT_FAILURES"; }

[[ ${HOME:-} == "${COO_TEST_SANDBOX:?}" ]] || {
  printf 'FAIL: HOME 이 샌드박스가 아니다 — 사용자 상태를 건드릴 수 있어 중단한다\n' >&2
  exit 1
}

dest="$COO_TEST_SANDBOX/pkg"
coo_extract_pkg "$dest" || { echo "skip: 추출 실패"; exit "$ASSERT_FAILURES"; }
root=$(coo_upstream_root "$dest")

appsrc=$(cat "$root/shell/services/AppLibrary.qml")
assert_contains "$appsrc" 'uwsm-app -- gtk-launch' "AppLibrary.launch 가 uwsm-app -- gtk-launch 를 부른다"

mkdir -p "$HOME/.local/state/omarchy/toggles"
: > "$HOME/.local/state/omarchy/toggles/bar-off"
mkdir -p "$XDG_DATA_HOME/applications"
cat >"$XDG_DATA_HOME/applications/coo-r06-probe.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=CooR06Probe
Exec=$COO_TEST_SANDBOX/r06.probe.sh
Terminal=false
Categories=Utility;
EOF

export COO_OMARCHY_PATH="$root"
export OMARCHY_PATH="$root"
# 실제 설치에서는 /usr/bin/omarchy-* 심링크가 helper 를 공급한다. 추출 트리에는
# 그 심링크가 있지만 /usr/bin 에 설치되지 않았으므로, 호출자 PATH 로 같은
# 가시성을 만든다 — 래퍼는 더 이상 PATH 를 조작하지 않는다 (SPEC §45).
export PATH="$root/bin:$PATH"
SHELL_PAT="quickshell -n -p $root/shell"

test_shell_pid() {
  local pid
  for pid in $(pgrep -f "$SHELL_PAT" 2>/dev/null || true); do
    [[ $pid =~ ^[0-9]+$ && -r /proc/$pid/comm ]] || continue
    [[ $(<"/proc/$pid/comm") == quickshell ]] || continue
    printf '%s\n' "$pid"
    return 0
  done
  return 1
}

"$W" --run >/dev/null 2>&1 &
wrapper_pid=$!

cleanup() {
  "$W" --ipc shell hide omarchy.menu >/dev/null 2>&1 || true
  [[ -n ${wrapper_pid:-} ]] || return 0
  local pid=$wrapper_pid
  wrapper_pid=""
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
  kill -0 "$wrapper_pid" 2>/dev/null || break
  sleep 0.25
done
assert_eq "$reply" "ok" "셸 ping (R06 전)"

qs_pid=$(test_shell_pid 2>/dev/null || true)
[[ $qs_pid =~ ^[0-9]+$ ]] && qs_found=0 || qs_found=1
assert_eq "$qs_found" "0" "test-owned extracted real quickshell PID 를 찾았다"
(( ASSERT_FAILURES == 0 )) || exit "$ASSERT_FAILURES"

envp=$(tr '\0' '\n' <"/proc/$qs_pid/environ" 2>/dev/null || true)
assert_contains "$envp" "$root/bin" "셸 프로세스가 호출자 PATH 를 그대로 물려받았다"

menu_layers() {
  hyprctl -j layers 2>/dev/null | jq -c --argjson pid "$qs_pid" \
    '[ to_entries[].value.levels | to_entries[].value[]
       | select(.namespace == "omarchy-menu" and .pid == $pid) ]' \
    || echo '[]'
}

"$W" --ipc shell summon omarchy.menu '{"menu":"apps"}' >/dev/null
menu_mapped=1
for _ in $(seq 1 40); do
  [[ $(jq -r 'length' <<<"$(menu_layers)") -gt 0 ]] && { menu_mapped=0; break; }
  sleep 0.25
done
assert_eq "$menu_mapped" "0" "R06 wtype 전 omarchy-menu layer 가 매핑됐다"
(( menu_mapped == 0 )) || exit "$ASSERT_FAILURES"

wtype CooR06Probe
sleep 0.4
wtype -k Return

launched=1
for _ in $(seq 1 40); do
  if [[ -f $marker ]]; then
    launched=0
    break
  fi
  sleep 0.25
done
assert_eq "$launched" "0" "R06 dummy 앱이 마커를 남겼다"
[[ -f $marker ]] && assert_eq "$(cat "$marker")" "launched" "R06 마커 내용"

"$W" --ipc shell hide omarchy.menu >/dev/null 2>&1 || true
sleep 0.2
remaining=$(jq -r 'length' <<<"$(menu_layers)")
assert_eq "$remaining" "0" "종료 전 omarchy-menu 가 닫혔다"

exit "$ASSERT_FAILURES"
