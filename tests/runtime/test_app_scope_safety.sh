#!/usr/bin/env bash
# Task 7 라이브 scope 검사는 설치된 셸을 건드리지 않고, 추출한 아티팩트만
# 대상으로 해야 한다. 이 정적 검사는 그 안전 경계가 느슨해지는 회귀를 막는다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

TEST="$REPO_ROOT/tests/runtime/test_app_scope.sh"
source_text=$(cat "$TEST")
assert_file_exists "$TEST" "앱 scope 라이브 테스트 존재"

assert_contains "$source_text" 'source "$REPO_ROOT/lib/runtime.sh"' \
  "라이브 테스트가 runtime artifact helper 를 source 한다"
assert_contains "$source_text" 'coo_pkg_artifact' \
  "셸 artifact 존재를 gate 한다"
assert_contains "$source_text" 'coo_extract_pkg "$root"' \
  "셸 artifact 를 sandbox root 로 추출한다"
assert_contains "$source_text" 'COO_OMARCHY_PATH="$root/usr/share/cachy-omarchy/upstream"' \
  "COO_OMARCHY_PATH 를 추출 runtime 으로 설정한다"
assert_contains "$source_text" 'OMARCHY_PATH="$COO_OMARCHY_PATH"' \
  "OMARCHY_PATH 를 추출 runtime 으로 설정한다"
assert_contains "$source_text" 'W="$REPO_ROOT/overlay/bin/cachy-omarchy-shell"' \
  "repository shell wrapper 를 사용한다"
assert_contains "$source_text" 'SHELL_PAT="quickshell -n -p $COO_OMARCHY_PATH/shell"' \
  "shell matching 을 정확한 extracted path 로 scope 한다"

# Quickshell 은 테스트의 sandbox HOME 만 쓰며, bar-off 가드를 셸 기동 전에
# 만들어야 테스트가 사용자 화면을 밀어내지 않는다.
assert_contains "$source_text" 'mkdir -p "$HOME/.local/state/omarchy/toggles"' \
  "sandbox HOME 에 toggle directory 를 만든다"
assert_contains "$source_text" ': > "$HOME/.local/state/omarchy/toggles/bar-off"' \
  "sandbox HOME 에 bar-off guard 를 만든다"
bar_guard_line=$(grep -nF ': > "$HOME/.local/state/omarchy/toggles/bar-off"' "$TEST" | head -1 | cut -d: -f1)
shell_run_line=$(grep -nF '"$W" --run' "$TEST" | head -1 | cut -d: -f1)
[[ $bar_guard_line =~ ^[0-9]+$ && $shell_run_line =~ ^[0-9]+$ && $bar_guard_line -lt $shell_run_line ]] && guard_before_run=0 || guard_before_run=1
assert_eq "$guard_before_run" "0" "bar-off guard 가 extracted shell 시작 전에 있다"

# scope 는 bare uwsm-app 호출이 아니라 AppLibrary → gtk-launch → real uwsm-app
# 경로에서만 측정한다. probe desktop 이름은 고정되어 실제 사용자 앱을 선택할
# 여지가 없고, 메뉴가 표시된 뒤에만 wtype 으로 선택한다.
assert_contains "$source_text" 'appsrc=$(cat "$COO_OMARCHY_PATH/shell/services/AppLibrary.qml")' \
  "extracted AppLibrary source 를 확인한다"
assert_contains "$source_text" "'uwsm-app -- gtk-launch'" \
  "AppLibrary 가 uwsm-app launcher route 를 사용한다"
assert_contains "$source_text" 'mkdir -p "$XDG_DATA_HOME/applications"' \
  "probe desktop 을 sandbox applications 에 만든다"
assert_contains "$source_text" '"$W" --ipc shell summon omarchy.menu' \
  "extracted shell IPC 로 Apps menu 를 summon 한다"
assert_contains "$source_text" 'hyprctl -j layers' \
  "input 전에 Apps menu layer 를 관측한다"
assert_contains "$source_text" 'wtype "$PROBE_NAME"' \
  "고정 probe desktop 이름만 입력한다"
if grep -E '^[[:space:]]*(setsid[[:space:]]+)?uwsm-app[[:space:]]+--' "$TEST" >/dev/null; then
  direct_uwsm_app=1
else
  direct_uwsm_app=0
fi
assert_eq "$direct_uwsm_app" "0" "probe 를 uwsm-app 으로 직접 실행하지 않는다"

assert_contains "$source_text" 'UWSM_APP=/usr/bin/uwsm-app' \
  "real uwsm-app path 를 명시한다"
