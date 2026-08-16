#!/usr/bin/env bash
# Task 1: cachy-omarchy-launcher 정적 계약 + IPC 오류 문자열 실측.
# 메뉴를 실제로 열지 않는다 (R04/R05 는 Task 2).
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/lib/runtime.sh"

L="$REPO_ROOT/overlay/bin/cachy-omarchy-launcher"
W="$REPO_ROOT/overlay/bin/cachy-omarchy-shell"

assert_file_exists "$L" "런처 존재"
[[ -x $L ]] && x=0 || x=1
assert_eq "$x" "0" "런처 실행 가능"
[[ -x $L ]] || exit 1

out=$("$L" --help 2>&1); code=$?
assert_eq "$code" "0" "--help exit 0"
assert_contains "$out" "omarchy.menu" "--help 가 omarchy.menu 를 설명한다"
assert_contains "$out" "--ipc" "--help 가 셸 IPC 위임을 설명한다"

# IPC 를 재발명하지 않는다 — 정본 래퍼를 부른다.
src=$(cat "$L")
assert_contains "$src" 'cachy-omarchy-shell --ipc' "셸 --ipc 에 위임한다"
assert_contains "$src" "toggle omarchy.menu" "토글 대상은 omarchy.menu"
assert_contains "$src" '{"menu":"root"}' "루트 메뉴 인자를 그대로 전달한다"

out=$("$L" --nonsense 2>&1); code=$?
assert_eq "$code" "1" "알 수 없는 인자 → exit 1"

out=$(COO_OMARCHY_PATH=/nonexistent "$L" 2>&1); code=$?
assert_eq "$code" "1" "잘못된 OMARCHY_PATH → exit 1"
assert_contains "$out" "shell.qml" "오류가 무엇이 없는지 말해준다"

dest="$COO_TEST_SANDBOX/pkg"
if coo_extract_pkg "$dest" 2>/dev/null; then
  root=$(coo_upstream_root "$dest")
  out=$(COO_OMARCHY_PATH="$root" "$L" 2>&1); code=$?
  assert_eq "$code" "1" "셸 미기동 → exit 1"
  assert_contains "$out" "기동" "미기동 안내가 있다"
fi

# ---------------------------------------------------------------- IPC 오류 문자열 실측 (M2 발견 3)
# 메뉴 토글은 하지 않는다. 잘못된 target/method 만 호출한다.
coo_live_runtime_usable || { exit "$ASSERT_FAILURES"; }
coo_pkg_artifact >/dev/null || { exit "$ASSERT_FAILURES"; }
[[ -n ${root:-} ]] || { exit "$ASSERT_FAILURES"; }

[[ ${HOME:-} == "${COO_TEST_SANDBOX:?}" ]] || {
  printf 'FAIL: HOME 이 샌드박스가 아니다 — 사용자 상태를 건드릴 수 있어 중단한다\n' >&2
  exit 1
}

mkdir -p "$HOME/.local/state/omarchy/toggles"
: > "$HOME/.local/state/omarchy/toggles/bar-off"

export COO_OMARCHY_PATH="$root"
export OMARCHY_PATH="$root"
"$W" --run >/dev/null 2>&1 &
shell_pid=$!
cleanup() {
  [[ -n ${shell_pid:-} ]] || return 0
  local pid=$shell_pid
  shell_pid=""
  kill -TERM "$pid" 2>/dev/null
  { sleep 2; kill -KILL "$pid" 2>/dev/null; } &
  local watchdog=$!
  wait "$pid" 2>/dev/null
  local sleeper
  sleeper=$(ps -o pid= --ppid "$watchdog" 2>/dev/null | tr -d ' ')
  kill "$watchdog" 2>/dev/null
  [[ -n $sleeper ]] && kill "$sleeper" 2>/dev/null
  wait "$watchdog" 2>/dev/null
  return 0
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

reply=""
for _ in $(seq 1 40); do
  reply=$("$W" --ipc shell ping 2>/dev/null) && [[ -n $reply ]] && break
  kill -0 "$shell_pid" 2>/dev/null || break
  sleep 0.25
done
assert_eq "$reply" "ok" "실측 전 ping 이 살아 있다"

measure_raw() {
  timeout --kill-after=1s 2s qs ipc -n -p "$root/shell" call -- "$@" 2>/dev/null
}

raw_target=$(measure_raw nosuch ping || true)
raw_fn=$(measure_raw shell nosuchfn || true)
printf 'measured ipc target-miss: %q\n' "$raw_target"
printf 'measured ipc function-miss: %q\n' "$raw_fn"

assert_contains "$raw_target" "Target not found." "qs 가 Target not found. 를 stdout 으로 낸다"
assert_contains "$raw_fn" "Function not found." "qs 가 Function not found. 를 stdout 으로 낸다"

out=$("$W" --ipc nosuch ping 2>&1); code=$?
assert_eq "$code" "1" "없는 target → 래퍼 exit 1 (silent success 금지)"
assert_contains "$out" "Target not found." "래퍼가 실측 문자열을 실패로 승격한다"

out=$("$W" --ipc shell nosuchfn 2>&1); code=$?
assert_eq "$code" "1" "없는 method → 래퍼 exit 1"
assert_contains "$out" "Function not found." "래퍼가 Function not found. 를 실패로 승격한다"

exit "$ASSERT_FAILURES"
