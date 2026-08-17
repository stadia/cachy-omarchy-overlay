#!/usr/bin/env bash
# M7 R01-R10 reliability evidence. Package files are tested from the two
# extracted archives; the manual wrapper-restart smoke is deliberately limited
# to a sandbox HOME. It exercises `cachy-omarchy-shell --restart`, not a systemd
# unit (the shell is launched by Hyprland autostart; R07 auto-restart is not
# provided — recovery is manual `--restart`).
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/lib/runtime.sh"

coo_pkg_artifact >/dev/null 2>&1 || { echo "skip: shell artifact unavailable"; exit 0; }
coo_overlay_artifact >/dev/null 2>&1 || { echo "skip: overlay artifact unavailable"; exit 0; }
[[ ${HOME:-} == "${COO_TEST_SANDBOX:?}" ]] || {
  echo "FAIL: HOME is not the test sandbox" >&2
  exit 1
}

root="$COO_TEST_SANDBOX/root"
coo_extract_overlay "$root"
coo_extract_pkg "$root"
W="$root/usr/bin/cachy-omarchy-shell"
defaults="$root/usr/share/cachy-omarchy/defaults/shell.json"
overlay_artifact=$(coo_overlay_artifact)

assert_file_exists "$W" "R01-R06 and manual-restart extracted wrapper exists"
assert_file_exists "$defaults" "R08-R10 extracted defaults exist"
assert_file_exists "$root/usr/share/cachy-omarchy/upstream/shell/shell.qml" \
  "R01-R03 extracted shell.qml exists"
assert_file_exists "$root/usr/bin/cachy-omarchy-launcher" \
  "R04 extracted launcher exists"
assert_file_exists "$root/usr/bin/cachy-omarchy-keybindings" \
  "R05 extracted keybindings helper exists"
assert_file_exists "$root/usr/lib/cachy-omarchy/compat/bin/uwsm-app" \
  "R06 extracted app-launch compatibility wrapper exists"

# R08: an archive/extracted-tree audit is the strongest claim possible without
# writing the user's configuration.  It proves this package owns neither a
# Waybar path nor a system unit or package install script that could modify one.
overlay_paths=$(bsdtar -tf "$overlay_artifact")
assert_eq "$(grep -Ec '^(etc/|usr/lib/systemd/system/|home/|root/)' <<<"$overlay_paths" || true)" "0" \
  "R08 no /etc, system unit, or user-home path is owned"
assert_eq "$(grep -Eic '(^|/)waybar([/.]|$)' <<<"$overlay_paths" || true)" "0" \
  "R08 no Waybar path is owned"
assert_eq "$(grep -Ec '^\.INSTALL$' <<<"$overlay_paths" || true)" "0" \
  "R08 no install script can modify Waybar configuration"
assert_eq "$(find "$root" -path '*/etc/*' -o -path '*/usr/lib/systemd/system/*' | wc -l | tr -d ' ')" "0" \
  "R08 extracted tree has no /etc or system unit"

# R09/R10 were rewritten for M8.  This shell now ships the upstream
# notification and lock plugins ENABLED — suppressing them was reversed
# (M8 principle 0: upstream defaults are the default).  The invariant that
# survives is narrower and is the one that actually protects the user: we
# never own a system path for a competing daemon and we never stop one.
# Handing mako's D-Bus name over is a measured, consented takeover, not a
# package-level eviction.
assert_eq "$(jq -r 'has("disabledPlugins")' "$defaults")" "false" \
  "R09/R10 extracted defaults disable no plugin"
assert_eq "$(grep -Eic '^(etc/.*(notification|dunst|mako)|usr/lib/systemd/system/.*(notification|dunst|mako))' <<<"$overlay_paths" || true)" "0" \
  "R09 no notification daemon /etc or system-unit path is owned"
assert_eq "$(grep -Eic '^(etc/.*(lock|hyprlock)|usr/lib/systemd/system/.*(lock|hyprlock))' <<<"$overlay_paths" || true)" "0" \
  "R10 no lock replacement /etc or system-unit path is owned"
printf '%s\n' '      FINDING: R09/R10 only audit package ownership; live mako/hyprlock takeover behaviour is verified by the M8 live task, not here.'

# Auto-start intent is now declared in the autostart bindings, not a systemd
# unit. The unit is gone from the package. This test never enables/starts a
# unit or changes a live user configuration.
bindings="$root/usr/share/cachy-omarchy/hypr/bindings.lua"
assert_file_exists "$bindings" "autostart bindings are packaged"
assert_contains "$(cat "$bindings")" "hyprland.start" "autostart trigger is declared"
assert_contains "$(cat "$bindings")" "cachy-omarchy-shell --run" "autostart launches the wrapper"
unit="$root/usr/lib/systemd/user/cachy-omarchy-shell.service"
if [[ ! -e $unit ]]; then
  printf 'ok:   systemd unit is not packaged\n'