assert_contains "$source_text" 'skip: 라이브 Wayland 런타임 없음 (quickshell/qs/systemd-cat 사용 불가 또는 WAYLAND_DISPLAY 소켓 없음)' \
  "runtime skip 문구가 test-packages allowlist 와 일치한다"
assert_contains "$source_text" 'skip: 실제 uwsm-app 이 PATH 에 없다 — Tier 2 스코프 격리를 검증할 수 없다 (uwsm 미설치 호스트)' \
  "uwsm skip 문구가 test-packages allowlist 와 일치한다"
assert_contains "$source_text" 'skip: 셸 아티팩트 없음' \
  "artifact absence 는 false-green 정책이 포착할 수 있는 skip 으로 남긴다"
assert_contains "$source_text" 'pacman -Qqo "$UWSM_APP"' \
  "locale-safe pacman quiet ownership query 를 사용한다"
assert_contains "$source_text" 'assert_eq "$uwsm_owner" "uwsm"' \
  "real uwsm-app owner 를 uwsm 으로 단언한다"
assert_contains "$source_text" 'PATH="/usr/bin:$COO_OMARCHY_PATH/bin:$PATH"' \
  "launcher bare name 이 real /usr/bin uwsm-app 을 먼저 해석한다"
if grep -F 'command -v uwsm-app' "$TEST" >/dev/null; then
  path_resolved_uwsm_app=1
else
  path_resolved_uwsm_app=0
fi
assert_eq "$path_resolved_uwsm_app" "0" "PATH-resolved uwsm-app probe 또는 shim 을 쓰지 않는다"

# Apps menu 는 다른 셸의 layer 가 아니라, IPC-ready extracted Quickshell PID
# 에 속한 layer 여야 한다. systemd-cat 부모는 같은 cmdline 일부를 가지므로
# /proc comm 으로 실제 quickshell process 만 고른다.
assert_contains "$source_text" 'test_shell_pid()' \
  "extracted runtime 의 real quickshell PID resolver 가 있다"
assert_contains "$source_text" '[[ $(<"/proc/$pid/comm") == quickshell ]]' \
  "PID resolver 가 systemd-cat parent 를 제외한다"
assert_contains "$source_text" 'shell_pid=$(test_shell_pid 2>/dev/null || true)' \
  "test shell IPC ready 뒤 real quickshell PID 를 얻는다"
assert_contains "$source_text" 'new_shell_pid=$(test_shell_pid 2>/dev/null || true)' \
  "restart replacement 도 같은 real quickshell PID resolver 를 쓴다"

ipc_ready_line=$(grep -nF 'assert_eq "${reply:-}" "ok" "테스트 전용 extracted shell 인스턴스 기동"' "$TEST" | head -1 | cut -d: -f1)
shell_pid_line=$(grep -nF 'shell_pid=$(test_shell_pid 2>/dev/null || true)' "$TEST" | head -1 | cut -d: -f1)
[[ $ipc_ready_line =~ ^[0-9]+$ && $shell_pid_line =~ ^[0-9]+$ && $ipc_ready_line -lt $shell_pid_line ]] && pid_after_ipc=0 || pid_after_ipc=1
assert_eq "$pid_after_ipc" "0" "real quickshell PID 는 test-shell IPC readiness 뒤에 확인한다"

menu_block=$(sed -n '/^menu_layers() {/,/^}/p' "$TEST")
assert_contains "$menu_block" 'jq -c --argjson pid "$shell_pid"' \
  "menu layer query 에 test-owned quickshell PID 를 준다"
assert_contains "$menu_block" 'select(.namespace == "omarchy-menu" and .pid == $pid)' \
  "menu layer 를 namespace 와 test-owned PID 모두로 filter 한다"
menu_selects=$(grep -F 'select(.namespace == "omarchy-menu"' "$TEST" || true)
if grep -Fv 'and .pid == $pid' <<<"$menu_selects" >/dev/null; then
  unscoped_menu_layer=1
else
  unscoped_menu_layer=0
fi
assert_eq "$unscoped_menu_layer" "0" "global omarchy-menu layer 가 mapped 조건을 만족시키지 않는다"

# PID-scoped mapped layer만으로는 키보드 focus 정책까지 증명하지 못한다. 실제
# extracted Menu.qml이 Exclusive keyboard focus를 선언하는지 확인하고, 그 확인도
# mapped-layer 판정 뒤 wtype 전에 끝나야 한다.
assert_contains "$source_text" 'menusrc=$(cat "$COO_OMARCHY_PATH/shell/plugins/menu/Menu.qml")' \
  "extracted Menu.qml keyboard routing source 를 읽는다"
