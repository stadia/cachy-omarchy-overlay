#!/usr/bin/env bash
# M4 Task 1: the upstream keybinding path is measured and the docs record the
# measurements. Docs + needles only — no wrapper ships in this task.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

AUDIT="$REPO_ROOT/docs/COMMAND_AUDIT.md"
DEPS="$REPO_ROOT/docs/RUNTIME_DEPENDENCIES.md"

assert_file_exists "$AUDIT" "COMMAND_AUDIT.md 존재"
audit=$(cat "$AUDIT")

# --- 키바인딩 UI 절이 M4 실측으로 채워졌다 ---------------------------------
[[ $audit == *"의존 감사는 M4"* ]] && stale=1 || stale=0
assert_eq "$stale" "0" "감사를 M4 로 미루는 문구는 사라졌다"
assert_contains "$audit" "hyprctl binds" "동적 수집은 plain hyprctl binds"
assert_contains "$audit" "xkbcli compile-keymap" "code: 키 해석은 xkbcli compile-keymap"
assert_contains "$audit" "omarchy-menu-select" "검색 메뉴는 omarchy-menu-select"
assert_contains "$audit" "omarchy-cmd-present" "lua 캐시 가드는 omarchy-cmd-present"
assert_contains "$audit" "JSON::PP" "select payload 는 perl JSON::PP"
assert_contains "$audit" "gum 미사용" "이 경로는 gum 미사용(실측)"

# --- 호스트 실측: 업스트림 그대로는 정적 2행만 나온다 -------------------------
assert_contains "$audit" "48" "호스트 bind 48개 실측이 기록됨"
assert_contains "$audit" "정적" "정적 2행만 나온다는 실측이 기록됨"
assert_contains "$audit" "__lua" "description-less __lua drop 이 기록됨"

assert_file_exists "$DEPS" "RUNTIME_DEPENDENCIES.md 존재"
deps=$(cat "$DEPS")

[[ $deps == *"TUI 헬퍼는 M4 키바인딩 UI"* ]] && stale=1 || stale=0
assert_eq "$stale" "0" "gum 행의 M4 예측 문구는 사라졌다"
assert_contains "$deps" "gum" "gum 행이 남아 있다"
assert_contains "$deps" "미사용" "gum 미사용 실측이 기록됨"
assert_contains "$deps" "xkbcli" "xkbcli 행이 추가됐다"
assert_contains "$deps" 'JSON::PP' "perl JSON::PP 실측이 기록됨"
assert_contains "$deps" '`lua`' "lua 행이 추가됐다"

exit "$ASSERT_FAILURES"
