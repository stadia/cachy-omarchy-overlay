#!/usr/bin/env bash
# cmd_run 의 정밀 멱등 가드: quickshell 이 이미 떠 있으면 --run 은 no-op(exit 0)
# 해야 하고, 실제 quickshell 을 exec 하지 않는다. 가드 패턴이 qs ipc 프로세스에
# false positive 를 내지 않는지도 검증(#5). 하니스가 REPO_ROOT/COO_TEST_SANDBOX 주입.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

W="$REPO_ROOT/overlay/bin/cachy-omarchy-shell"
assert_file_exists "$W" "래퍼 존재"

# 소스 정적 검증: socket-wait 루프는 제거됐고, Qt 핀은 유지됐다.
src=$(cat "$W")
assert_eq "$(grep -c 'systemctl --user show-environment' "$W")" "0" \
  "socket-wait 의 systemctl show-environment 루프 제거됨"
assert_contains "$src" 'QT_QPA_PLATFORM=wayland' "Qt wayland 핀 유지"
assert_contains "$src" 'pgrep -f' "멱등 가드 pgrep 존재"
assert_contains "$src" 'quickshell -n -p' "가드 패턴이 quickshell -n -p 전체 매칭(경로-only 아님)"

# 동작 검증: fake pgrep 가 match 를 보고하면 --run 은 require_tree 를 지난 뒤
# 멱등 가드에서 즉시 exit 0 한다(quickshell/systemd-cat 미도달).
sandbox=$COO_TEST_SANDBOX
fake_bin=$sandbox/fake-bin
mkdir -p "$fake_bin"
cat >"$fake_bin/pgrep" <<'EOF'
#!/usr/bin/env bash
[[ ${1:-} == -f ]] && exit 0   # pgrep -f <pat> → match
exit 1
EOF
chmod +x "$fake_bin/pgrep"
# fake quickshell: 도달하면 안 됨(표식 파일 생성).
cat >"$fake_bin/quickshell" <<'EOF'
#!/usr/bin/env bash
echo "SHOULD_NOT_HAVE_LAUNCHED $$" >"${COO_SHOULD_LAUNCH_LOG:-/dev/null}"
exit 0
EOF
chmod +x "$fake_bin/quickshell"
should=$sandbox/launched.log
: >"$should"
mkdir -p "$sandbox/upstream/shell"; printf '// x\n' >"$sandbox/upstream/shell/shell.qml"
# timeout 3s: red 상태(socket-wait 루프가 아직 남아있을 때) 20s 대기를 3s 에 끊어
# 빠르게 red 를 본다. green 상태에선 가드가 즉시 exit 0 한다.
out=$(PATH="$fake_bin:$PATH" COO_OMARCHY_PATH="$sandbox/upstream" \
  COO_SHOULD_LAUNCH_LOG="$should" timeout 3s "$W" --run 2>&1); code=$?
assert_eq "$code" "0" "이미 실행 중이면 --run 은 no-op exit 0"
assert_eq "$(cat "$should")" "" "이미 실행 중엔 quickshell 을 exec 하지 않는다"

exit "$ASSERT_FAILURES"