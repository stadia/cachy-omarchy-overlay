#!/usr/bin/env bash
# hyprland.conf 는 지원하지 않는다(Lua 전용). conf 만 있는 사용자는 설치 시점에
# init 이 알린다. 설치를 막지는 않는다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

INIT="$REPO_ROOT/overlay/bin/cachy-omarchy-init"
MARK="hyprland.conf 는 지원하지 않는다"

run_init() { # $1 = hypr 디렉터리
  HOME="$1/home" COO_HYPR_DIR="$1/hypr" \
    COO_CONFIG_DIR="$1/home/.config/cachy-omarchy" \
    COO_STATE_DIR="$1/home/.local/state/omarchy" \
    COO_PAM_LOCK_FILE="$1/pam-present" \
    "$INIT" --dry-run 2>&1
}

mk() { # $1 = 케이스 이름 → 준비된 디렉터리 경로를 stdout 으로
  local d; d=$(mktemp -d "${TMPDIR:-/tmp}/coo-init-notice-$1-XXXXXX")
  mkdir -p "$d/home/.config" "$d/hypr"
  : > "$d/pam-present"
  printf '%s\n' "$d"
}

# 상태 1: conf 만 있다 → 고지한다.
d1=$(mk conf); printf 'monitor=,preferred,auto,1\n' > "$d1/hypr/hyprland.conf"
assert_contains "$(run_init "$d1")" "$MARK" "conf 전용 구성에서 고지한다"

# 상태 2: lua 가 있다 → 고지하지 않는다.
d2=$(mk lua); printf '%s\n' '-- lua config' > "$d2/hypr/hyprland.lua"
out2=$(run_init "$d2")
if [[ $out2 == *"$MARK"* ]]; then
  printf 'FAIL: lua 구성에서는 고지하지 않는다\n'; ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
else
  printf 'ok:   lua 구성에서는 고지하지 않는다\n'
fi

# 상태 3: 둘 다 있다 → 고지하지 않는다 (lua 가 있으면 그것을 쓴다).
d3=$(mk both)
printf 'monitor=,preferred,auto,1\n' > "$d3/hypr/hyprland.conf"
printf '%s\n' '-- lua config' > "$d3/hypr/hyprland.lua"
out3=$(run_init "$d3")
if [[ $out3 == *"$MARK"* ]]; then
  printf 'FAIL: conf+lua 구성에서는 고지하지 않는다\n'; ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
else
  printf 'ok:   conf+lua 구성에서는 고지하지 않는다\n'
fi

# 상태 4: 설정이 없다 → 고지하지 않는다.
d4=$(mk none)
out4=$(run_init "$d4")
if [[ $out4 == *"$MARK"* ]]; then
  printf 'FAIL: 설정이 없으면 고지하지 않는다\n'; ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
else
  printf 'ok:   설정이 없으면 고지하지 않는다\n'
fi

# 고지는 설치를 막지 않는다.
code=0; run_init "$d1" >/dev/null 2>&1 || code=$?
assert_eq "$code" "0" "고지해도 init 은 실패하지 않는다"

rm -rf "$d1" "$d2" "$d3" "$d4"
exit "$ASSERT_FAILURES"
