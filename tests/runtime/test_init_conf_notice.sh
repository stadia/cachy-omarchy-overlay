#!/usr/bin/env bash
# hyprland.conf 는 지원하지 않는다(Lua 전용). conf 만 있으면 init 은 아무것도
# 쓰기 전에 실패한다 — 테마 시드·PAM 이 적용된 채 반쯤 설치되지 않도록.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

INIT="$REPO_ROOT/overlay/bin/cachy-omarchy-init"
MARK="hyprland.conf 는 지원하지 않는다"

run_init() { # $1 = 케이스 디렉터리, 나머지 = init 인자
  local d=$1; shift
  HOME="$d/home" COO_HYPR_DIR="$d/hypr" \
    COO_CONFIG_DIR="$d/home/.config/cachy-omarchy" \
    COO_STATE_DIR="$d/home/.local/state/omarchy" \
    COO_PAM_LOCK_FILE="$d/pam-present" \
    "$INIT" "$@" 2>&1
}

mk() { # $1 = 케이스 이름 → 준비된 디렉터리 경로를 stdout 으로
  local d; d=$(mktemp -d "${TMPDIR:-/tmp}/coo-init-notice-$1-XXXXXX")
  mkdir -p "$d/home/.config" "$d/hypr"
  : > "$d/pam-present"
  printf '%s\n' "$d"
}

# 상태 1: conf 만 있다 → dry-run 이든 아니든 실패하고, 아무것도 쓰지 않는다.
d1=$(mk conf); printf 'monitor=,preferred,auto,1\n' > "$d1/hypr/hyprland.conf"
conf_before=$(cat "$d1/hypr/hyprland.conf")
for args in "--dry-run" ""; do
  out=$(run_init "$d1" ${args:+$args}); code=$?
  assert_eq "$code" "1" "conf 전용 구성은 init ${args:-(실행)} 이 실패한다"
  assert_contains "$out" "$MARK" "conf 전용 구성은 사유를 말한다 (${args:-실행})"
done
assert_eq "$(cat "$d1/hypr/hyprland.conf")" "$conf_before" "init 은 hyprland.conf 를 건드리지 않는다"
[[ -e $d1/home/.config/cachy-omarchy || -e $d1/home/.local/state/omarchy ]] && wrote=1 || wrote=0
assert_eq "$wrote" "0" "실패한 init 은 설정·상태 디렉터리를 만들지 않는다"

# 상태 2~4: lua 가 있거나(conf 동반 포함) 설정이 없으면 이 사유로 실패하지 않는다.
d2=$(mk lua); printf '%s\n' '-- lua config' > "$d2/hypr/hyprland.lua"
d3=$(mk both)
printf 'monitor=,preferred,auto,1\n' > "$d3/hypr/hyprland.conf"
printf '%s\n' '-- lua config' > "$d3/hypr/hyprland.lua"
d4=$(mk none)
for d in "$d2" "$d3" "$d4"; do
  out=$(run_init "$d" --dry-run); code=$?
  if [[ $out == *"$MARK"* ]]; then
    printf 'FAIL: %s 에서는 conf 비지원으로 실패하지 않는다\n' "${d##*/}"; ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
  else
    printf 'ok:   %s 에서는 conf 비지원으로 실패하지 않는다\n' "${d##*/}"
  fi
done

rm -rf "$d1" "$d2" "$d3" "$d4"
exit "$ASSERT_FAILURES"
