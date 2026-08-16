#!/usr/bin/env bash
# M6 U01/U06/U07 foundation: fake tools only, never network or pacman.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/assert.sh"

root=$COO_TEST_SANDBOX/repo
mkdir -p "$root/packages" "$root/bin"
cp -a "$REPO_ROOT/upstream.lock" "$root/"
cp -a "$REPO_ROOT/packages/cachy-omarchy-shell" "$root/packages/"
cp -a "$REPO_ROOT/packages/cachy-omarchy-overlay" "$root/packages/"
cp -a "$REPO_ROOT/bin/check-upstream" "$REPO_ROOT/bin/build-packages" "$root/bin/"
chmod +x "$root/bin"/*
fake=$COO_TEST_SANDBOX/fake
mkdir -p "$fake"
log=$COO_TEST_SANDBOX/tools.log

cat >"$fake/git" <<'EOF'
#!/usr/bin/env bash
# v4.0.1 is annotated: direct ref is tag object, peeled ref is commit.
if [[ ${COO_FAKE_LIGHTWEIGHT:-0} == 1 ]]; then
  printf '%s\n' 'f0020448ca87329199de7cb12f2015ebc4a3e5e7 refs/tags/v4.0.0'
  printf '%s\n' '4444444444444444444444444444444444444444 refs/tags/v4.0.1'
  exit 0
fi
printf '%s\n' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa refs/tags/v4.0.0'
printf '%s\n' 'f0020448ca87329199de7cb12f2015ebc4a3e5e7 refs/tags/v4.0.0^{}'
printf '%s\n' '1111111111111111111111111111111111111111 refs/tags/v4.0.1'
printf '%s\n' '2222222222222222222222222222222222222222 refs/tags/v4.0.1^{}'
printf '%s\n' '3333333333333333333333333333333333333333 refs/tags/v3.9.9'
EOF
cat >"$fake/makepkg" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$(basename "$PWD")" >>"$COO_TOOL_LOG"
[[ ${COO_FAKE_BUILD_FAIL:-0} != 1 ]] || exit 7
mkdir -p "$PKGDEST"
if [[ $PWD == *cachy-omarchy-shell ]]; then
  ver=$(grep -m1 '^pkgver=' PKGBUILD | cut -d= -f2 | tr -d "'\"")
  rel=$(grep -m1 '^pkgrel=' PKGBUILD | cut -d= -f2 | tr -d "'\"")
  : >"$PKGDEST/cachy-omarchy-shell-${ver}-${rel}-any.pkg.tar.zst"
else
  ver=$(grep -m1 '^pkgver=' PKGBUILD | cut -d= -f2 | tr -d "'\"")
  rel=$(grep -m1 '^pkgrel=' PKGBUILD | cut -d= -f2 | tr -d "'\"")
  : >"$PKGDEST/cachy-omarchy-overlay-${ver}-${rel}-any.pkg.tar.zst"
fi
[[ ${COO_FAKE_EXTRA:-0} != 1 ]] || : >"$PKGDEST/extra.pkg.tar.zst"
EOF
cat >"$fake/bsdtar" <<'EOF'
#!/usr/bin/env bash
if [[ ${COO_FAKE_AUDIT_FAIL:-0} == 1 ]]; then echo etc/os-release; else echo usr/share/cachy-omarchy/ok; fi
EOF
cat >"$fake/sha256sum" <<'EOF'
#!/usr/bin/env bash
[[ ${COO_FAKE_SHA_FAIL:-0} != 1 ]] || exit 9
/usr/bin/sha256sum "$@"
EOF
cat >"$fake/install" <<'EOF'
#!/usr/bin/env bash
[[ ${COO_FAKE_COPY_FAIL:-0} != 1 ]] || exit 8
/usr/bin/install "$@"
EOF
chmod +x "$fake"/*

# U01: discovery is read-only and does not invoke build tools.
lock_before=$(sha256sum "$root/upstream.lock")
pkg_before=$(sha256sum "$root/packages/cachy-omarchy-shell/PKGBUILD")
out=$(COO_REPO_ROOT="$root" COO_GIT_BIN="$fake/git" "$root/bin/check-upstream" 2>&1); code=$?
assert_eq "$code" "0" "U01 no-update exits cleanly"
assert_contains "$out" "update available" "U01 reports available update"
assert_contains "$out" "2222222222222222222222222222222222222222" "U01 uses annotated tag peeled commit"
assert_eq "$(sha256sum "$root/upstream.lock")" "$lock_before" "U01 lock is unchanged"
assert_eq "$(sha256sum "$root/packages/cachy-omarchy-shell/PKGBUILD")" "$pkg_before" "U01 PKGBUILD is unchanged"
out=$(COO_FAKE_LIGHTWEIGHT=1 COO_REPO_ROOT="$root" COO_GIT_BIN="$fake/git" "$root/bin/check-upstream" 2>&1); code=$?
assert_eq "$code" "0" "lightweight tag check exits cleanly"
assert_contains "$out" "4444444444444444444444444444444444444444" "lightweight tag uses direct commit"
[[ -e $log ]] && invoked=1 || invoked=0
assert_eq "$invoked" "0" "U01 does not build or install"

# Successful pair build writes both checksums and preserves shell→overlay order.
COO_TOOL_LOG="$log" COO_REPO_ROOT="$root" COO_BUILD_DIR="$COO_TEST_SANDBOX/build" COO_STATE_DIR="$COO_TEST_SANDBOX/state" COO_MAKEPKG_BIN="$fake/makepkg" COO_BSDTAR_BIN="$fake/bsdtar" COO_SHA256_BIN="$fake/sha256sum" "$root/bin/build-packages" >/dev/null
assert_eq "$(tr '\n' ' ' <"$log")" "cachy-omarchy-shell cachy-omarchy-overlay " "build order is shell then overlay"
manifest=$COO_TEST_SANDBOX/state/validated-build.manifest
assert_file_exists "$manifest" "validated manifest exists"
manifest_src=$(cat "$manifest")
assert_contains "$manifest_src" "OMARCHY_COMMIT=f0020448ca87329199de7cb12f2015ebc4a3e5e7" "manifest binds commit"
assert_contains "$manifest_src" "cachy-omarchy-overlay-0.1.0-1-any.pkg.tar.zst" "manifest binds overlay artifact"

# U06: failed build publishes neither artifacts nor a manifest.
rm -f "$log"
code=0
out=$(COO_TOOL_LOG="$log" COO_FAKE_BUILD_FAIL=1 COO_REPO_ROOT="$root" COO_BUILD_DIR="$COO_TEST_SANDBOX/fail-build" COO_STATE_DIR="$COO_TEST_SANDBOX/fail-state" COO_MAKEPKG_BIN="$fake/makepkg" COO_BSDTAR_BIN="$fake/bsdtar" "$root/bin/build-packages" 2>&1) || code=$?
assert_eq "$code" "7" "U06 build failure blocks publication"
[[ -e $COO_TEST_SANDBOX/fail-state/validated-build.manifest ]] && published=1 || published=0
assert_eq "$published" "0" "U06 no manifest after failure"

# U07: audit failure publishes neither artifacts nor manifest.
code=0
out=$(COO_FAKE_AUDIT_FAIL=1 COO_REPO_ROOT="$root" COO_BUILD_DIR="$COO_TEST_SANDBOX/audit-build" COO_STATE_DIR="$COO_TEST_SANDBOX/audit-state" COO_MAKEPKG_BIN="$fake/makepkg" COO_BSDTAR_BIN="$fake/bsdtar" "$root/bin/build-packages" 2>&1) || code=$?
assert_eq "$code" "1" "U07 audit failure blocks publication"
[[ -e $COO_TEST_SANDBOX/audit-state/validated-build.manifest ]] && published=1 || published=0
assert_eq "$published" "0" "U07 no manifest after audit failure"

# Transaction regression: checksum/copy failure leaves an old validated pair untouched.
trans_build=$COO_TEST_SANDBOX/transaction-build
trans_state=$COO_TEST_SANDBOX/transaction-state
mkdir -p "$trans_build" "$trans_state"
printf 'old-shell' >"$trans_build/cachy-omarchy-shell-3.9.9-1-any.pkg.tar.zst"
printf 'old-overlay' >"$trans_build/cachy-omarchy-overlay-0.0.9-1-any.pkg.tar.zst"
printf 'old-manifest\n' >"$trans_state/validated-build.manifest"
old_sum=$(sha256sum "$trans_build"/* "$trans_state/validated-build.manifest")
code=0
out=$(COO_TOOL_LOG="$log" COO_FAKE_SHA_FAIL=1 COO_REPO_ROOT="$root" COO_BUILD_DIR="$trans_build" COO_STATE_DIR="$trans_state" COO_MAKEPKG_BIN="$fake/makepkg" COO_BSDTAR_BIN="$fake/bsdtar" COO_SHA256_BIN="$fake/sha256sum" COO_INSTALL_BIN="$fake/install" "$root/bin/build-packages" 2>&1) || code=$?
assert_eq "$code" "9" "checksum failure blocks publication"
assert_eq "$(sha256sum "$trans_build"/* "$trans_state/validated-build.manifest")" "$old_sum" "checksum failure preserves old pair and manifest"
code=0
out=$(COO_TOOL_LOG="$log" COO_FAKE_COPY_FAIL=1 COO_REPO_ROOT="$root" COO_BUILD_DIR="$trans_build" COO_STATE_DIR="$trans_state" COO_MAKEPKG_BIN="$fake/makepkg" COO_BSDTAR_BIN="$fake/bsdtar" COO_SHA256_BIN="$fake/sha256sum" COO_INSTALL_BIN="$fake/install" "$root/bin/build-packages" 2>&1) || code=$?
assert_eq "$code" "8" "copy failure blocks publication"
assert_eq "$(sha256sum "$trans_build"/* "$trans_state/validated-build.manifest")" "$old_sum" "copy failure preserves old pair and manifest"
code=0
out=$(COO_FAKE_EXTRA=1 COO_REPO_ROOT="$root" COO_BUILD_DIR="$COO_TEST_SANDBOX/ambiguous-build" COO_STATE_DIR="$COO_TEST_SANDBOX/ambiguous-state" COO_MAKEPKG_BIN="$fake/makepkg" COO_BSDTAR_BIN="$fake/bsdtar" "$root/bin/build-packages" 2>&1) || code=$?
assert_eq "$code" "1" "ambiguous artifacts are rejected"
[[ -e $COO_TEST_SANDBOX/ambiguous-state/validated-build.manifest ]] && published=1 || published=0
assert_eq "$published" "0" "ambiguous artifacts publish no manifest"

exit "$ASSERT_FAILURES"
