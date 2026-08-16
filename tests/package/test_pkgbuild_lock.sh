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

[[ $OMARCHY_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && version_ok=0 || version_ok=1
assert_eq "$version_ok" "0" "lock version is stable semver"
[[ $OMARCHY_COMMIT =~ ^[0-9a-f]{40}$ ]] && commit_ok=0 || commit_ok=1
assert_eq "$commit_ok" "0" "lock commit is a full SHA"

pkgver=$(grep -E '^pkgver=' "$pkgbuild" | head -1 | cut -d= -f2 | tr -d "'" | tr -d '"')
commit=$(grep -E '^_commit=' "$pkgbuild" | head -1 | cut -d= -f2 | tr -d "'" | tr -d '"')
pkgname=$(grep -E '^pkgname=' "$pkgbuild" | head -1 | cut -d= -f2 | tr -d "'" | tr -d '"')

assert_eq "$pkgname" "cachy-omarchy-shell" "P-name"
assert_eq "$pkgver" "$OMARCHY_VERSION" "P08 pkgver matches lock"
assert_eq "$commit" "$OMARCHY_COMMIT" "P07 commit matches lock"
[[ $ASSERT_FAILURES -eq 0 ]]
