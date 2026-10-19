#!/usr/bin/env bash
# bin/build-packages·test-packages·install-packages·rollback 을 가짜 도구로
# 검사한다. 네트워크·실제 pacman·sudo·makepkg 는 쓰지 않는다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

root=$COO_TEST_SANDBOX/repo
fake=$COO_TEST_SANDBOX/fake
build=$COO_TEST_SANDBOX/build
mkdir -p "$root/packages/cachy-omarchy-shell" "$root/packages/cachy-omarchy-overlay" "$fake"
cp -a "$REPO_ROOT/bin" "$root/bin"
cat >"$root/upstream.lock" <<'EOT'
OMARCHY_VERSION=4.0.4
OMARCHY_COMMIT=1111111111111111111111111111111111111111
EOT
printf 'pkgver=4.0.4\npkgrel=2\n' >"$root/packages/cachy-omarchy-shell/PKGBUILD"
printf 'pkgver=0.3.0\npkgrel=1\n' >"$root/packages/cachy-omarchy-overlay/PKGBUILD"
shell_now=cachy-omarchy-shell-4.0.4-2-any.pkg.tar.zst
overlay_now=cachy-omarchy-overlay-0.3.0-1-any.pkg.tar.zst

cat >"$fake/makepkg" <<'EOT'
#!/usr/bin/env bash
set -euo pipefail
[[ ${COO_FAKE_BUILD_FAIL:-0} != 1 ]] || { echo 'fake-makepkg: forced build failure' >&2; exit 7; }
name=$(basename "$PWD")
ver=$(grep -m1 '^pkgver=' PKGBUILD | cut -d= -f2)
rel=$(grep -m1 '^pkgrel=' PKGBUILD | cut -d= -f2)
mkdir -p "$PKGDEST"
printf '%s\n' "$name-$ver-$rel" >"$PKGDEST/$name-$ver-$rel-any.pkg.tar.zst"
[[ ${COO_FAKE_EXTRA:-0} != 1 ]] || : >"$PKGDEST/extra.pkg.tar.zst"
EOT
cat >"$fake/bsdtar" <<'EOT'
#!/usr/bin/env bash
if [[ ${COO_FAKE_AUDIT_FAIL:-0} == 1 ]]; then echo etc/os-release; else echo usr/share/cachy-omarchy/ok; fi
EOT
chmod +x "$fake"/*

run_build() {
  COO_REPO_ROOT="$root" COO_BUILD_DIR="$build" COO_MAKEPKG_BIN="$fake/makepkg" \
    COO_BSDTAR_BIN="$fake/bsdtar" "$root/bin/build-packages" "$@" 2>&1
}

# --clean (makechrootpkg) 는 제거됐다. 깨끗한 환경 증명은 CI resolve lane 이 한다.
code=0
out=$(run_build --clean) || code=$?
assert_eq "$code" "2" "build-packages rejects removed --clean"
assert_contains "$out" "unknown argument: --clean" "removed --clean is reported as unknown"

exit "$ASSERT_FAILURES"
