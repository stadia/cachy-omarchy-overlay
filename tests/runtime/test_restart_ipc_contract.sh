#!/usr/bin/env bash
# --restart 의 락 판정은 업스트림 omarchy-shell 의 오류 문구에 기대고 있다:
# 진행 허용 목록("is not running", "Target not found.")과 거부 사유("is not
# responding", "is not ready")다. 핀을 올리다 업스트림이 문구를 바꾸면 판정이
# 조용히 거부 쪽(안전하지만 재시작 불능)이나 더 나쁘게는 진행 쪽으로 어긋나므로,
# 스테이징된 소스와 우리 래퍼가 같은 문구를 쓰는지 고정한다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/lib/runtime.sh"

tree="${COO_TEST_SANDBOX:?}/ipc-contract-tree"
if ! coo_extract_pkg "$tree"; then
  printf 'FAIL: build/ 에 cachy-omarchy-shell 아티팩트가 없다 — bin/build-packages 를 먼저 돌린다\n'
  exit 1
fi
client="$(coo_upstream_root "$tree")/bin/omarchy-shell"
wrapper="$REPO_ROOT/overlay/compat/bin/omarchy-restart-shell"
assert_file_exists "$client" "스테이징된 업스트림 omarchy-shell"

for phrase in "omarchy-shell is not running" "omarchy-shell is not responding" \
              "omarchy-shell is not ready" "Target not found."; do
  assert_contains "$(<"$client")" "$phrase" "업스트림 omarchy-shell 이 \"$phrase\" 를 낸다"
done
# 래퍼가 허용 목록으로 쓰는 두 문구는 업스트림 문구의 부분 문자열이어야 한다.
assert_contains "$(<"$wrapper")" '*"is not running"*' "래퍼의 진행 허용: 셸 미실행"
assert_contains "$(<"$wrapper")" '*"Target not found."*' "래퍼의 진행 허용: lock 플러그인 부재"
# 래퍼는 무응답·기동 중을 진행 목록에 넣지 않는다.
[[ $(<"$wrapper") == *'*"is not responding"*) ;;'* || $(<"$wrapper") == *'*"is not ready"*) ;;'* ]] && leak=1 || leak=0
assert_eq "$leak" "0" "무응답·기동 중은 진행 허용 목록에 없다"

exit "$ASSERT_FAILURES"
