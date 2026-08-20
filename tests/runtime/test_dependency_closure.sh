#!/usr/bin/env bash
# v0.9: helper -> external command -> Arch package -> depends 등급 클로저.
#
# 이 테스트는 설치 트리를 요구한다. 아티팩트가 없으면 note 를 찍고 통과하지
# 않는다 — 라이브 세션이 아니라 빌드만 요구하므로, 빌드를 안 돌린 것은
# 스킵할 사유가 아니다. 조용히 통과하는 것이 이 저장소에서 가장 위험한
# 실패 모드다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/lib/runtime.sh"

tree="${COO_TEST_SANDBOX:?}/closure-tree"
if ! coo_extract_pkg "$tree"; then
  printf 'FAIL: build/ 에 cachy-omarchy-shell 아티팩트가 없다 — bin/build-packages 를 먼저 돌린다\n'
  exit 1
fi
if ! coo_extract_overlay "$tree/overlay"; then
  printf 'FAIL: build/ 에 cachy-omarchy-overlay 아티팩트가 없다 — bin/build-packages 를 먼저 돌린다\n'
  exit 1
fi

out=$(python3 "$REPO_ROOT/tests/runtime/closure_check.py" \
  --tree "$tree" --repo "$REPO_ROOT" \
  --map "$REPO_ROOT/tests/data/command-packages.tsv" \
  --exceptions "$REPO_ROOT/tests/data/closure-exceptions.tsv" 2>&1)
code=$?
[[ -n $out ]] && printf '%s\n' "$out"
assert_eq "$code" "0" "클로저 위반 없음"

exit $((ASSERT_FAILURES > 0))
