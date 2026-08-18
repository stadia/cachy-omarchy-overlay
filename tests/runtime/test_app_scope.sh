#!/usr/bin/env bash
# 삭제된 test_uwsm_scope.sh 의 대체. 실제 AppLibrary launcher 경로가 real
# uwsm-app 으로 probe 를 app-graphical.slice scope 에 넣고, 추출 셸을 재시작해도
# probe 가 살아남는지 실측한다 (SPEC §45, 설계 문서 §9.3·§10.4).
#
# 안전: 사용자 세션의 셸은 절대 건드리지 않는다. 추출 트리를 OMARCHY_PATH 로
# 삼아 우리 인스턴스를 따로 띄우고, --restart 는 그 경로 패턴에만 매칭된다
# (cachy-omarchy-shell:100 — `quickshell -n -p $OMARCHY_PATH/shell`).
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/lib/runtime.sh"

[[ ${HOME:-} == "${COO_TEST_SANDBOX:?}" ]] \
  || { echo "FAIL: HOME 이 샌드박스가 아니다 — 중단"; exit 1; }

[[ ${COO_RUN_LIVE:-} == 1 ]] || { echo "skip: COO_RUN_LIVE=1 이 아니다"; exit 0; }
coo_live_runtime_usable || {
  echo "skip: 라이브 Wayland 런타임 없음 (quickshell/qs/systemd-cat 사용 불가 또는 WAYLAND_DISPLAY 소켓 없음)"
  exit 0
}
UWSM_APP=/usr/bin/uwsm-app
[[ -x $UWSM_APP ]] || {
  echo "skip: 실제 uwsm-app 이 PATH 에 없다 — Tier 2 스코프 격리를 검증할 수 없다 (uwsm 미설치 호스트)"
  exit 0
}
coo_pkg_artifact >/dev/null 2>&1 || { echo "skip: 셸 아티팩트 없음"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq 없음 — Apps menu layer 를 검증할 수 없다"; exit 1; }
command -v hyprctl >/dev/null 2>&1 || { echo "FAIL: hyprctl 없음 — Apps menu layer 를 검증할 수 없다"; exit 1; }
command -v wtype >/dev/null 2>&1 || { echo "FAIL: wtype 없음 — sandbox probe 를 선택할 수 없다"; exit 1; }
command -v gtk-launch >/dev/null 2>&1 || { echo "FAIL: gtk-launch 없음 — AppLibrary launcher 를 검증할 수 없다"; exit 1; }

# -q 는 패키지 이름만 출력하므로 pacman 의 locale-dependent ownership 문장을
# 파싱하지 않는다. 이 경로가 uwsm 소유가 아니면 bare launcher lookup 을 믿지
# 않고, 셸을 기동하기 전에 실패시킨다.
uwsm_owner=$(pacman -Qqo "$UWSM_APP" 2>/dev/null || true)
assert_eq "$uwsm_owner" "uwsm" "real /usr/bin/uwsm-app 은 uwsm 패키지 소유"
(( ASSERT_FAILURES == 0 )) || exit "$ASSERT_FAILURES"

root="$COO_TEST_SANDBOX/scope-root"
coo_extract_pkg "$root"
export COO_OMARCHY_PATH="$root/usr/share/cachy-omarchy/upstream"
export OMARCHY_PATH="$COO_OMARCHY_PATH"
# AppLibrary 는 bare uwsm-app 을 실행한다. 먼저 real /usr/bin 을 두어 artifact
# 또는 호출자 PATH 의 shim 이 아닌 uwsm 패키지 바이너리만 해석되게 한다.
export PATH="/usr/bin:$COO_OMARCHY_PATH/bin:$PATH"
W="$REPO_ROOT/overlay/bin/cachy-omarchy-shell"
SHELL_PAT="quickshell -n -p $COO_OMARCHY_PATH/shell"

# systemd-cat 의 cmdline 도 SHELL_PAT 를 포함하므로 pgrep 결과만 쓰면 부모 PID를
# 잡을 수 있다. /proc comm 이 quickshell 인 후보만 택해 정확히 추출한 runtime의
# 실제 renderer PID를 반환한다. SHELL_PAT 자체가 installed shell을 배제한다.
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

appsrc=$(cat "$COO_OMARCHY_PATH/shell/services/AppLibrary.qml")
assert_contains "$appsrc" 'uwsm-app -- gtk-launch' \
  "extracted AppLibrary 가 uwsm-app launcher route 를 사용한다"
(( ASSERT_FAILURES == 0 )) || exit "$ASSERT_FAILURES"

# probe 는 sandbox desktop entry 를 통해서만 선택한다. 이름은 실제 사용자
# desktop entry 와 충돌하지 않는 고정값이고, marker 의 PID 로만 정리한다.
PROBE_NAME=CooTask7ScopeProbe
pidfile="$COO_TEST_SANDBOX/scope-probe.pid"
probe="$COO_TEST_SANDBOX/scope-probe.sh"
rm -f "$pidfile"
cat >"$probe" <<PROBE
#!/usr/bin/env bash
printf '%s\n' "\$\$" >"$pidfile"
exec sleep 300
PROBE
chmod +x "$probe"
mkdir -p "$XDG_DATA_HOME/applications"
cat >"$XDG_DATA_HOME/applications/coo-task7-scope-probe.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$PROBE_NAME
Exec=$probe
Terminal=false
Categories=Utility;
EOF

# Quickshell 은 sandbox HOME 만 사용한다. bar-off 는 테스트 셸이 사용자 화면을
# 밀어내지 않도록 extracted shell 을 시작하기 전에 반드시 만든다.
mkdir -p "$HOME/.local/state/omarchy/toggles"
: > "$HOME/.local/state/omarchy/toggles/bar-off"

probe_pid=""
cleanup() {
  local pids candidate
  "$W" --ipc shell hide omarchy.menu >/dev/null 2>&1 || true
  # Return 직후 signal 이 오면 marker는 이미 쓰였지만 아래 대입은 아직 못 했을
  # 수 있다. sandbox pidfile에서 numeric PID만 복구해 test-owned probe만 정리한다.
  if [[ -z $probe_pid && -s $pidfile ]]; then
    candidate=$(cat "$pidfile" 2>/dev/null || true)
    [[ $candidate =~ ^[0-9]+$ ]] && probe_pid=$candidate
  fi
  [[ $probe_pid =~ ^[0-9]+$ ]] && kill -TERM "$probe_pid" 2>/dev/null
  pids=$(pgrep -f "$SHELL_PAT" 2>/dev/null || true)
  [[ -n $pids ]] && kill -TERM $pids 2>/dev/null
  sleep 0.5
  pids=$(pgrep -f "$SHELL_PAT" 2>/dev/null || true)
  [[ -n $pids ]] && kill -KILL $pids 2>/dev/null
  return 0
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# 1) 추출 트리의 셸만 기동한다. IPC 응답을 확인하지 못하면 어떤 키도 주입하지
# 않아 사용자 앱을 선택할 가능성을 없앤다.
"$W" --run >/dev/null 2>&1 &
for _ in $(seq 1 40); do
  reply=$("$W" --ipc shell ping 2>/dev/null) && [[ $reply == ok ]] && break
  sleep 0.25
done
assert_eq "${reply:-}" "ok" "테스트 전용 extracted shell 인스턴스 기동"
(( ASSERT_FAILURES == 0 )) || exit "$ASSERT_FAILURES"

# IPC가 준비된 뒤 test-owned 실제 quickshell PID를 확정한다. 이 PID로 menu
# layer를 묶어야 다른 설치 셸의 omarchy-menu가 wtype 안전 검사를 통과시키지 않는다.
shell_pid=$(test_shell_pid 2>/dev/null || true)
[[ $shell_pid =~ ^[0-9]+$ ]] && shell_found=0 || shell_found=1
assert_eq "$shell_found" "0" "test-owned extracted real quickshell PID 를 찾았다"
(( ASSERT_FAILURES == 0 )) || exit "$ASSERT_FAILURES"

# 2) AppLibrary → uwsm-app -- gtk-launch 경로로 sandbox probe 를 고른다.
menu_layers() {
  hyprctl -j layers 2>/dev/null | jq -c --argjson pid "$shell_pid" \
    '[ to_entries[].value.levels | to_entries[].value[]
       | select(.namespace == "omarchy-menu" and .pid == $pid) ]' \
    || echo '[]'
}

"$W" --ipc shell summon omarchy.menu '{"menu":"apps"}' >/dev/null
for _ in $(seq 1 40); do
  [[ $(jq -r 'length' <<<"$(menu_layers)") -gt 0 ]] && { menu_mapped=0; break; }
  sleep 0.25
done
assert_eq "${menu_mapped:-1}" "0" "wtype 전 Apps menu layer 가 mapped 됐다"
(( ASSERT_FAILURES == 0 )) || exit "$ASSERT_FAILURES"

# PID-scoped layer가 실제로 mapped 된 뒤, 그 layer를 만든 extracted upstream
# Menu.qml이 keyboard focus를 exclusive로 잡는 계약을 직접 확인한다.
menusrc=$(cat "$COO_OMARCHY_PATH/shell/plugins/menu/Menu.qml")
assert_contains "$menusrc" 'WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive' \
  "extracted Menu.qml 이 test-owned menu 에 Exclusive keyboard focus 를 준다"
(( ASSERT_FAILURES == 0 )) || exit "$ASSERT_FAILURES"

wtype "$PROBE_NAME"
sleep 0.4
wtype -k Return
for _ in $(seq 1 40); do
  [[ -s $pidfile ]] && break
  sleep 0.25
done
probe_pid=$(cat "$pidfile" 2>/dev/null)
[[ $probe_pid =~ ^[0-9]+$ ]] && kill -0 "$probe_pid" 2>/dev/null && found=0 || found=1
assert_eq "$found" "0" "AppLibrary 가 sandbox probe 를 launcher 로 띄웠다 (PID $probe_pid)"

if (( found == 0 )); then
  # 3) scope 배치와 extracted shell cgroup 분리
  cgroup=$(cat "/proc/$probe_pid/cgroup" 2>/dev/null)
  assert_contains "$cgroup" "app-graphical.slice" \
    "probe 가 app-graphical.slice 아래 있다"
  assert_contains "$cgroup" ".scope" "probe 가 자기 systemd scope 를 가진다"

  shell_cgroup=$(cat "/proc/$shell_pid/cgroup" 2>/dev/null)
  [[ $cgroup != "$shell_cgroup" ]] && detached=0 || detached=1
  assert_eq "$detached" "0" "probe cgroup 이 extracted shell cgroup 과 다르다"

  # 4) 핵심 단언: extracted shell 을 재시작해도 probe 가 살아남는다 (§10.4).
  "$W" --restart >/dev/null 2>&1
  for _ in $(seq 1 40); do
    reply=$("$W" --ipc shell ping 2>/dev/null) && [[ $reply == ok ]] && break
    sleep 0.25
  done
  assert_eq "${reply:-}" "ok" "재시작 후 extracted shell 이 다시 응답한다"

  new_shell_pid=$(test_shell_pid 2>/dev/null || true)
  [[ $new_shell_pid =~ ^[0-9]+$ && $new_shell_pid != "$shell_pid" ]] && replaced=0 || replaced=1
  assert_eq "$replaced" "0" "test-owned shell process 가 실제로 교체됐다"

  kill -0 "$probe_pid" 2>/dev/null && alive=0 || alive=1
  assert_eq "$alive" "0" "extracted shell 재시작 뒤에도 sandbox probe 가 살아있다"
fi

exit "$ASSERT_FAILURES"
