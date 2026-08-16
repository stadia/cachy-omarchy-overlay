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
printf '%s\n' 'f0020448ca87329199de7cb12f2015ebc4a3e5e7 refs/tags/v4.0.0'
EOF
cat >"$fake/makepkg" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$(basename "$PWD")" >>"$COO_TOOL_LOG"
[[ ${COO_FAKE_BUILD_FAIL:-0} != 1 ]] || exit 7
mkdir -p "$PKGDEST"
if [[ $PWD == *cachy-omarchy-shell ]]; then
  : >"$PKGDEST/cachy-omarchy-shell-4.0.0-1-any.pkg.tar.zst"
else
  : >"$PKGDEST/cachy-omarchy-overlay-0.1.0-1-any.pkg.tar.zst"
fi
EOF
cat >"$fake/bsdtar" <<'EOF'
#!/usr/bin/env bash
if [[ ${COO_FAKE_AUDIT_FAIL:-0} == 1 ]]; then echo etc/os-release; else echo usr/share/cachy-omarchy/ok; fi
EOF
cat >"$fake/sha256sum" <<'EOF'
#!/usr/bin/env bash
/usr/bin/sha256sum "$@"
EOF
chmod +x "$fake"/*

# U01: discovery is read-only and does not invoke build tools.
lock_before=$(sha256sum "$root/upstream.lock")
pkg_before=$(sha256sum "$root/packages/cachy-omarchy-shell/PKGBUILD")
out=$(COO_REPO_ROOT="$root" COO_GIT_BIN="$fake/git" "$root/bin/check-upstream" 2>&1); code=$?
assert_eq "$code" "0" "U01 no-update exits cleanly"
assert_contains "$out" "up to date" "U01 reports up to date"
assert_eq "$(sha256sum "$root/upstream.lock")" "$lock_before" "U01 lock is unchanged"
assert_eq "$(sha256sum "$root/packages/cachy-omarchy-shell/PKGBUILD")" "$pkg_before" "U01 PKGBUILD is unchanged"
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

exit "$ASSERT_FAILURES"
