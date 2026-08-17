#!/usr/bin/env bash
# 셸 프로세스 PATH 에 compat shim 과 업스트림 bin 이 이 순서로 붙는지 검증한다.
# 위젯은 helper 를 bare name 으로 부른다(plugins/panels/*/Panel.qml) — PATH 에
# 없으면 스테이징해도 무효다. SPEC 44/45: 셸 프로세스 한정, 사용자 PATH 불변.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

WRAPPER="$REPO_ROOT/overlay/bin/cachy-omarchy-shell"
assert_file_exists "$WRAPPER" "래퍼 존재"

# 가짜 트리: quickshell 을 스텁으로 두고 cmd_run 이 조립한 PATH 를 받아쓴다.
fake="$COO_TEST_SANDBOX/fakeroot"
mkdir -p "$fake/upstream/shell" "$fake/upstream/bin" "$fake/compat/bin" "$fake/stub"
: > "$fake/upstream/shell/shell.qml"

cat > "$fake/stub/quickshell" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$PATH"
STUB
chmod +x "$fake/stub/quickshell"
cat > "$fake/stub/systemd-cat" <<'STUB'
#!/usr/bin/env bash
while [[ ${1:-} != "--" && $# -gt 0 ]]; do shift; done
shift || true
exec "$@"
STUB
chmod +x "$fake/stub/systemd-cat"

run_wrapper() {
  PATH="$fake/stub:$PATH" \
    COO_OMARCHY_PATH="$fake/upstream" \
    COO_COMPAT_BIN="$1" \
    "$WRAPPER" --run 2>/dev/null
}

out=$(run_wrapper "$fake/compat/bin")
case "$out" in
  "$fake/compat/bin:$fake/upstream/bin:"*) ok=0 ;;
  *) ok=1 ;;
esac
assert_eq "$ok" "0" "PATH 선두 = compat/bin:\$OMARCHY_PATH/bin"

# 원래 PATH 가 뒤에 온전히 남는다 — 교체가 아니라 앞에 붙이기다.
case "$out" in
  *":$fake/stub:"*) ok=0 ;;
  *) ok=1 ;;
esac
assert_eq "$ok" "0" "원래 PATH 가 뒤에 보존된다"

# 없는 디렉터리는 PATH 에 넣지 않는다 (compat 미설치 트리에서 죽은 항목 금지).
out_nocompat=$(run_wrapper "$fake/nonexistent/bin")
case "$out_nocompat" in
  "$fake/upstream/bin:"*) ok=0 ;;
  *) ok=1 ;;
esac
assert_eq "$ok" "0" "compat 디렉터리가 없으면 PATH 선두는 \$OMARCHY_PATH/bin"

# 사용자 PATH 오염 금지: 래퍼를 부른 셸의 PATH 는 그대로다.
assert_eq "${PATH#"$fake/upstream/bin"}" "$PATH" "호출자 PATH 는 변하지 않는다"

exit "$ASSERT_FAILURES"