else
  printf 'FAIL: systemd unit still packaged: %s\n' "$unit" >&2
  ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
fi
printf '%s\n' '      FINDING: automatic start is asserted via packaged autostart bindings, not observed live here.'

# This is a manual extracted-tree wrapper-restart smoke when a Wayland runtime
# is available. It does not exercise systemd Restart=on-failure: no user unit
# is enabled, started, or supervised by systemd in this test.
if ! coo_live_runtime_usable; then
  # This is deliberately a note, not a skip: the package-ownership R08-R10
  # assertions above did run.  M6 treats `skip:` as required-test failure;
  # the unavailable live recovery remains explicit evidence, not false green.
  printf '%s\n' 'note: manual --restart smoke UNVERIFIED (needs working systemd-cat/journald, quickshell, qs, and a live WAYLAND_DISPLAY socket)'
  exit "$ASSERT_FAILURES"
fi

export COO_PREFIX_ROOT="$root/usr/share/cachy-omarchy"
export COO_OMARCHY_PATH="$root/usr/share/cachy-omarchy/upstream"
export COO_COMPAT_BIN="$root/usr/lib/cachy-omarchy/compat/bin"
export COO_IPC_TIMEOUT=1s
mkdir -p "$HOME/.local/state/omarchy/toggles"
: > "$HOME/.local/state/omarchy/toggles/bar-off"

shell_pid=""
stop_shell() {
  local pid=${shell_pid:-} n=0
  shell_pid=""
  [[ -n $pid ]] && kill -TERM "$pid" 2>/dev/null || true
  while kill -0 "$pid" 2>/dev/null && (( n < 20 )); do sleep 0.1; n=$((n + 1)); done
  kill -KILL "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  # --restart 가 detached 로 띄운 인스턴스도 정리(테스트 전용 경로로 정밀 매칭).
  local pat="quickshell -n -p $COO_OMARCHY_PATH/shell" rpids
  rpids=$(pgrep -f "$pat" 2>/dev/null || true)
  [[ -n $rpids ]] && kill -KILL $rpids 2>/dev/null || true
}
start_shell() {
  "$W" --run >/dev/null 2>&1 &
  shell_pid=$!
}
wait_ping() {
  local reply="" n
  for n in $(seq 1 40); do
    reply=$("$W" --ipc shell ping 2>/dev/null) && [[ $reply == ok ]] && { printf '%s\n' "$reply"; return 0; }
    kill -0 "$shell_pid" 2>/dev/null || return 1
    sleep 0.25
  done
  return 1
}
trap stop_shell EXIT
trap 'stop_shell; exit 130' INT
trap 'stop_shell; exit 143' TERM

start_shell
first_reply=$(wait_ping 2>/dev/null || true)
assert_eq "$first_reply" "ok" "manual wrapper first start responds to IPC"
if [[ $first_reply == ok ]]; then
  stop_shell
  start_shell
  recovered_reply=$(wait_ping 2>/dev/null || true)
  assert_eq "$recovered_reply" "ok" "manual wrapper restart after owned PID kill recovers IPC"
  # --restart: detached kill + 재기동. 추적 PID 는 죽고, 새 인스턴스가 IPC 응답.
  shell_pid_prev=$shell_pid
  out=$("$W" --restart 2>&1); rc=$?
  assert_eq "$rc" "0" "--restart exits 0 (detached relaunch)"
  sleep 0.3
  assert_eq "$(kill -0 "$shell_pid_prev" 2>/dev/null; echo $?)" "1" "--restart killed the old instance"
  restart_reply=$(wait_ping 2>/dev/null || true)
  assert_eq "$restart_reply" "ok" "--restart relaunches a shell that answers IPC"
  # 멱등: 이미 떠 있으면 --run 은 no-op(exit 0)하고 새 인스턴스를 늘리지 않는다.
  before_n=$(pgrep -f "quickshell -n -p $COO_OMARCHY_PATH/shell" 2>/dev/null | wc -l | tr -d ' ')
  out=$("$W" --run 2>&1); rc=$?
  assert_eq "$rc" "0" "--run while running is no-op exit 0"
  after_n=$(pgrep -f "quickshell -n -p $COO_OMARCHY_PATH/shell" 2>/dev/null | wc -l | tr -d ' ')
  assert_eq "$after_n" "$before_n" "--run no-op does not add an instance"
fi

exit "$ASSERT_FAILURES"