assert_contains "$source_text" 'WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive' \
  "extracted Menu.qml 이 Exclusive keyboard focus 를 선언한다"
menu_mapped_line=$(grep -nF 'assert_eq "${menu_mapped:-1}" "0" "wtype 전 Apps menu layer 가 mapped 됐다"' "$TEST" | head -1 | cut -d: -f1)
keyboard_contract_line=$(grep -nF 'WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive' "$TEST" | head -1 | cut -d: -f1)
wtype_line=$(grep -nF 'wtype "$PROBE_NAME"' "$TEST" | head -1 | cut -d: -f1)
[[ $menu_mapped_line =~ ^[0-9]+$ && $keyboard_contract_line =~ ^[0-9]+$ && $wtype_line =~ ^[0-9]+$ && $menu_mapped_line -lt $keyboard_contract_line && $keyboard_contract_line -lt $wtype_line ]] && keyboard_route_before_input=0 || keyboard_route_before_input=1
assert_eq "$keyboard_route_before_input" "0" "PID-scoped menu mapping과 Exclusive keyboard routing을 wtype 전에 확인한다"

pgrep_lines=$(grep -E 'pgrep[[:space:]]+-f' "$TEST" || true)
assert_contains "$pgrep_lines" '"$SHELL_PAT"' \
  "모든 shell pgrep 이 exact SHELL_PAT 를 사용한다"
if grep -E 'pgrep[[:space:]]+-f' "$TEST" | grep -Fv '"$SHELL_PAT"' >/dev/null 2>&1; then
  unscoped_pgrep=1
else
  unscoped_pgrep=0
fi
assert_eq "$unscoped_pgrep" "0" "unscoped quickshell matching 이 없다"

cleanup_block=$(sed -n '/^cleanup() {/,/^}/p' "$TEST")
assert_contains "$cleanup_block" 'pgrep -f "$SHELL_PAT"' \
  "cleanup 이 exact SHELL_PAT process 만 찾는다"
assert_contains "$cleanup_block" 'kill -TERM $pids' \
  "cleanup 이 extracted shell process 만 종료한다"
assert_contains "$cleanup_block" 'kill -KILL $pids' \
  "cleanup 이 extracted shell process 만 강제 종료한다"
assert_contains "$cleanup_block" '[[ -z $probe_pid && -s $pidfile ]]' \
  "cleanup 이 Return 직후 marker 의 probe PID 를 복구한다"
assert_contains "$cleanup_block" 'candidate=$(cat "$pidfile" 2>/dev/null || true)' \
  "cleanup 이 sandbox pidfile 만 읽는다"
assert_contains "$cleanup_block" '[[ $candidate =~ ^[0-9]+$ ]] && probe_pid=$candidate' \
  "cleanup 이 numeric marker PID 만 probe PID 로 수용한다"
recovery_line=$(grep -nF '[[ -z $probe_pid && -s $pidfile ]]' "$TEST" | head -1 | cut -d: -f1)
probe_kill_line=$(grep -nF 'kill -TERM "$probe_pid"' "$TEST" | head -1 | cut -d: -f1)
[[ $recovery_line =~ ^[0-9]+$ && $probe_kill_line =~ ^[0-9]+$ && $recovery_line -lt $probe_kill_line ]] && recovery_before_kill=0 || recovery_before_kill=1
assert_eq "$recovery_before_kill" "0" "marker PID recovery 가 probe kill 보다 먼저 실행된다"
if grep -Eq '(^|[[:space:]])(pkill|killall)([[:space:]]|$)' <<<"$cleanup_block"; then
  broad_cleanup=1
else
  broad_cleanup=0
fi
assert_eq "$broad_cleanup" "0" "cleanup 에 broad process killer 가 없다"
cleanup_kills=$(grep -E 'kill[[:space:]]' <<<"$cleanup_block" || true)
if grep -Ev 'kill -TERM "\$probe_pid"|kill -TERM \$pids|kill -KILL \$pids' <<<"$cleanup_kills" >/dev/null; then
  unexpected_cleanup_kill=1
else
  unexpected_cleanup_kill=0
fi
assert_eq "$unexpected_cleanup_kill" "0" "cleanup 은 probe PID 와 extracted shell PID 만 종료한다"

if grep -E '(^|[[:space:];])cachy-omarchy-shell[[:space:]]+--restart' "$TEST" >/dev/null; then
  bare_restart=1
else
  bare_restart=0
fi
assert_eq "$bare_restart" "0" "bare installed cachy-omarchy-shell restart 를 호출하지 않는다"
assert_contains "$source_text" '"$W" --restart' \
  "restart 는 repository wrapper 로만 수행한다"

exit "$ASSERT_FAILURES"
