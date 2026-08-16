#!/usr/bin/env bash
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

U="$REPO_ROOT/overlay/systemd/cachy-omarchy-shell.service"
assert_file_exists "$U" "유닛 존재"
[[ -f $U ]] || exit 1
unit=$(cat "$U")

assert_contains "$unit" "Description=" "설명"
assert_contains "$unit" "PartOf=graphical-session.target" "세션과 생명주기 연동"
assert_contains "$unit" "After=graphical-session.target" "순서"
assert_contains "$unit" "ExecStart=/usr/bin/cachy-omarchy-shell --run" "ExecStart 는 래퍼를 부른다"
assert_contains "$unit" "Restart=on-failure" "재시작 정책"
assert_contains "$unit" "ConditionEnvironment=WAYLAND_DISPLAY" "Wayland 세션에서만 실행"
assert_contains "$unit" "WantedBy=graphical-session.target" "설치 대상"

assert_eq "$(grep -c '^\[Service\]$' "$U")" "1" "[Service] 정확히 하나"
assert_eq "$(grep -c '^ExecStart=' "$U")" "1" "ExecStart 정확히 하나 (line-anchored)"
assert_eq "$(grep -c '^ConditionEnvironment=WAYLAND_DISPLAY$' "$U")" "1" "ConditionEnvironment 정확히 하나 (line-anchored)"
assert_eq "$(grep -c '^WantedBy=graphical-session.target$' "$U")" "1" "WantedBy 정확히 하나 (line-anchored)"

# 유닛이 quickshell 을 직접 부르면 안 된다 — 기동 명령은 래퍼가 소유한다.
assert_eq "$(grep -ci 'quickshell' "$U")" "0" "유닛은 quickshell 을 직접 부르지 않는다 (case-insensitive)"
# 컴포지터를 띄우려 하면 안 된다.
assert_eq "$(grep -ci 'hyprland' "$U")" "0" "유닛은 Hyprland 를 띄우지 않는다"

exit "$ASSERT_FAILURES"
