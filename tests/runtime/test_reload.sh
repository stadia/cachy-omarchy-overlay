#!/usr/bin/env bash
# cachy-omarchy-reload 는 --restart 위의 얇은 앞단이다. 락 판단 로직은
# 이중화하지 않는다 — COO_SHELL_BIN 스텁이 --restart 인자로 불렸는지만
# 확인한다. 실제 셸은 절대 건드리지 않는다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

R="$REPO_ROOT/overlay/bin/cachy-omarchy-reload"
assert_file_exists "$R" "reload 명령 존재"
[[ -x $R ]] && x=0 || x=1
assert_eq "$x" "0" "reload 명령 실행 가능"
[[ -x $R ]] || exit 1

out=$("$R" --help 2>&1); code=$?
assert_eq "$code" "0" "--help exit 0"
assert_contains "$out" "reload" "--help 가 명령 이름을 언급"

fake="$COO_TEST_SANDBOX/reload"
stub="$fake/stub"
calls="$fake/calls.log"
mkdir -p "$stub"
: > "$calls"

cat > "$stub/cachy-omarchy-shell" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$COO_CALL_LOG"
exit 0
STUB
chmod +x "$stub/cachy-omarchy-shell"

out=$(COO_SHELL_BIN="$stub/cachy-omarchy-shell" COO_CALL_LOG="$calls" "$R" 2>&1); code=$?
assert_eq "$code" "0" "인자 없음 → exit 0"
assert_eq "$(cat "$calls")" "--restart" "COO_SHELL_BIN 이 --restart 로 불림"

# 알 수 없는 인자를 조용히 무시하지 않는다.
out=$("$R" --nonsense 2>&1); code=$?
assert_eq "$code" "1" "알 수 없는 인자 → exit 1"

exit "$ASSERT_FAILURES"
