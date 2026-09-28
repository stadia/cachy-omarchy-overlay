#!/usr/bin/env bash
# omarchy-restart-shell compat shim 이 cachy-omarchy-shell --restart 로 위임만
# 하는지 검증한다. 락 판단/kill 로직은 이중화하지 않으므로 여기서 다시 재지
# 않는다 — COO_SHELL_BIN 스텁이 --restart 로 불렸는지만 확인한다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

SHIM="$REPO_ROOT/overlay/compat/bin/omarchy-restart-shell"
assert_file_exists "$SHIM" "shim 존재"
[[ -f $SHIM ]] || exit 1
[[ -x $SHIM ]] && x=0 || x=1
assert_eq "$x" "0" "실행 가능"

# 업스트림 원본이 부르는 미스테이징 헬퍼를 실제로 실행하지 않는다.
# 주석은 사유 설명상 그 이름을 언급할 수 있으므로, 실행문(비주석 행)만 본다.
code_lines=$(grep -v '^[[:space:]]*#' "$SHIM")
for missing in omarchy-hyprland-session-locked omarchy-launch-shell \
               omarchy-system-sleep-lock; do
  case "$code_lines" in
    *"$missing"*) hit=1 ;;
    *) hit=0 ;;
  esac
  assert_eq "$hit" "0" "미스테이징 헬퍼 $missing 를 부르지 않는다"
done
case "$code_lines" in
  *"quickshell"*|*"kill "*) k=1 ;;
  *) k=0 ;;
esac
assert_eq "$k" "0" "shim 자체는 kill 을 하지 않는다"
# 중간 별칭(cachy-omarchy-reload)을 거치지 않는다. 호스트에 설치된 옛 별칭이
# 있으면 동작 단언만으로는 이것을 구분하지 못한다.
case "$code_lines" in
  *"cachy-omarchy-reload"*|*"COO_RELOAD_BIN"*) via_alias=1 ;;
  *) via_alias=0 ;;
esac
assert_eq "$via_alias" "0" "reload 별칭을 거치지 않고 --restart 로 직접 위임한다"

fake="$COO_TEST_SANDBOX/restart-shell"
stub="$fake/stub"
calls="$fake/calls.log"
mkdir -p "$stub"
: > "$calls"

cat > "$stub/cachy-omarchy-shell" <<'STUB'
#!/usr/bin/env bash
printf 'called:%s\n' "$*" >> "$COO_CALL_LOG"
exit "${STUB_EXIT:-0}"
STUB
chmod +x "$stub/cachy-omarchy-shell"

out=$(COO_SHELL_BIN="$stub/cachy-omarchy-shell" COO_CALL_LOG="$calls" "$SHIM" 2>&1)
code=$?
assert_eq "$code" "0" "위임 성공 시 exit 0"
assert_eq "$(cat "$calls")" "called:--restart" "cachy-omarchy-shell --restart 를 호출"

# 위임 대상이 실패하면 그 exit code 를 그대로 전달한다(집어삼키지 않는다).
STUB_EXIT=1 COO_SHELL_BIN="$stub/cachy-omarchy-shell" COO_CALL_LOG="$calls" "$SHIM" >/dev/null 2>&1
code=$?
assert_eq "$code" "1" "위임 대상 실패를 그대로 전달"

exit "$ASSERT_FAILURES"
