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

# build/ 는 롤백 이력으로 옛 버전을 남긴다. 현재 메타데이터가 가리키는 이름이
# 더 최근 mtime 의 다른 버전보다 이겨야 하고, 현재 이름이 없으면 옛 파일로
# 대신하지 않고 "아티팩트 없음" 으로 처리해야 한다 (bin/test-packages 와 같은 기준).
# 후보 스위트는 COO_BUILD_DIR 를 물려받으므로 기본 경로 검사에서는 비운다.
fake_root=$COO_TEST_SANDBOX/fake-root
mkdir -p "$fake_root/bin" "$fake_root/build" \
  "$fake_root/packages/cachy-omarchy-shell" "$fake_root/packages/cachy-omarchy-overlay"
cp "$REPO_ROOT/bin/package-names.sh" "$fake_root/bin/"
printf 'OMARCHY_VERSION=4.0.4\nOMARCHY_COMMIT=%s\n' "$(printf '0%.0s' {1..40})" >"$fake_root/upstream.lock"
printf 'pkgver=4.0.4\npkgrel=2\n' >"$fake_root/packages/cachy-omarchy-shell/PKGBUILD"
printf 'pkgver=1.0.2\npkgrel=1\n' >"$fake_root/packages/cachy-omarchy-overlay/PKGBUILD"
cur_shell=$fake_root/build/cachy-omarchy-shell-4.0.4-2-any.pkg.tar.zst
cur_overlay=$fake_root/build/cachy-omarchy-overlay-1.0.2-1-any.pkg.tar.zst
touch -d '2026-01-01' "$cur_shell" "$cur_overlay"
touch -d '2026-06-01' "$fake_root/build/cachy-omarchy-shell-4.0.3-1-any.pkg.tar.zst" \
  "$fake_root/build/cachy-omarchy-overlay-1.0.1-1-any.pkg.tar.zst"
out=$(COO_BUILD_DIR= COO_REPO_ROOT_OVERRIDE="$fake_root" coo_pkg_artifact 2>/dev/null)
assert_eq "$out" "$cur_shell" "current shell name wins over a newer non-current file"
out=$(COO_BUILD_DIR= COO_REPO_ROOT_OVERRIDE="$fake_root" coo_overlay_artifact 2>/dev/null)
assert_eq "$out" "$cur_overlay" "current overlay name wins over a newer non-current file"
other_build=$COO_TEST_SANDBOX/other-build
mkdir -p "$other_build"
cp -p "$cur_shell" "$other_build/"
out=$(COO_REPO_ROOT_OVERRIDE="$fake_root" COO_BUILD_DIR="$other_build" coo_pkg_artifact 2>/dev/null)
assert_eq "$out" "$other_build/${cur_shell##*/}" "COO_BUILD_DIR is honored"
rm -f "$cur_shell" "$cur_overlay"
out=$(COO_BUILD_DIR= COO_REPO_ROOT_OVERRIDE="$fake_root" coo_pkg_artifact 2>/dev/null); code=$?
assert_eq "$code:$out" "1:" "missing current shell artifact is absent, not an older one"
out=$(COO_BUILD_DIR= COO_REPO_ROOT_OVERRIDE="$fake_root" coo_overlay_artifact 2>/dev/null); code=$?
assert_eq "$code:$out" "1:" "missing current overlay artifact is absent, not an older one"
assert_eq "${OMARCHY_VERSION:-unset}" "unset" "artifact lookup does not leak lock variables"

exit "$ASSERT_FAILURES"
