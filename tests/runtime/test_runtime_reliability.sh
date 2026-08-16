#!/usr/bin/env bash
# M7 R01-R10 reliability evidence.  Package files are tested from the two
# extracted archives; the manual wrapper-restart smoke is deliberately limited
# to a sandbox HOME. It is not a systemd Restart=on-failure service test.
# It never enables/starts a user unit or changes a live user configuration.
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

# R09/R10: disabled plugins prevent this shell from providing the upstream
# notification/lock components.  The package audit only proves no replacement
# is owned; it cannot prove a real dunst/mako/hyprlock session is preserved.
assert_eq "$(jq -r '.disabledPlugins | index("omarchy.notifications") != null' "$defaults")" "true" \
  "R09 omarchy.notifications is disabled"
assert_eq "$(jq -r '.disabledPlugins | index("omarchy.lock") != null' "$defaults")" "true" \
  "R10 omarchy.lock is disabled"
assert_eq "$(grep -Eic '^(etc/.*(notification|dunst|mako)|usr/lib/systemd/system/.*(notification|dunst|mako))' <<<"$overlay_paths" || true)" "0" \
  "R09 no notification daemon /etc or system-unit path is owned"
assert_eq "$(grep -Eic '^(etc/.*(lock|hyprlock)|usr/lib/systemd/system/.*(lock|hyprlock))' <<<"$overlay_paths" || true)" "0" \
  "R10 no lock replacement /etc or system-unit path is owned"
printf '%s\n' '      FINDING: R09/R10 only audit package ownership; live dunst/mako/hyprlock preservation is UNVERIFIED.'

# This is a read-only observation.  WantedBy is unit install intent, not an
# observed start: this test never calls enable, start, daemon-reload, or reload.
unit="$root/usr/lib/systemd/user/cachy-omarchy-shell.service"
assert_file_exists "$unit" "auto-start unit is packaged as a user unit"
assert_contains "$(cat "$unit")" "WantedBy=graphical-session.target" \
  "auto-start intent is declared"
if command -v systemctl >/dev/null 2>&1; then
  target_state=$(systemctl --user is-active graphical-session.target 2>&1); target_code=$?
  target_show=$(systemctl --user show graphical-session.target \
    --property=ActiveState --property=SubState --no-page 2>&1); show_code=$?
  printf '      FINDING: graphical-session.target read-only state (is-active exit=%s): %s\n' \
    "$target_code" "$target_state"
  printf '      FINDING: graphical-session.target read-only show (exit=%s): %s\n' \
    "$show_code" "${target_show//$'\n'/; }"
else
  printf '%s\n' '      FINDING: systemctl unavailable; automatic start is UNVERIFIED.'
fi
printf '%s\n' '      FINDING: no target activation was requested; automatic start is UNVERIFIED.'

# This is a manual extracted-tree wrapper-restart smoke when a Wayland runtime
# is available. It does not exercise systemd Restart=on-failure: no user unit
# is enabled, started, or supervised by systemd in this test.
if ! command -v quickshell >/dev/null || ! command -v qs >/dev/null || \
   ! command -v systemd-cat >/dev/null || [[ -z ${WAYLAND_DISPLAY:-} ]]; then
  # This is deliberately a note, not a skip: the package-ownership R08-R10
  # assertions above did run.  M6 treats `skip:` as required-test failure;
  # the unavailable live recovery remains explicit evidence, not false green.
  printf '%s\n' 'note: manual wrapper-restart smoke UNVERIFIED (needs quickshell, qs, systemd-cat, and WAYLAND_DISPLAY); R07 systemd service recovery remains UNVERIFIED'
  exit "$ASSERT_FAILURES"
fi

export COO_PREFIX_ROOT="$root/usr/share/cachy-omarchy"
export COO_OMARCHY_PATH="$COO_PREFIX_ROOT/upstream"
export COO_COMPAT_BIN="$root/usr/lib/cachy-omarchy/compat/bin"
export COO_IPC_TIMEOUT=1s
mkdir -p "$HOME/.local/state/omarchy/toggles"
: > "$HOME/.local/state/omarchy/toggles/bar-off"

shell_pid=""
stop_shell() {
  local pid=${shell_pid:-} n=0
  shell_pid=""
  [[ -n $pid ]] || return 0
  kill -TERM "$pid" 2>/dev/null || true
  while kill -0 "$pid" 2>/dev/null && (( n < 20 )); do sleep 0.1; n=$((n + 1)); done
  kill -KILL "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
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
  # This is our just-created wrapper PID, never a broad pkill/killall match.
  stop_shell
  start_shell
  recovered_reply=$(wait_ping 2>/dev/null || true)
  assert_eq "$recovered_reply" "ok" "manual wrapper restart after owned PID kill recovers IPC"
fi

exit "$ASSERT_FAILURES"
