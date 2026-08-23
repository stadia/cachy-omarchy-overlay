#!/usr/bin/env bash
# omarchy-restart-shell compat shim 이 cachy-omarchy-reload 로 위임만 하는지
# 검증한다. 락 판단/kill 로직은 이중화하지 않으므로 여기서 다시 재지 않는다
# — COO_RELOAD_BIN 스텁이 인자 없이 불렸는지만 확인한다.
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

fake="$COO_TEST_SANDBOX/restart-shell"
stub="$fake/stub"
calls="$fake/calls.log"
mkdir -p "$stub"
: > "$calls"

cat > "$stub/cachy-omarchy-reload" <<'STUB'
#!/usr/bin/env bash
printf 'called:%s\n' "$*" >> "$COO_CALL_LOG"
exit 0
STUB
chmod +x "$stub/cachy-omarchy-reload"

out=$(COO_RELOAD_BIN="$stub/cachy-omarchy-reload" COO_CALL_LOG="$calls" "$SHIM" 2>&1)
code=$?
assert_eq "$code" "0" "위임 성공 시 exit 0"
assert_eq "$(cat "$calls")" "called:" "인자 없이 cachy-omarchy-reload 를 호출"

# 위임 대상이 실패하면 그 exit code 를 그대로 전달한다(집어삼키지 않는다).
cat > "$stub/cachy-omarchy-reload" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
chmod +x "$stub/cachy-omarchy-reload"
COO_RELOAD_BIN="$stub/cachy-omarchy-reload" "$SHIM" >/dev/null 2>&1
code=$?
assert_eq "$code" "1" "위임 대상 실패를 그대로 전달"

exit "$ASSERT_FAILURES"
