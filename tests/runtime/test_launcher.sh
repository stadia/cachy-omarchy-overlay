#!/usr/bin/env bash
# SUPER+SPACE 체인(업스트림 omarchy-menu → compat omarchy-shell → 래퍼)과 호환
# 별칭, IPC 오류 문자열 실측. 메뉴를 실제로 열지 않는다 (R04/R05 는
# test_launcher_toggle.sh).
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/lib/runtime.sh"

L="$REPO_ROOT/overlay/bin/cachy-omarchy-launcher"
W="$REPO_ROOT/overlay/bin/cachy-omarchy-shell"
COMPAT="$REPO_ROOT/overlay/compat/bin"

# SUPER+SPACE 는 업스트림 `omarchy-menu toggle` 이다. 호환 별칭
# cachy-omarchy-launcher 는 옛 사용자 바인딩 사본을 위해 그것으로 넘긴다.
fake="$COO_TEST_SANDBOX/launcher-fake"
mkdir -p "$fake"
cat >"$fake/omarchy-menu" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$COO_FAKE_LOG"
STUB
chmod +x "$fake/omarchy-menu"
PATH="$fake:$PATH" COO_FAKE_LOG="$fake/menu.log" "$L"; code=$?
assert_eq "$code" "0" "호환 별칭 exit 0"
assert_eq "$(cat "$fake/menu.log")" "toggle" "호환 별칭은 omarchy-menu toggle 로 넘긴다"

# 실제 체인: 업스트림 omarchy-menu → compat omarchy-shell → 우리 셸 래퍼.
# 래퍼 자리에 스텁을 둬 IPC 인자만 본다(셸을 띄우지 않는다).
cat >"$fake/cachy-omarchy-shell" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$COO_FAKE_LOG"
STUB
chmod +x "$fake/cachy-omarchy-shell"

dest="$COO_TEST_SANDBOX/pkg"
if coo_extract_pkg "$dest" 2>/dev/null; then
  root=$(coo_upstream_root "$dest")
  PATH="$COMPAT:$PATH" COO_SHELL_BIN="$fake/cachy-omarchy-shell" COO_FAKE_LOG="$fake/ipc.log" \
    "$root/bin/omarchy-menu" toggle; code=$?
  assert_eq "$code" "0" "omarchy-menu toggle 체인 exit 0"
  assert_eq "$(cat "$fake/ipc.log")" $'--ipc\nshell\ntoggle\nomarchy.menu\n{"menu":"root"}' \
    "omarchy-menu toggle 이 래퍼에 루트 메뉴 토글 IPC 를 보낸다"
fi

# ---------------------------------------------------------------- IPC 오류 문자열 실측 (M2 발견 3)
# 메뉴 토글은 하지 않는다. 잘못된 target/method 만 호출한다.
coo_live_runtime_usable || { echo "skip: 라이브 Wayland 런타임 없음 (quickshell/qs/systemd-cat 사용 불가 또는 WAYLAND_DISPLAY 소켓 없음)"; exit "$ASSERT_FAILURES"; }
coo_pkg_artifact >/dev/null || { echo "skip: 셸 아티팩트 없음"; exit "$ASSERT_FAILURES"; }
[[ -n ${root:-} ]] || { printf 'FAIL: 아티팩트는 있는데 추출에 실패했다\n'; exit 1; }

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
