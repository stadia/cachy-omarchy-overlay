#!/usr/bin/env bash
# R06 live launch must type into the extracted shell's menu only. An unscoped
# omarchy-menu layer lets wtype hit the installed production menu.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

TEST="$REPO_ROOT/tests/runtime/test_app_launch.sh"
source_text=$(cat "$TEST")
assert_file_exists "$TEST" "R06 live launch test exists"

assert_contains "$source_text" 'SHELL_PAT="quickshell -n -p $root/shell"' \
  "shell matching 을 정확한 extracted path 로 scope 한다"
assert_contains "$source_text" '[[ $(<"/proc/$pid/comm") == quickshell ]]' \
  "PID resolver 가 systemd-cat parent 를 제외한다"

menu_block=$(sed -n '/^menu_layers() {/,/^}/p' "$TEST")
assert_contains "$menu_block" 'jq -c --argjson pid "$qs_pid"' \
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

wtype_line=$(grep -nE '^[[:space:]]*wtype ' "$TEST" | head -1 | cut -d: -f1)
menu_mapped_line=$(grep -nF 'R06 wtype 전 omarchy-menu layer 가 매핑됐다' "$TEST" | head -1 | cut -d: -f1)
[[ $menu_mapped_line =~ ^[0-9]+$ && $wtype_line =~ ^[0-9]+$ && $menu_mapped_line -lt $wtype_line ]] \
  && mapped_before_wtype=0 || mapped_before_wtype=1
assert_eq "$mapped_before_wtype" "0" "PID-scoped menu mapping 을 wtype 전에 확인한다"

exit "$ASSERT_FAILURES"
