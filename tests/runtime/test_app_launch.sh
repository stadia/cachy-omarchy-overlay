#!/usr/bin/env bash
# R06: dummy desktop is launched through AppLibrary (uwsm-app -- gtk-launch).
# Shim delegates to a real uwsm-app when one is on PATH, else falls back to
# exec'ing the target directly (see test_uwsm_app_shim.sh for both paths in
# isolation). PATH is shell-process only.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/lib/runtime.sh"

SHIM="$REPO_ROOT/overlay/compat/bin/uwsm-app"
W="$REPO_ROOT/overlay/bin/cachy-omarchy-shell"

assert_file_exists "$SHIM" "uwsm-app shim 존재"
[[ -x $SHIM ]] && x=0 || x=1
assert_eq "$x" "0" "uwsm-app shim 실행 가능"
[[ -x $SHIM ]] || exit 1

src=$(cat "$SHIM")
assert_contains "$src" 'exec "$@"' "shim 은 나머지를 exec 한다 (REIMPLEMENT 아님)"

host=$(command -v uwsm-app 2>/dev/null || true)
if [[ -n $host ]]; then
  echo "info: 호스트에 실제 uwsm-app 있음 ($host) — 아래 exec 는 shim 의 위임 경로를 탄다"
else
  echo "info: 호스트에 uwsm-app 없음 — 아래 exec 는 shim 의 fallback 경로를 탄다"
fi

marker=$COO_TEST_SANDBOX/r06.marker
: >"$COO_TEST_SANDBOX/r06.probe.sh"
cat >"$COO_TEST_SANDBOX/r06.probe.sh" <<EOF
#!/usr/bin/env bash
printf 'launched\n' > '$marker'
EOF
chmod +x "$COO_TEST_SANDBOX/r06.probe.sh"

out=$("$SHIM" -- "$COO_TEST_SANDBOX/r06.probe.sh"); code=$?
assert_eq "$code" "0" "shim -- cmd 가 위임한다"
assert_eq "$(cat "$marker")" "launched" "shim 이 대상 명령을 실행했다"
rm -f "$marker"

wrap=$(cat "$W")
assert_contains "$wrap" 'COMPAT_BIN' "래퍼가 compat PATH 를 셸 프로세스에만 붙인다"

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
export COO_COMPAT_BIN="$REPO_ROOT/overlay/compat/bin"

"$W" --run >/dev/null 2>&1 &
shell_pid=$!

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
assert_eq "$reply" "ok" "셸 ping (R06 전)"

envp=$(tr '\0' '\n' <"/proc/$shell_pid/environ" 2>/dev/null || true)
assert_contains "$envp" "$COO_COMPAT_BIN" "셸 PATH 에 compat shim 디렉터리가 있다"
parent_path=$PATH
[[ $parent_path == *"$COO_COMPAT_BIN"* ]] && p=1 || p=0
assert_eq "$p" "0" "테스트 프로세스 PATH 는 compat 으로 오염되지 않는다"

menu_layers() {
  hyprctl -j layers 2>/dev/null | jq -c \
    '[ to_entries[].value.levels | to_entries[].value[] | select(.namespace == "omarchy-menu") ]' \
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
remaining=$(hyprctl layers 2>/dev/null | grep -ci "omarchy-menu" || true)
assert_eq "$remaining" "0" "종료 전 omarchy-menu 가 닫혔다"

exit "$ASSERT_FAILURES"
