#!/usr/bin/env bash
# resolve lane 의 존재 이유는 "--nodeps 없이 의존을 해석시킨다" 하나다.
# 언젠가 누군가 CI 를 초록으로 만들려고 --nodeps 를 넣으면 이 lane 은 기존
# clean build 와 똑같아지고 아무것도 증명하지 않게 된다. 여기서 막는다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

script="$REPO_ROOT/bin/ci-resolve-install"
assert_file_exists "$script" "resolve 스크립트가 있다"
[[ -x $script ]] && printf 'ok:   실행 가능하다\n' \
  || { printf 'FAIL: 실행 가능하다\n'; ASSERT_FAILURES=$((ASSERT_FAILURES + 1)); }

body=$(cat "$script" 2>/dev/null)
nodeps=$(printf '%s\n' "$body" | grep -c -- '--nodeps' || true)
assert_eq "$nodeps" "0" "의존 해석 lane 은 --nodeps 를 쓰지 않는다"

assert_contains "$body" "repo-add" "로컬 pacman 저장소를 만든다"
assert_contains "$body" "cachy-omarchy-overlay" "overlay 만 설치해 패키지 간 의존을 해석시킨다"
assert_contains "$body" "omarchy-settings" "공식 패키지 부재를 게이트로 검사한다"
assert_contains "$body" "게이트 B conflicts" "omarchy conflicts 결과를 별도로 기록한다"
assert_contains "$body" "게이트 B 기준선" "omarchy-settings 기준선 부재를 별도로 기록한다"
assert_contains "$body" "closure_check.py" "게이트 C: 폐쇄 스캐너를 실설치 트리에 돌린다"

exit "$ASSERT_FAILURES"
