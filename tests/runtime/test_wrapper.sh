#!/usr/bin/env bash
# 래퍼의 환경 구성과 실패 모드. 셸을 실제로 띄우지 않는다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/lib/runtime.sh"

W="$REPO_ROOT/overlay/bin/cachy-omarchy-shell"
assert_file_exists "$W" "래퍼 존재"
[[ -x $W ]] && x=0 || x=1
assert_eq "$x" "0" "래퍼 실행 가능"
[[ -x $W ]] || exit 1

out=$("$W" --help 2>&1); code=$?
assert_eq "$code" "0" "--help exit 0"
assert_contains "$out" "--run" "--help 가 --run 을 설명"
assert_contains "$out" "--ipc" "--help 가 --ipc 를 설명"

# OMARCHY_PATH 가 없는 곳을 가리키면 조용히 성공하지 말고 실패해야 한다.
out=$(COO_OMARCHY_PATH=/nonexistent "$W" --ipc shell ping 2>&1); code=$?
assert_eq "$code" "1" "잘못된 OMARCHY_PATH → exit 1"
assert_contains "$out" "shell.qml" "오류가 무엇이 없는지 말해준다"

# --path 는 해석 결과를 그대로 보여준다.
dest="$COO_TEST_SANDBOX/pkg"
if coo_extract_pkg "$dest" 2>/dev/null; then
  root=$(coo_upstream_root "$dest")
  assert_eq "$(COO_OMARCHY_PATH="$root" "$W" --path)" "$root" "--path 는 override 를 존중"
fi

# 알 수 없는 인자를 조용히 무시하지 않는다.
out=$("$W" --nonsense 2>&1); code=$?
assert_eq "$code" "1" "알 수 없는 인자 → exit 1"

exit "$ASSERT_FAILURES"
