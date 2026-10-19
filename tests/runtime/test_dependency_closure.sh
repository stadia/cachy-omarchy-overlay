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

# 업스트림 헬퍼 목록은 체크인하지 않고 핀 커밋의 트리에서 그때그때 뽑는다.
helpers="$COO_TEST_SANDBOX/upstream-helpers.txt"
if ! COO_REPO_ROOT="$REPO_ROOT" "$REPO_ROOT/bin/list-upstream-helpers" >"$helpers"; then
  printf 'FAIL: 핀 커밋의 업스트림 bin/ 목록을 읽지 못했다 (build/omarchy 클론이 필요하다)\n'
  exit 1
fi

out=$(python3 "$REPO_ROOT/tests/runtime/closure_check.py" \
  --tree "$tree" --repo "$REPO_ROOT" \
  --map "$REPO_ROOT/tests/data/command-packages.tsv" \
  --upstream-helpers "$helpers" \
  --exceptions "$REPO_ROOT/tests/data/closure-exceptions.tsv" 2>&1)
code=$?
[[ -n $out ]] && printf '%s\n' "$out"
assert_eq "$code" "0" "클로저 위반 없음"

# 생성 표가 문서와 일치하는가. 손으로 고치면 여기서 빨개진다. 핀을 옮길 때는
# bin/update-upstream 이 bin/sync-closure-table 로 표를 다시 쓴다.
generated=$(python3 "$REPO_ROOT/tests/runtime/closure_check.py" \
  --tree "$tree" --repo "$REPO_ROOT" \
  --map "$REPO_ROOT/tests/data/command-packages.tsv" \
  --upstream-helpers "$helpers" \
  --exceptions "$REPO_ROOT/tests/data/closure-exceptions.tsv" --emit-table)
embedded=$(awk '/CLOSURE_BEGIN/{f=1;next} /CLOSURE_END/{f=0} f' \
  "$REPO_ROOT/docs/RUNTIME_DEPENDENCIES.md")
assert_eq "$(printf '%s\n' "$embedded" | sed '/^$/d')" \
          "$(printf '%s\n' "$generated" | sed '/^$/d')" \
          "RUNTIME_DEPENDENCIES.md 의 클로저 표가 최신이다"

exit $((ASSERT_FAILURES > 0))
