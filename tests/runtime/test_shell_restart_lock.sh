#!/usr/bin/env bash
# --restart 는 세션이 잠긴 동안 셸을 죽이면 안 된다. 계약: 스키마가 온전한
# (locked/secure/requested 세 키가 다 있는) "unlocked" 응답만 진행, IPC
# 레벨 오류(대상 없음 등, exit 0 + 오류 문자열 — lock 서비스 부재로 간주)나
# IPC 자체 실패(타임아웃/셸 미기동)도 보존할 락이 없으므로 진행, 그 외
# (파싱 불가·키 누락 등) 전부 안전하게 거부한다.
# 실제 quickshell/hyprlock 은 전혀 건드리지 않는다 — qs/pgrep/kill/setsid
# 를 모두 스텁으로 교체한다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

W="$REPO_ROOT/overlay/bin/cachy-omarchy-shell"
assert_file_exists "$W" "래퍼 존재"

fake="$COO_TEST_SANDBOX/restart-lock"
stub="$fake/stub"
calls="$fake/calls.log"
mkdir -p "$fake/upstream/shell" "$stub"
: > "$fake/upstream/shell/shell.qml"
: > "$calls"

# 가짜 qs: "ipc ... call -- lock status" 호출에 $STUB_LOCK_JSON 을,
# exit code 는 $STUB_LOCK_EXIT(기본 0) 을 그대로 돌려준다.
cat > "$stub/qs" <<'STUB'
#!/usr/bin/env bash
printf 'qs %s\n' "$*" >> "$COO_CALL_LOG"
printf '%s' "${STUB_LOCK_JSON:-}"
exit "${STUB_LOCK_EXIT:-0}"
STUB
chmod +x "$stub/qs"

# pgrep: 아무 것도 못 찾은 척(재시작 경로가 kill 을 건드리지 않게) 하면서
# 호출 여부만 기록한다.
cat > "$stub/pgrep" <<'STUB'
#!/usr/bin/env bash
printf 'pgrep %s\n' "$*" >> "$COO_CALL_LOG"
exit 1
STUB
chmod +x "$stub/pgrep"

# kill: 호출됐다는 사실만 기록 — 거부 경로에서 절대 호출되면 안 된다.
cat > "$stub/kill" <<'STUB'
#!/usr/bin/env bash
printf 'kill %s\n' "$*" >> "$COO_CALL_LOG"
exit 0
STUB
chmod +x "$stub/kill"

# setsid: 실제 재기동 대신 호출만 기록한다 (진짜 프로세스를 절대 띄우지
# 않는다).
cat > "$stub/setsid" <<'STUB'
#!/usr/bin/env bash
printf 'setsid %s\n' "$*" >> "$COO_CALL_LOG"
exit 0
STUB
chmod +x "$stub/setsid"

run_restart() {
  : > "$calls"
  PATH="$stub:$PATH" \
    COO_OMARCHY_PATH="$fake/upstream" \
    COO_CALL_LOG="$calls" \
    STUB_LOCK_JSON="$1" \
    STUB_LOCK_EXIT="${2:-0}" \
    "$W" --restart
}

kill_called() { grep -q '^kill ' "$calls"; }
pgrep_called() { grep -q '^pgrep ' "$calls"; }

# cmd_restart 는 setsid 를 detach 로 백그라운드에 띄우고 바로 반환하므로,
# 로그 기록은 살짝 뒤늦게 온다. 무한 대기 없이 짧게 폴링한다.
setsid_called() {
  local n=0
  while (( n < 20 )); do
    grep -q '^setsid ' "$calls" && return 0
    sleep 0.05; n=$((n + 1))
  done
  return 1
}

# (a) secure:true (스키마 완전) → 거부
out=$(run_restart '{"locked":true,"secure":true,"requested":false}' 0 2>&1); code=$?
assert_eq "$code" "1" "secure:true → exit 1"
assert_contains "$out" "Refusing to restart the shell while the session is locked." "secure:true → 거부 메시지"
kill_called && k=1 || k=0
assert_eq "$k" "0" "secure:true → kill 미호출"
pgrep_called && p=1 || p=0
assert_eq "$p" "0" "secure:true → pgrep 도달 안 함"

# (b) requested:true (스키마 완전) → 거부
out=$(run_restart '{"locked":true,"secure":false,"requested":true}' 0 2>&1); code=$?
assert_eq "$code" "1" "requested:true → exit 1"
assert_contains "$out" "Refusing to restart the shell while the session is locked." "requested:true → 거부 메시지"
kill_called && k=1 || k=0
assert_eq "$k" "0" "requested:true → kill 미호출"
pgrep_called && p=1 || p=0
assert_eq "$p" "0" "requested:true → pgrep 도달 안 함"

# (c) locked:false, secure:false, requested:false (스키마 완전) → 진행 (setsid 호출)
out=$(run_restart '{"locked":false,"secure":false,"requested":false}' 0 2>&1); code=$?
assert_eq "$code" "0" "잠기지 않음 → exit 0"
setsid_called && s=1 || s=0
assert_eq "$s" "1" "잠기지 않음 → 재기동(setsid) 진행"

# (d) IPC 실패(셸 미실행) → 진행
out=$(run_restart '' 1 2>&1); code=$?
assert_eq "$code" "0" "IPC 실패 → exit 0 (보존할 락 없음)"
setsid_called && s=1 || s=0
assert_eq "$s" "1" "IPC 실패 → 재기동(setsid) 진행"

# (e) 응답은 왔는데 파싱 불가(쓰레기 JSON) → 거부
out=$(run_restart 'not json' 0 2>&1); code=$?
assert_eq "$code" "1" "파싱 불가 → exit 1"
assert_contains "$out" "Refusing to restart the shell while the session is locked." "파싱 불가 → 거부 메시지"
kill_called && k=1 || k=0
assert_eq "$k" "0" "파싱 불가 → kill 미호출"
pgrep_called && p=1 || p=0
assert_eq "$p" "0" "파싱 불가 → pgrep 도달 안 함"

# (f) IPC 레벨 오류(exit 0 + "Target not found.") → lock 서비스 부재로 간주,
# 보존할 락이 없으므로 진행한다 (lock 플러그인 비활성/로딩 중인 셸에서도
# 재시작이 영원히 막히지 않아야 한다).
out=$(run_restart 'Target not found.' 0 2>&1); code=$?
assert_eq "$code" "0" "IPC 오류 문자열 → exit 0 (lock 서비스 부재로 간주, 진행)"
setsid_called && s=1 || s=0
assert_eq "$s" "1" "IPC 오류 문자열 → 재기동(setsid) 진행"

# (g) 응답은 파싱되지만 키가 없음({}) → 스키마 불완전, 거부.
# .secure/.requested 두 항만 보던 이전 판정식은 {} 를 "false or false" =
# false 로 읽어 실수로 진행시켰다(fail-open) — 이제는 세 키가 모두 있어야
# 판정하고, 없으면 거부한다.
out=$(run_restart '{}' 0 2>&1); code=$?
assert_eq "$code" "1" "{} → exit 1 (스키마 불완전 → 거부)"
assert_contains "$out" "Refusing to restart the shell while the session is locked." "{} → 거부 메시지"
kill_called && k=1 || k=0
assert_eq "$k" "0" "{} → kill 미호출"
pgrep_called && p=1 || p=0
assert_eq "$p" "0" "{} → pgrep 도달 안 함"

exit "$ASSERT_FAILURES"
