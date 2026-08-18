#!/usr/bin/env bash
# 셸 래퍼는 PATH 를 조작하지 않는다 (SPEC §45 개정). 업스트림 helper 는
# /usr/bin/omarchy-* 심링크로 노출되고, OMARCHY_PATH 는 uwsm 세션 환경이
# 공급한다. 래퍼가 다시 PATH 를 만지면 두 개의 진실이 생긴다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

WRAPPER="$REPO_ROOT/overlay/bin/cachy-omarchy-shell"
assert_file_exists "$WRAPPER" "래퍼 존재"

fake="$COO_TEST_SANDBOX/fakeroot"
mkdir -p "$fake/upstream/shell" "$fake/upstream/bin" "$fake/stub"
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

caller_path="$fake/stub:$PATH"
out=$(PATH="$caller_path" COO_OMARCHY_PATH="$fake/upstream" "$WRAPPER" --run 2>/dev/null)

assert_eq "$out" "$caller_path" "셸 프로세스 PATH = 호출자 PATH (조작 없음)"

case "$out" in
  *"$fake/upstream/bin"*) leaked=1 ;;
  *) leaked=0 ;;
esac
assert_eq "$leaked" "0" "\$OMARCHY_PATH/bin 을 PATH 에 붙이지 않는다"

# 소스에 PATH 조립이 남아있지 않은지도 직접 본다 — 주석만 남기고 코드가
# 되살아나는 회귀를 잡는다.
grep -qE '^[^#]*PATH=.*(COMPAT_BIN|OMARCHY_PATH/bin)' "$WRAPPER" && rev=1 || rev=0
assert_eq "$rev" "0" "래퍼 소스에 PATH prepend 코드가 없다"

exit "$ASSERT_FAILURES"
