#!/usr/bin/env bash
# omarchy-restart-shell 은 세션이 잠긴 동안 셸을 죽이면 안 된다. 계약(허용 목록): 스키마가
# 온전한(locked/secure/requested 세 키가 다 있는) "unlocked" 응답, 그리고 보존할
# 락이 확실히 없는 두 경우("is not running" = 셸 미실행, "Target not found." =
# lock 플러그인 부재)만 진행한다. 기동 중·무응답·알 수 없는 오류·파싱 불가·키 누락은
# 전부 안전하게 거부한다. 진행할 때는 Hyprland 에 닿는지 확인한 뒤 정상 종료
# (quickshell kill) 하고 Hyprland 가 omarchy-launch-shell 을 띄운다 — TERM 으로
# 죽이면 감독자가 되살려 이중 기동하기 때문이다.
# 실제 quickshell/hyprlock/Hyprland 는 전혀 건드리지 않는다 — omarchy-shell,
# quickshell, hyprctl, pgrep 을 모두 스텁으로 교체한다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

W="$REPO_ROOT/overlay/compat/bin/omarchy-restart-shell"
assert_file_exists "$W" "래퍼 존재"

fake="$COO_TEST_SANDBOX/restart-lock"
stub="$fake/stub"
calls="$fake/calls.log"
mkdir -p "$fake/upstream/shell" "$stub"
: > "$fake/upstream/shell/shell.qml"
: > "$calls"

# 가짜 omarchy-shell: "lock status" 에는 $STUB_LOCK_JSON(stdout)·$STUB_LOCK_ERR
# (stderr)·$STUB_LOCK_EXIT 를, "shell ping" 에는 ok 를 돌려준다.
cat > "$stub/omarchy-shell" <<'STUB'
#!/usr/bin/env bash
printf 'omarchy-shell %s\n' "$*" >> "$COO_CALL_LOG"
if [[ $1 == lock && $2 == status ]]; then
  printf '%s' "${STUB_LOCK_JSON:-}"
  printf '%s' "${STUB_LOCK_ERR:-}" >&2
  exit "${STUB_LOCK_EXIT:-0}"
fi
echo ok
STUB
# kill 은 한 번만 성공하고(살아 있던 셸) 그 다음은 실패한다(더 없음).
cat > "$stub/quickshell" <<'STUB'
#!/usr/bin/env bash
printf 'quickshell %s\n' "$*" >> "$COO_CALL_LOG"
[[ -e $COO_CALL_LOG.killed ]] && exit 1
: > "$COO_CALL_LOG.killed"
exit 0
STUB
# STUB_HYPR_FAIL=monitors|dispatch 로 해당 호출만 실패시킨다.
cat > "$stub/hyprctl" <<'STUB'
#!/usr/bin/env bash
printf 'hyprctl %s\n' "$*" >> "$COO_CALL_LOG"
if [[ $1 == -j && ${STUB_HYPR_FAIL:-} == monitors ]] || [[ $1 == dispatch && ${STUB_HYPR_FAIL:-} == dispatch ]]; then
  echo "hyprctl stub failure" >&2
  exit 1
