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
  --upstream-helpers "$REPO_ROOT/tests/data/upstream-helpers.txt" \
  --exceptions "$REPO_ROOT/tests/data/closure-exceptions.tsv" 2>&1)
code=$?
[[ -n $out ]] && printf '%s\n' "$out"
assert_eq "$code" "0" "클로저 위반 없음"

# 생성 표가 문서와 일치하는가. 손으로 고치면 여기서 빨개진다.
#
# test_update_pipeline.sh:587 는 COO_UPDATE_PIPELINE_NESTED=1 로 실제
# bin/update-upstream 을 돌려 그 후보의 기본 테스트 스위트(이 파일 포함)를
# 검증한다. 그 후보는 작은 disposable 픽스처 저장소로 핀을 옮긴 것이라
# tests/data/upstream-helpers.txt 가 그 자리에서 재생성되며(핀 이동 시
# bin/update-upstream 이 하는 일 그 자체), 스테이징되는 헬퍼 집합이 실제
# 저장소와 전혀 다르다. 이 문서(docs/RUNTIME_DEPENDENCIES.md)는 **실제
# 저장소의 핀**을 기준으로 커밋되므로, 그 픽스처가 만드는 표와 다른 것은
# 결함이 아니라 픽스처의 구조적 특성이다 — 클로저 위반 단언(위)은 계속
# 전체 실행된다, 이 표-동기화 단언만 건너뛴다.
if [[ ${COO_UPDATE_PIPELINE_NESTED:-0} == 1 ]]; then
  echo "skip: COO_UPDATE_PIPELINE_NESTED=1 픽스처 핀이라 실제 저장소 문서와 표가 구조적으로 다르다"
else
  generated=$(python3 "$REPO_ROOT/tests/runtime/closure_check.py" \
    --tree "$tree" --repo "$REPO_ROOT" \
    --map "$REPO_ROOT/tests/data/command-packages.tsv" \
    --upstream-helpers "$REPO_ROOT/tests/data/upstream-helpers.txt" \
    --exceptions "$REPO_ROOT/tests/data/closure-exceptions.tsv" --emit-table)
  embedded=$(awk '/CLOSURE_BEGIN/{f=1;next} /CLOSURE_END/{f=0} f' \
    "$REPO_ROOT/docs/RUNTIME_DEPENDENCIES.md")
  assert_eq "$(printf '%s\n' "$embedded" | sed '/^$/d')" \
            "$(printf '%s\n' "$generated" | sed '/^$/d')" \
            "RUNTIME_DEPENDENCIES.md 의 클로저 표가 최신이다"
fi

exit $((ASSERT_FAILURES > 0))
