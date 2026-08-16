#!/usr/bin/env bash
# lib/runtime.sh 의 패키지 추출 헬퍼가 실제로 동작하는지 검증한다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/lib/runtime.sh"

assert_eq "$(coo_repo_root)" "$REPO_ROOT" "coo_repo_root"

artifact=$(coo_pkg_artifact); code=$?
if (( code != 0 )); then
  echo "skip: build/*.pkg.tar.zst 없음 — 먼저 makepkg 를 돌릴 것"
  exit 0
fi
assert_contains "$artifact" "cachy-omarchy-shell" "아티팩트 이름"

dest="$COO_TEST_SANDBOX/pkg"
coo_extract_pkg "$dest"
assert_eq "$?" "0" "추출 성공"

root=$(coo_upstream_root "$dest")
assert_file_exists "$root/shell/shell.qml" "shell.qml 존재"
assert_file_exists "$root/config/omarchy/shell.json" "기본 shell.json 존재"
assert_file_exists "$root/version" "version 존재"

# 아티팩트가 없을 때는 조용히 실패해야 한다.
out=$(COO_REPO_ROOT_OVERRIDE="$COO_TEST_SANDBOX/empty" coo_pkg_artifact 2>/dev/null); code=$?
assert_eq "$code" "1" "아티팩트 없음 → exit 1"
assert_eq "$out" "" "아티팩트 없음 → 빈 출력"

exit "$ASSERT_FAILURES"
