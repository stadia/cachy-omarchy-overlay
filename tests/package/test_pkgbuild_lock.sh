#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/assert.sh"

lock=$REPO_ROOT/upstream.lock
pkgbuild=$REPO_ROOT/packages/cachy-omarchy-shell/PKGBUILD
assert_file_exists "$lock" "upstream.lock"
assert_file_exists "$pkgbuild" "PKGBUILD"

# shellcheck disable=SC1090
set -a
source "$lock"
set +a

assert_eq "$OMARCHY_VERSION" "4.0.0" "lock version"
assert_eq "$OMARCHY_COMMIT" "f0020448ca87329199de7cb12f2015ebc4a3e5e7" "lock commit"

pkgver=$(grep -E '^pkgver=' "$pkgbuild" | head -1 | cut -d= -f2 | tr -d "'" | tr -d '"')
commit=$(grep -E '^_commit=' "$pkgbuild" | head -1 | cut -d= -f2 | tr -d "'" | tr -d '"')
pkgname=$(grep -E '^pkgname=' "$pkgbuild" | head -1 | cut -d= -f2 | tr -d "'" | tr -d '"')

assert_eq "$pkgname" "cachy-omarchy-shell" "P-name"
assert_eq "$pkgver" "$OMARCHY_VERSION" "P08 pkgver matches lock"
assert_eq "$commit" "$OMARCHY_COMMIT" "P07 commit matches lock"
[[ $ASSERT_FAILURES -eq 0 ]]
