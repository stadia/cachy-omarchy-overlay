#!/usr/bin/env bash
# M7 clean-build transport: fake makechrootpkg only; never creates a chroot.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/assert.sh"

shell_pkg=$REPO_ROOT/packages/cachy-omarchy-shell/PKGBUILD
overlay_pkg=$REPO_ROOT/packages/cachy-omarchy-overlay/PKGBUILD
# shell metadata may be a disposable newer candidate inside M6 update tests.
# shellcheck disable=SC1090
source "$REPO_ROOT/upstream.lock"
field() { grep -m1 -E "^$2=" "$1" | cut -d= -f2- | tr -d "'\""; }
shell_rel=$(field "$shell_pkg" pkgrel)
overlay_ver=$(field "$overlay_pkg" pkgver)
overlay_rel=$(field "$overlay_pkg" pkgrel)
assert_contains "$(cat "$shell_pkg")" '"$startdir/../../overlay/defaults"' \
  "direct shell PKGBUILD proves parent-overlay chroot failure"
assert_contains "$(cat "$overlay_pkg")" '"$startdir/../../overlay"' \
  "direct overlay PKGBUILD proves parent-overlay chroot failure"
assert_contains "$(cat "$shell_pkg")" 'clean-overlay-defaults.tar' \
  "shell has transient clean source input"
assert_contains "$(cat "$overlay_pkg")" 'clean-overlay.tar' \
  "overlay has transient clean source input"

fake=$COO_TEST_SANDBOX/fake
upstream=$COO_TEST_SANDBOX/upstream/omarchy
mkdir -p "$fake" "$COO_TEST_SANDBOX/chroot" "$upstream/shell"
printf 'fixture\n' >"$upstream/shell/shell.qml"
log=$COO_TEST_SANDBOX/makechrootpkg.log
cat >"$fake/makechrootpkg" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s|%s\n' "$PWD" "$*" >>"$COO_CLEAN_LOG"
[[ $* == *' -i '* ]] && exit 91
[[ -f PKGBUILD ]] || exit 92
if [[ $PWD == *clean-cachy-omarchy-shell ]]; then
  [[ -f clean-omarchy.tar && -f clean-overlay-defaults.tar ]] || exit 93
  listing=$(tar -tf clean-omarchy.tar)
  grep -qx 'omarchy/shell/shell.qml' <<<"$listing"
  listing=$(tar -tf clean-overlay-defaults.tar)
  grep -qx 'overlay/defaults/shell.json' <<<"$listing"
  ver=$(grep -m1 '^pkgver=' PKGBUILD | cut -d= -f2 | tr -d "'\"")
  rel=$(grep -m1 '^pkgrel=' PKGBUILD | cut -d= -f2 | tr -d "'\"")
  : >"cachy-omarchy-shell-${ver}-${rel}-any.pkg.tar.zst"
else
  [[ $PWD == *clean-cachy-omarchy-overlay ]] || exit 94
  [[ -f clean-overlay.tar ]] || exit 95
  listing=$(tar -tf clean-overlay.tar)
  grep -qx 'overlay/bin/cachy-omarchy-init' <<<"$listing"
  ver=$(grep -m1 '^pkgver=' PKGBUILD | cut -d= -f2 | tr -d "'\"")
  rel=$(grep -m1 '^pkgrel=' PKGBUILD | cut -d= -f2 | tr -d "'\"")
  : >"cachy-omarchy-overlay-${ver}-${rel}-any.pkg.tar.zst"
fi
EOF
cat >"$fake/bsdtar" <<'EOF'
#!/usr/bin/env bash
echo usr/share/cachy-omarchy/ok
EOF
chmod +x "$fake/makechrootpkg" "$fake/bsdtar"

COO_REPO_ROOT="$REPO_ROOT" \
COO_BUILD_DIR="$COO_TEST_SANDBOX/build" \
COO_STATE_DIR="$COO_TEST_SANDBOX/state" \
COO_CLEAN_CHROOT_DIR="$COO_TEST_SANDBOX/chroot" \
COO_CLEAN_OMARCHY_SOURCE="$upstream" \
COO_MAKECHROOTPKG_BIN="$fake/makechrootpkg" \
COO_BSDTAR_BIN="$fake/bsdtar" \
COO_CLEAN_LOG="$log" \
"$REPO_ROOT/bin/build-packages" --clean >"$COO_TEST_SANDBOX/output"

assert_file_exists "$COO_TEST_SANDBOX/build/cachy-omarchy-shell-${OMARCHY_VERSION}-${shell_rel}-any.pkg.tar.zst" \
  "clean shell artifact is audited and published"
assert_file_exists "$COO_TEST_SANDBOX/build/cachy-omarchy-overlay-${overlay_ver}-${overlay_rel}-any.pkg.tar.zst" \
  "clean overlay artifact is audited and published"
assert_file_exists "$COO_TEST_SANDBOX/state/validated-build.manifest" \
  "clean build publishes validated manifest"
assert_contains "$(cat "$log")" '-r ' "clean tool receives chroot root"
assert_contains "$(cat "$log")" '--nodeps' "clean tool receives non-install makepkg argument"
[[ $(wc -l <"$log") -eq 2 ]] || { echo 'FAIL: clean tool was not called exactly twice'; ASSERT_FAILURES=$((ASSERT_FAILURES + 1)); }
# Temporary source archives were made below mktemp work and must not become
# tracked copies in either package directory.
if find "$REPO_ROOT/packages" -type f \( -name 'clean-*.tar' -o -name 'overlay.tar' \) | grep -q .; then
  echo 'FAIL: clean source archive leaked into tracked package directory'
  ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
else
  echo 'ok:   clean source archives stay transient'
fi

[[ $ASSERT_FAILURES -eq 0 ]]
