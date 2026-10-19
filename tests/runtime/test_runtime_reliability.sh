#!/usr/bin/env bash
# M7 R01-R10 reliability evidence. Package files are tested from the two
# extracted archives; the manual wrapper-restart smoke is deliberately limited
# to a sandbox HOME. It exercises the upstream omarchy-launch-shell supervisor,
# not a systemd unit (the shell is launched by Hyprland autostart; recovery from
# a Qt _exit() is the supervisor's bounded relaunch, from anything else the
# manual `omarchy-restart-shell`).
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
W="$root/usr/bin/omarchy-launch-shell"
IPC="$root/usr/bin/omarchy-shell"
defaults="$root/usr/share/cachy-omarchy/upstream/config/omarchy/shell.json"
overlay_artifact=$(coo_overlay_artifact)

assert_file_exists "$W" "R01-R05 extracted upstream launcher exists"
assert_file_exists "$defaults" "R08-R10 extracted defaults exist"
assert_file_exists "$root/usr/share/cachy-omarchy/upstream/shell/shell.qml" \
  "R01-R03 extracted shell.qml exists"
assert_file_exists "$root/usr/bin/omarchy-menu" \
  "R04 extracted upstream menu command exists"
assert_file_exists "$root/usr/bin/omarchy-menu-keybindings" \
  "R05 extracted keybindings helper exists"
# 패키지에 든 헬퍼가 패치된 것이어야 한다 — 원본은 CachyOS 에서 빈 시트를 보인다.
assert_contains "$(cat "$root/usr/bin/omarchy-menu-keybindings")" "cachy-v1" \
  "R05 packaged keybindings helper carries patch 0003 (cachy-v1 cache key)"
# R06: app-launch now goes through the real uwsm-app from the uwsm package
# (session-environment redesign) instead of a shim we extract — there is no
# artifact of ours to assert here. Live coverage moves to Task 7's systemd
# scope test.

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
assert_contains "$(cat "$bindings")" 'hl.exec_cmd("omarchy-launch-shell")' "autostart launches the upstream supervisor"
unit="$root/usr/lib/systemd/user/cachy-omarchy-shell.service"
if [[ ! -e $unit ]]; then
  printf 'ok:   systemd unit is not packaged\n'
else
  printf 'FAIL: systemd unit still packaged: %s\n' "$unit" >&2
  ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
fi
printf '%s\n' '      FINDING: automatic start is asserted via packaged autostart bindings, not observed live here.'

# This is a manual extracted-tree launcher-restart smoke when a Wayland runtime
# is available. It does not exercise systemd Restart=on-failure: no user unit
# is enabled, started, or supervised by systemd in this test.
if ! coo_live_runtime_usable; then
  # This is deliberately a note, not a skip: the package-ownership R08-R10
  # assertions above did run.  M6 treats `skip:` as required-test failure;
  # the unavailable live recovery remains explicit evidence, not false green.
  printf '%s\n' 'note: manual launcher smoke UNVERIFIED (needs working systemd-cat/journald, quickshell, qs, and a live WAYLAND_DISPLAY socket)'
  exit "$ASSERT_FAILURES"
fi

export COO_PREFIX_ROOT="$root/usr/share/cachy-omarchy"
export COO_OMARCHY_PATH="$root/usr/share/cachy-omarchy/upstream"
export OMARCHY_PATH="$COO_OMARCHY_PATH"
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
  # 감독자가 되살린 인스턴스도 정리(테스트 전용 경로로 정밀 매칭).
  local pat="quickshell -n -p $COO_OMARCHY_PATH/shell" rpids
  rpids=$(pgrep -f "$pat" 2>/dev/null || true)
  [[ -n $rpids ]] && kill -KILL $rpids 2>/dev/null || true
}
start_shell() {
  "$W" >/dev/null 2>&1 &
  shell_pid=$!
}
wait_ping() {
  local reply="" n
  for n in $(seq 1 40); do
    reply=$("$IPC" shell ping 2>/dev/null) && [[ $reply == ok ]] && { printf '%s\n' "$reply"; return 0; }
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
  # 정상 종료(quickshell kill)는 감독자가 의도된 정지로 읽고 되살리지 않는다.
  # 실제 --restart(Hyprland 로 재기동)는 이 샌드박스 트리가 아니라 세션 트리를
  # 띄우므로 여기서 부르지 않는다 — 판정 로직은 test_shell_restart_lock.sh,
  # 실세션 동작은 수동 확인이 맡는다.
  quickshell kill -p "$COO_OMARCHY_PATH/shell" --any-display >/dev/null 2>&1
  for n in $(seq 1 50); do kill -0 "$shell_pid" 2>/dev/null || break; sleep 0.1; done
  kill -0 "$shell_pid" 2>/dev/null && supervisor_gone=1 || supervisor_gone=0
  assert_eq "$supervisor_gone" "0" "clean quickshell kill ends the supervisor without a relaunch"
fi

exit "$ASSERT_FAILURES"