fi
STUB
# STUB_PGREP_ALIVE=1 이면 옛 인스턴스가 끝내 안 죽는다.
cat > "$stub/pgrep" <<'STUB'
#!/usr/bin/env bash
[[ ${STUB_PGREP_ALIVE:-0} == 1 ]]
STUB
chmod +x "$stub"/*

run_restart() {
  : > "$calls"; rm -f "$calls.killed"
  PATH="$stub:$PATH" \
    COO_OMARCHY_PATH="$fake/upstream" \
    COO_CALL_LOG="$calls" \
    COO_EXIT_WAIT=1 COO_READY_WAIT=1 \
    STUB_LOCK_JSON="${1:-}" \
    STUB_LOCK_ERR="${3:-}" \
    STUB_LOCK_EXIT="${2:-0}" \
    STUB_HYPR_FAIL="${STUB_HYPR_FAIL:-}" STUB_PGREP_ALIVE="${STUB_PGREP_ALIVE:-0}" \
    "$W"
}

killed() { grep -q '^quickshell kill' "$calls"; }
launched() { grep -qF 'hyprctl dispatch hl.dsp.exec_cmd("omarchy-launch-shell")' "$calls"; }

refuses() {
  local label=$1 json=$2 exit_code=$3 err=${4:-} out code k l
  out=$(run_restart "$json" "$exit_code" "$err" 2>&1); code=$?
  assert_eq "$code" "1" "$label → exit 1"
  assert_contains "$out" "Refusing to restart the shell" "$label → 거부 메시지"
  killed && k=1 || k=0
  assert_eq "$k" "0" "$label → quickshell kill 미호출"
  launched && l=1 || l=0
  assert_eq "$l" "0" "$label → 재기동 미요청"
}

proceeds() {
  local label=$1 json=$2 exit_code=$3 err=${4:-} out code k l
  out=$(run_restart "$json" "$exit_code" "$err" 2>&1); code=$?
  assert_eq "$code" "0" "$label → exit 0"
  killed && k=1 || k=0
  assert_eq "$k" "1" "$label → quickshell kill 로 정상 종료"
  launched && l=1 || l=0
  assert_eq "$l" "1" "$label → Hyprland 에 omarchy-launch-shell 재기동 요청"
}

refuses "secure:true" '{"locked":true,"secure":true,"requested":false}' 0
refuses "requested:true" '{"locked":true,"secure":false,"requested":true}' 0
refuses "locked 만 true" '{"locked":true,"secure":false,"requested":false}' 0
refuses "파싱 불가" 'not json' 0
# {} 는 스키마 불완전: 세 키를 모두 요구하지 않으면 fail-open 이 된다.
refuses "{}" '{}' 0
# 셸이 기동 중이면 락 서비스가 아직 로드 중일 수 있다.
refuses "not ready" '' 1 'omarchy-shell is not ready'

proceeds "잠기지 않음" '{"locked":false,"secure":false,"requested":false}' 0
proceeds "셸 미실행" '' 1 'omarchy-shell is not running'
proceeds "lock 서비스 부재" '' 1 'Target not found.'
# 허용 목록 밖은 전부 거부 — 잠긴 채 멈춘 셸, 명령 부재, 업스트림의 새 오류 문구.
refuses "IPC 무응답" '' 1 'omarchy-shell is not responding'
refuses "명령 부재(127)" '' 127 'omarchy-shell: command not found'
refuses "알 수 없는 오류" '' 1 'Something new went wrong'
refuses "오류 문구 없는 nonzero" '' 1 ''

# 순서: 종료가 재기동보다 먼저다.
run_restart '{"locked":false,"secure":false,"requested":false}' 0 >/dev/null 2>&1
kill_line=$(grep -n '^quickshell kill' "$calls" | head -1 | cut -d: -f1)
launch_line=$(grep -n '^hyprctl dispatch' "$calls" | head -1 | cut -d: -f1)
assert_eq "$(( kill_line < launch_line ? 1 : 0 ))" "1" "정상 종료가 재기동보다 먼저다"
assert_contains "$(grep '^quickshell kill' "$calls" | head -1)" "-p $fake/upstream/shell --any-display" "kill 은 이 트리의 셸만 겨냥한다"

# OMARCHY_PATH 가 없는 곳을 가리키면 조용히 성공하지 말고 무엇이 없는지 말한다.
out=$(COO_OMARCHY_PATH=/nonexistent "$W" 2>&1); code=$?
assert_eq "$code" "1" "잘못된 OMARCHY_PATH → exit 1"
assert_contains "$out" "shell.qml" "오류가 무엇이 없는지 말해준다"

# Hyprland 에 닿지 못하면 셸을 죽이기 전에 멈춘다(죽인 뒤엔 되살릴 수 없다).
unlocked='{"locked":false,"secure":false,"requested":false}'
out=$(STUB_HYPR_FAIL=monitors run_restart "$unlocked" 0 2>&1); code=$?
assert_eq "$code" "1" "Hyprland 에 못 닿으면 exit 1"
assert_contains "$out" "hyprctl stub failure" "hyprctl 의 오류를 그대로 전한다"
killed && k=1 || k=0
assert_eq "$k" "0" "Hyprland 에 못 닿으면 셸을 죽이지 않는다"

# 기동 요청이 실패하면 성공으로 보고하지 않는다.
out=$(STUB_HYPR_FAIL=dispatch run_restart "$unlocked" 0 2>&1); code=$?
assert_eq "$code" "1" "dispatch 실패 → exit 1"
assert_contains "$out" "hyprctl stub failure" "dispatch 오류를 그대로 전한다"

# 옛 인스턴스가 끝내 안 죽으면 새로 띄우지 않는다(already running 거짓 성공 방지).
out=$(STUB_PGREP_ALIVE=1 run_restart "$unlocked" 0 2>&1); code=$?
assert_eq "$code" "1" "옛 인스턴스가 남으면 exit 1"
assert_contains "$out" "종료되지 않았다" "원인을 말한다"
launched && l=1 || l=0
assert_eq "$l" "0" "옛 인스턴스가 남으면 재기동을 요청하지 않는다"

# 새 셸이 ping 에 끝내 안 답하면 성공이라 하지 않는다.
cat > "$stub/omarchy-shell" <<'STUB'
#!/usr/bin/env bash
if [[ $1 == lock && $2 == status ]]; then printf '{"locked":false,"secure":false,"requested":false}'; exit 0; fi
exit 1
STUB
out=$(run_restart "" 0 2>&1); code=$?
assert_eq "$code" "1" "ping 무응답 → exit 1"
assert_contains "$out" "did not become ready" "준비되지 않았다고 말한다"

out=$("$W" --help 2>&1); code=$?
assert_eq "$code" "0" "--help → exit 0"
assert_contains "$out" "omarchy-restart-shell" "--help 가 사용법을 안내한다"
out=$("$W" --bogus 2>&1); code=$?
assert_eq "$code" "1" "알 수 없는 인자 → exit 1"

exit "$ASSERT_FAILURES"
