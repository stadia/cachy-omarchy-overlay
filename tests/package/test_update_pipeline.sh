#!/usr/bin/env bash
# M6 U01/U06/U07 foundation: fake tools only, never network or pacman.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/assert.sh"

# A default candidate suite invokes this test again. The outer fake-tool test
# controls that recursion while retaining the candidate's actual test runner.
if [[ ${COO_UPDATE_PIPELINE_NESTED:-0} == 1 ]]; then
  echo "nested update pipeline fixture complete"
  exit 0
fi

root=$COO_TEST_SANDBOX/repo
mkdir -p "$root/packages" "$root/bin"
cp -a "$REPO_ROOT/upstream.lock" "$REPO_ROOT/UPSTREAM.md" "$root/"
while IFS= read -r -d '' path; do
  mkdir -p "$root/$(dirname "$path")"
  cp -a "$REPO_ROOT/$path" "$root/$path"
done < <(git -C "$REPO_ROOT" ls-files -z packages/cachy-omarchy-shell packages/cachy-omarchy-overlay)
cp -a "$REPO_ROOT/bin/check-upstream" "$REPO_ROOT/bin/build-packages" \
  "$REPO_ROOT/bin/validated-build.sh" "$REPO_ROOT/bin/test-packages" \
  "$REPO_ROOT/bin/install-packages" "$REPO_ROOT/bin/rollback" \
  "$REPO_ROOT/bin/update-upstream" "$REPO_ROOT/bin/bump-pkgrel" "$root/bin/"
chmod +x "$root/bin"/*
fake=$COO_TEST_SANDBOX/fake
mkdir -p "$fake"
log=$COO_TEST_SANDBOX/tools.log

cat >"$fake/git" <<'EOF'
#!/usr/bin/env bash
# v4.0.1 is annotated: direct ref is tag object, peeled ref is commit.
if [[ ${COO_FAKE_NO_UPDATE:-0} == 1 ]]; then
  printf '%s\n' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa refs/tags/v4.0.0'
  printf '%s\n' 'f0020448ca87329199de7cb12f2015ebc4a3e5e7 refs/tags/v4.0.0^{}'
  exit 0
fi
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
  target="$PKGDEST/cachy-omarchy-shell-${ver}-${rel}-any.pkg.tar.zst"
  if [[ -n ${COO_FAKE_ARTIFACT_SOURCE:-} ]]; then
    source_archive=$(find "$COO_FAKE_ARTIFACT_SOURCE" -maxdepth 1 -type f -name 'cachy-omarchy-shell-*.pkg.tar.zst' -print -quit)
    cp "$source_archive" "$target"
  else
    : >"$target"
  fi
else
  ver=$(grep -m1 '^pkgver=' PKGBUILD | cut -d= -f2 | tr -d "'\"")
  rel=$(grep -m1 '^pkgrel=' PKGBUILD | cut -d= -f2 | tr -d "'\"")
  target="$PKGDEST/cachy-omarchy-overlay-${ver}-${rel}-any.pkg.tar.zst"
  if [[ -n ${COO_FAKE_ARTIFACT_SOURCE:-} ]]; then
    source_archive=$(find "$COO_FAKE_ARTIFACT_SOURCE" -maxdepth 1 -type f -name 'cachy-omarchy-overlay-*.pkg.tar.zst' -print -quit)
    cp "$source_archive" "$target"
  else
    : >"$target"
  fi
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
cat >"$fake/mv" <<'EOF'
#!/usr/bin/env bash
last=${!#}
if [[ ${COO_FAKE_POINTER_FAIL:-0} == 1 && $last == */validated-build.manifest ]]; then exit 10; fi
if [[ ${COO_FAKE_METADATA_PKG_MV_FAIL:-0} == 1 && ${COO_UPDATE_METADATA_PUBLISH:-} == pkg ]]; then exit 13; fi
if [[ ${COO_FAKE_INSTALLED_MV_FAIL:-0} == 1 && ${COO_INSTALL_FINALIZE:-0} == 1 && $last == */installed-build.manifest ]]; then exit 14; fi
if [[ ${COO_FAKE_ARCHIVE_MV_FAIL:-0} == 1 && $last == */packages/previous-* ]]; then exit 12; fi
/usr/bin/mv "$@"
EOF
cat >"$fake/pacman" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$COO_PACMAN_LOG"
[[ ${COO_FAKE_PACMAN_FAIL:-0} != 1 ]] || exit 11
EOF
cat >"$fake/test-runner" <<'EOF'
#!/usr/bin/env bash
[[ -n ${COO_TEST_LOG:-} ]] && printf 'runner\n' >>"$COO_TEST_LOG"
case ${COO_FAKE_TEST_MODE:-pass} in
  pass) printf 'all test coverage ran\n' ;;
  skip) printf 'skip: installed tree absent\n' ;;
  fail) printf 'FAIL: runtime\n'; exit 9 ;;
esac
EOF
cat >"$fake/smoke" <<'EOF'
#!/usr/bin/env bash
printf 'smoke\n' >>"$COO_PACMAN_LOG"
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
release=$(awk -F= '$1 == "RELEASE" { print $2 }' "$manifest")
assert_file_exists "$COO_TEST_SANDBOX/state/$release/artifacts/cachy-omarchy-shell-4.0.0-1-any.pkg.tar.zst" "manifest points to immutable shell release"

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
mkdir -p "$trans_build" "$trans_state/validated-builds/old/artifacts"
printf 'old-shell' >"$trans_build/cachy-omarchy-shell-3.9.9-1-any.pkg.tar.zst"
printf 'old-overlay' >"$trans_build/cachy-omarchy-overlay-0.0.9-1-any.pkg.tar.zst"
printf 'old-shell' >"$trans_state/validated-builds/old/artifacts/cachy-omarchy-shell-3.9.9-1-any.pkg.tar.zst"
printf 'old-overlay' >"$trans_state/validated-builds/old/artifacts/cachy-omarchy-overlay-0.0.9-1-any.pkg.tar.zst"
printf 'RELEASE=validated-builds/old\nARTIFACT=old old\n' >"$trans_state/validated-build.manifest"
old_pointer=$(cat "$trans_state/validated-build.manifest")
old_sum=$(sha256sum "$trans_build"/* "$trans_state/validated-builds/old/artifacts"/* "$trans_state/validated-build.manifest")
code=0
out=$(COO_TOOL_LOG="$log" COO_FAKE_SHA_FAIL=1 COO_REPO_ROOT="$root" COO_BUILD_DIR="$trans_build" COO_STATE_DIR="$trans_state" COO_MAKEPKG_BIN="$fake/makepkg" COO_BSDTAR_BIN="$fake/bsdtar" COO_SHA256_BIN="$fake/sha256sum" COO_INSTALL_BIN="$fake/install" "$root/bin/build-packages" 2>&1) || code=$?
assert_eq "$code" "9" "checksum failure blocks publication"
assert_eq "$(sha256sum "$trans_build"/* "$trans_state/validated-builds/old/artifacts"/* "$trans_state/validated-build.manifest")" "$old_sum" "checksum failure preserves old pair and manifest"
code=0
out=$(COO_TOOL_LOG="$log" COO_FAKE_COPY_FAIL=1 COO_REPO_ROOT="$root" COO_BUILD_DIR="$trans_build" COO_STATE_DIR="$trans_state" COO_MAKEPKG_BIN="$fake/makepkg" COO_BSDTAR_BIN="$fake/bsdtar" COO_SHA256_BIN="$fake/sha256sum" COO_INSTALL_BIN="$fake/install" "$root/bin/build-packages" 2>&1) || code=$?
assert_eq "$code" "8" "copy failure blocks publication"
assert_eq "$(sha256sum "$trans_build"/* "$trans_state/validated-builds/old/artifacts"/* "$trans_state/validated-build.manifest")" "$old_sum" "copy failure preserves old pair and manifest"
code=0
out=$(COO_TOOL_LOG="$log" COO_FAKE_EXTRA=1 COO_REPO_ROOT="$root" COO_BUILD_DIR="$COO_TEST_SANDBOX/ambiguous-build" COO_STATE_DIR="$COO_TEST_SANDBOX/ambiguous-state" COO_MAKEPKG_BIN="$fake/makepkg" COO_BSDTAR_BIN="$fake/bsdtar" "$root/bin/build-packages" 2>&1) || code=$?
assert_eq "$code" "1" "ambiguous artifacts are rejected"
assert_contains "$out" "ambiguous build artifacts" "extra artifact reaches ambiguity guard"
[[ -e $COO_TEST_SANDBOX/ambiguous-state/validated-build.manifest ]] && published=1 || published=0
assert_eq "$published" "0" "ambiguous artifacts publish no manifest"

# Pointer rename is final commit: failure preserves the old pointer/release.
code=0
out=$(COO_TOOL_LOG="$log" COO_FAKE_POINTER_FAIL=1 COO_REPO_ROOT="$root" COO_BUILD_DIR="$trans_build" COO_STATE_DIR="$trans_state" COO_MAKEPKG_BIN="$fake/makepkg" COO_BSDTAR_BIN="$fake/bsdtar" COO_MV_BIN="$fake/mv" "$root/bin/build-packages" 2>&1) || code=$?
assert_eq "$code" "10" "manifest replacement failure blocks validation commit"
assert_eq "$(cat "$trans_state/validated-build.manifest")" "$old_pointer" "pointer failure preserves old manifest"
assert_file_exists "$trans_state/validated-builds/old/artifacts/cachy-omarchy-shell-3.9.9-1-any.pkg.tar.zst" "pointer failure preserves referenced old release"

# Dynamic shell version comes from fixture lock/PKGBUILD, not hard-coded names.
dyn=$COO_TEST_SANDBOX/dynamic-repo
cp -a "$root" "$dyn"
sed -i 's/OMARCHY_VERSION=4.0.0/OMARCHY_VERSION=4.0.1/; s/f0020448ca87329199de7cb12f2015ebc4a3e5e7/5555555555555555555555555555555555555555/' "$dyn/upstream.lock"
sed -i "s/pkgver=4.0.0/pkgver=4.0.1/; s/_commit='[0-9a-f]*'/_commit='5555555555555555555555555555555555555555'/" "$dyn/packages/cachy-omarchy-shell/PKGBUILD"
COO_TOOL_LOG="$log" COO_REPO_ROOT="$dyn" COO_BUILD_DIR="$COO_TEST_SANDBOX/dynamic-build" COO_STATE_DIR="$COO_TEST_SANDBOX/dynamic-state" COO_MAKEPKG_BIN="$fake/makepkg" COO_BSDTAR_BIN="$fake/bsdtar" "$dyn/bin/build-packages" >/dev/null
dynamic_manifest=$(cat "$COO_TEST_SANDBOX/dynamic-state/validated-build.manifest")
assert_contains "$dynamic_manifest" "OMARCHY_VERSION=4.0.1" "dynamic lock version reaches manifest"
assert_contains "$dynamic_manifest" "cachy-omarchy-shell-4.0.1-1-any.pkg.tar.zst" "dynamic shell artifact name is used"
assert_contains "$dynamic_manifest" "cachy-omarchy-overlay-0.1.0-1-any.pkg.tar.zst" "overlay version remains independent"

# U08: testing requires a current manifest first, and any skip is a failure.
missing_state=$COO_TEST_SANDBOX/missing-state
code=0
out=$(COO_REPO_ROOT="$root" COO_STATE_DIR="$missing_state" COO_TEST_RUNNER="$fake/test-runner" "$root/bin/test-packages" 2>&1) || code=$?
assert_eq "$code" "1" "U08 missing manifest blocks tests before false green"
assert_contains "$out" "validated manifest missing" "U08 reports missing manifest"

# Strict parser regression: an empty singleton must still count as present,
# so a later valid duplicate cannot reach the runner.
manifest_backup=$(cat "$COO_TEST_SANDBOX/state/validated-build.manifest")
printf 'RELEASE=\n%s\n' "$manifest_backup" >"$COO_TEST_SANDBOX/state/validated-build.manifest"
runner_log=$COO_TEST_SANDBOX/runner.log
rm -f "$runner_log"
code=0
out=$(COO_REPO_ROOT="$root" COO_STATE_DIR="$COO_TEST_SANDBOX/state" COO_TEST_RUNNER="$fake/test-runner" COO_TEST_LOG="$runner_log" "$root/bin/test-packages" 2>&1) || code=$?
assert_eq "$code" "1" "duplicate empty RELEASE blocks manifest"
assert_contains "$out" "duplicate RELEASE" "duplicate empty RELEASE is diagnosed"
[[ -e $runner_log ]] && runner_called=1 || runner_called=0
assert_eq "$runner_called" "0" "malformed manifest invokes no runner"
printf '%s\n' "$manifest_backup" >"$COO_TEST_SANDBOX/state/validated-build.manifest"

code=0
out=$(COO_REPO_ROOT="$root" COO_STATE_DIR="$COO_TEST_SANDBOX/state" COO_TEST_RUNNER="$fake/test-runner" COO_FAKE_TEST_MODE=skip "$root/bin/test-packages" 2>&1) || code=$?
assert_eq "$code" "1" "U08 skipped installed-tree coverage fails"
assert_contains "$out" "skip:" "U08 preserves runner skip evidence"
code=0
out=$(COO_REPO_ROOT="$root" COO_STATE_DIR="$COO_TEST_SANDBOX/state" COO_TEST_RUNNER="$fake/test-runner" COO_FAKE_TEST_MODE=fail "$root/bin/test-packages" 2>&1) || code=$?
assert_eq "$code" "9" "U08 failed runner blocks validation"
out=$(COO_REPO_ROOT="$root" COO_STATE_DIR="$COO_TEST_SANDBOX/state" COO_TEST_RUNNER="$fake/test-runner" COO_FAKE_TEST_MODE=pass "$root/bin/test-packages" 2>&1); code=$?
assert_eq "$code" "0" "U08 non-skipped runner passes"

# Seed a complete prior installed pair. It must be archived before fake pacman.
prior=$COO_TEST_SANDBOX/state/packages/previous-old
mkdir -p "$prior/artifacts"
old_shell=cachy-omarchy-shell-3.9.9-1-any.pkg.tar.zst
old_overlay=cachy-omarchy-overlay-0.0.9-1-any.pkg.tar.zst
printf old-shell >"$prior/artifacts/$old_shell"
printf old-overlay >"$prior/artifacts/$old_overlay"
old_shell_sum=$(sha256sum "$prior/artifacts/$old_shell" | awk '{print $1}')
old_overlay_sum=$(sha256sum "$prior/artifacts/$old_overlay" | awk '{print $1}')
cat >"$prior/validated-build.manifest" <<EOF
RELEASE=packages/previous-old
OMARCHY_VERSION=3.9.9
OMARCHY_COMMIT=9999999999999999999999999999999999999999
ARTIFACT=$old_shell $old_shell_sum
ARTIFACT=$old_overlay $old_overlay_sum
EOF
cp "$prior/validated-build.manifest" "$COO_TEST_SANDBOX/state/installed-build.manifest"
paclog=$COO_TEST_SANDBOX/pacman.log
: >"$paclog"
code=0
out=$(COO_REPO_ROOT="$root" COO_STATE_DIR="$COO_TEST_SANDBOX/state" COO_PACMAN_BIN="$fake/pacman" COO_PACMAN_LOG="$paclog" "$root/bin/install-packages" 2>&1) || code=$?
assert_eq "$code" "1" "explicit install refusal blocks pacman"
assert_eq "$(wc -l <"$paclog")" "0" "refused install invokes no pacman"

# The archive rename is a hard precondition: a failed archive must block pacman.
: >"$paclog"
code=0
out=$(COO_REPO_ROOT="$root" COO_STATE_DIR="$COO_TEST_SANDBOX/state" COO_PACMAN_BIN="$fake/pacman" COO_PACMAN_LOG="$paclog" COO_MV_BIN="$fake/mv" COO_FAKE_ARCHIVE_MV_FAIL=1 "$root/bin/install-packages" --install 2>&1) || code=$?
assert_eq "$code" "1" "archive rename failure blocks install"
assert_eq "$(wc -l <"$paclog")" "0" "archive rename failure invokes no pacman"

COO_REPO_ROOT="$root" COO_STATE_DIR="$COO_TEST_SANDBOX/state" COO_PACMAN_BIN="$fake/pacman" COO_PACMAN_LOG="$paclog" "$root/bin/install-packages" --install >/dev/null
assert_contains "$(cat "$paclog")" "-U" "U09 install calls fake pacman explicitly"
assert_contains "$(cat "$paclog")" "cachy-omarchy-shell-4.0.0-1-any.pkg.tar.zst" "U09 installs exact current shell"
assert_eq "$(cat "$prior/artifacts/$old_shell")" "old-shell" "U09 previous shell remains archived"
assert_eq "$(cat "$prior/artifacts/$old_overlay")" "old-overlay" "U09 previous overlay remains archived"
archived_count=$(find "$COO_TEST_SANDBOX/state/packages" -name validated-build.manifest | wc -l)
[[ $archived_count -ge 2 ]] && archived=0 || archived=1
assert_eq "$archived" "0" "U09 install archives prior validated pair"

# U10: rollback uses exactly the newest complete archived pair and optional smoke.
: >"$paclog"
COO_REPO_ROOT="$root" COO_STATE_DIR="$COO_TEST_SANDBOX/state" COO_PACMAN_BIN="$fake/pacman" COO_PACMAN_LOG="$paclog" COO_ROLLBACK_SMOKE_BIN="$fake/smoke" "$root/bin/rollback" >/dev/null
rollback_line=$(head -n1 "$paclog")
assert_contains "$rollback_line" "-U" "U10 rollback invokes fake pacman with -U"
assert_contains "$rollback_line" "cachy-omarchy-shell-3.9.9-1-any.pkg.tar.zst" "U10 rollback selects prior shell only"
assert_contains "$rollback_line" "cachy-omarchy-overlay-0.0.9-1-any.pkg.tar.zst" "U10 rollback selects prior overlay only"
assert_eq "$(tail -n1 "$paclog")" "smoke" "U10 smoke runs only after pacman"

# Missing/corrupt prior state must not invoke pacman.
: >"$paclog"
code=0
out=$(COO_REPO_ROOT="$root" COO_STATE_DIR="$COO_TEST_SANDBOX/no-prior" COO_PACMAN_BIN="$fake/pacman" COO_PACMAN_LOG="$paclog" "$root/bin/rollback" 2>&1) || code=$?
assert_eq "$code" "1" "U10 missing prior state fails safely"
assert_eq "$(wc -l <"$paclog")" "0" "missing prior invokes no pacman"
mkdir -p "$COO_TEST_SANDBOX/corrupt-state/packages/previous-z/artifacts"
printf 'RELEASE=packages/previous-z\nOMARCHY_VERSION=3.9.9\nOMARCHY_COMMIT=9999999999999999999999999999999999999999\nARTIFACT=bad.pkg.tar.zst deadbeef\nARTIFACT=bad2.pkg.tar.zst deadbeef\n' >"$COO_TEST_SANDBOX/corrupt-state/packages/previous-z/validated-build.manifest"
code=0
out=$(COO_REPO_ROOT="$root" COO_STATE_DIR="$COO_TEST_SANDBOX/corrupt-state" COO_PACMAN_BIN="$fake/pacman" COO_PACMAN_LOG="$paclog" "$root/bin/rollback" 2>&1) || code=$?
assert_eq "$code" "1" "U10 corrupt prior state fails safely"
assert_eq "$(wc -l <"$paclog")" "0" "corrupt prior invokes no pacman"

# U01 update no-op: discovery must not mutate metadata or invoke packaging tools.
update_lock_before=$(sha256sum "$root/upstream.lock")
update_pkg_before=$(sha256sum "$root/packages/cachy-omarchy-shell/PKGBUILD")
: >"$log"
out=$(COO_FAKE_NO_UPDATE=1 COO_REPO_ROOT="$root" COO_GIT_BIN="$fake/git" COO_TOOL_LOG="$log" "$root/bin/update-upstream" 2>&1); code=$?
assert_eq "$code" "0" "U01 update no-op exits cleanly"
assert_contains "$out" "up to date" "U01 update reports up to date"
assert_eq "$(sha256sum "$root/upstream.lock")" "$update_lock_before" "U01 update leaves lock unchanged"
assert_eq "$(sha256sum "$root/packages/cachy-omarchy-shell/PKGBUILD")" "$update_pkg_before" "U01 update leaves PKGBUILD unchanged"
assert_eq "$(wc -l <"$log")" "0" "U01 update invokes no build"

# Candidate validation must carry docs required by the repository's default test runner.
cp -a "$REPO_ROOT/docs" "$root/docs"
cp -a "$REPO_ROOT/tests" "$root/tests"
cp -a "$REPO_ROOT/lib" "$root/lib"
cp -a "$REPO_ROOT/overlay" "$root/overlay"

# U02/U03: successful update uses peeled commit, resets only shell pkgrel, and never installs.
update_state=$COO_TEST_SANDBOX/update-state
update_build=$COO_TEST_SANDBOX/update-build
pac_update=$COO_TEST_SANDBOX/update-pacman.log
: >"$pac_update"
code=0
out=$(WAYLAND_DISPLAY= COO_UPDATE_PIPELINE_NESTED=1 COO_REPO_ROOT="$root" COO_GIT_BIN="$fake/git" COO_STATE_DIR="$update_state" COO_BUILD_DIR="$update_build" COO_OMARCHY_GIT="$REPO_ROOT/build/omarchy" COO_TOOL_LOG="$log" COO_MAKEPKG_BIN="$fake/makepkg" COO_BSDTAR_BIN="$fake/bsdtar" COO_FAKE_ARTIFACT_SOURCE="$REPO_ROOT/build" COO_PACMAN_BIN="$fake/pacman" COO_PACMAN_LOG="$pac_update" "$root/bin/update-upstream" 2>&1) || code=$?
assert_eq "$code" "0" "U02 update validates and publishes candidate"
assert_contains "$out" "PASS tests/runtime/test_m3_docs.sh" "candidate default suite runs M3 docs test"
assert_contains "$out" "PASS tests/package/test_package_files.sh" "candidate default suite reaches package files test"
updated_lock=$(cat "$root/upstream.lock")
updated_pkg=$(cat "$root/packages/cachy-omarchy-shell/PKGBUILD")
assert_contains "$updated_lock" "OMARCHY_VERSION=4.0.1" "U02 lock version updates"
assert_contains "$updated_lock" "OMARCHY_COMMIT=2222222222222222222222222222222222222222" "U02 lock uses peeled commit"
assert_contains "$updated_lock" "OMARCHY_TAG=v4.0.1" "U02 lock tag updates"
assert_contains "$updated_pkg" "pkgver=4.0.1" "U03 shell pkgver updates"
assert_contains "$updated_pkg" "pkgrel=1" "U03 pkgrel resets to one"
assert_contains "$updated_pkg" "_commit='2222222222222222222222222222222222222222'" "U02 shell commit updates"
assert_eq "$(grep -m1 '^pkgver=' "$root/packages/cachy-omarchy-overlay/PKGBUILD")" "pkgver=0.1.0" "U02 overlay version is independent"
assert_eq "$(wc -l <"$pac_update")" "0" "U02 update never invokes pacman"
assert_contains "$out" "UPSTREAM.md requires human" "UPSTREAM.md deferred with explicit reason"

# U04 is explicit local packaging revision only: no lock or version mutation.
lock_before_bump=$(sha256sum "$root/upstream.lock")
version_before_bump=$(grep -m1 '^pkgver=' "$root/packages/cachy-omarchy-shell/PKGBUILD")
out=$(COO_REPO_ROOT="$root" "$root/bin/bump-pkgrel" 2>&1); code=$?
assert_eq "$code" "0" "U04 local pkgrel bump exits cleanly"
assert_contains "$out" "1 -> 2" "U04 reports increment"
assert_eq "$(grep -m1 '^pkgrel=' "$root/packages/cachy-omarchy-shell/PKGBUILD")" "pkgrel=2" "U04 increments only pkgrel"
assert_eq "$(grep -m1 '^pkgver=' "$root/packages/cachy-omarchy-shell/PKGBUILD")" "$version_before_bump" "U04 preserves pkgver"
assert_eq "$(sha256sum "$root/upstream.lock")" "$lock_before_bump" "U04 preserves lock"

# U05-U08 failures keep original tracked metadata and never invoke pacman.
for mode in patch build audit test; do
  failroot=$COO_TEST_SANDBOX/update-fail-$mode
  cp -a "$root" "$failroot"
  # U02 changed root to 4.0.1; each failure fixture must start at the prior pin
  # so update-upstream actually enters its patch/build/audit/test stage.
  sed -i 's/OMARCHY_VERSION=4\.0\.1/OMARCHY_VERSION=4.0.0/; s/OMARCHY_COMMIT=2222222222222222222222222222222222222222/OMARCHY_COMMIT=f0020448ca87329199de7cb12f2015ebc4a3e5e7/; s/OMARCHY_TAG=v4\.0\.1/OMARCHY_TAG=v4.0.0/' "$failroot/upstream.lock"
  sed -i "s/pkgver=4.0.1/pkgver=4.0.0/; s/pkgrel=2/pkgrel=1/; s/_commit='2222222222222222222222222222222222222222'/_commit='f0020448ca87329199de7cb12f2015ebc4a3e5e7'/" "$failroot/packages/cachy-omarchy-shell/PKGBUILD"
  before_lock=$(sha256sum "$failroot/upstream.lock")
  before_pkg=$(sha256sum "$failroot/packages/cachy-omarchy-shell/PKGBUILD")
  fail_pac=$COO_TEST_SANDBOX/fail-$mode-pacman.log
  : >"$fail_pac"
  envs=(COO_REPO_ROOT="$failroot" COO_GIT_BIN="$fake/git" COO_STATE_DIR="$COO_TEST_SANDBOX/fail-$mode-state" COO_BUILD_DIR="$COO_TEST_SANDBOX/fail-$mode-build" COO_TOOL_LOG="$log" COO_MAKEPKG_BIN="$fake/makepkg" COO_BSDTAR_BIN="$fake/bsdtar" COO_TEST_RUNNER="$fake/test-runner" COO_PACMAN_BIN="$fake/pacman" COO_PACMAN_LOG="$fail_pac")
  case $mode in
    patch) envs+=(COO_PATCH_FAIL=1); update_id=U05; expected_code=1 ;;
    build) envs+=(COO_FAKE_BUILD_FAIL=1); update_id=U06; expected_code=7 ;;
    audit) envs+=(COO_FAKE_AUDIT_FAIL=1); update_id=U07; expected_code=1 ;;
    test) envs+=(COO_FAKE_TEST_MODE=skip); update_id=U08; expected_code=1 ;;
  esac
  code=0
  out=$(env "${envs[@]}" "$failroot/bin/update-upstream" 2>&1) || code=$?
  assert_eq "$code" "$expected_code" "$update_id $mode failure blocks publish"
  assert_eq "$(sha256sum "$failroot/upstream.lock")" "$before_lock" "U$mode failure preserves lock"
  assert_eq "$(sha256sum "$failroot/packages/cachy-omarchy-shell/PKGBUILD")" "$before_pkg" "U$mode failure preserves PKGBUILD"
  assert_eq "$(wc -l <"$fail_pac")" "0" "U$mode failure invokes no pacman"
done

# Metadata publication is a transaction boundary: a failed second rename must
# leave both tracked inputs and the old authoritative pointer/release intact.
pubroot=$COO_TEST_SANDBOX/metadata-publish-repo
cp -a "$root" "$pubroot"
sed -i 's/OMARCHY_VERSION=4\.0\.1/OMARCHY_VERSION=4.0.0/; s/OMARCHY_COMMIT=2222222222222222222222222222222222222222/OMARCHY_COMMIT=f0020448ca87329199de7cb12f2015ebc4a3e5e7/; s/OMARCHY_TAG=v4\.0\.1/OMARCHY_TAG=v4.0.0/' "$pubroot/upstream.lock"
sed -i "s/pkgver=4.0.1/pkgver=4.0.0/; s/pkgrel=2/pkgrel=1/; s/_commit='2222222222222222222222222222222222222222'/_commit='f0020448ca87329199de7cb12f2015ebc4a3e5e7'/" "$pubroot/packages/cachy-omarchy-shell/PKGBUILD"
pub_state=$COO_TEST_SANDBOX/metadata-publish-state
cp -a "$COO_TEST_SANDBOX/state" "$pub_state"
pub_lock_before=$(sha256sum "$pubroot/upstream.lock")
pub_pkg_before=$(sha256sum "$pubroot/packages/cachy-omarchy-shell/PKGBUILD")
pub_pointer_before=$(cat "$pub_state/validated-build.manifest")
pub_old_release=$(awk -F= '$1 == "RELEASE" { print $2; exit }' "$pub_state/validated-build.manifest")
code=0
out=$(COO_REPO_ROOT="$pubroot" COO_GIT_BIN="$fake/git" COO_STATE_DIR="$pub_state" COO_BUILD_DIR="$COO_TEST_SANDBOX/metadata-publish-build" COO_TOOL_LOG="$log" COO_MAKEPKG_BIN="$fake/makepkg" COO_BSDTAR_BIN="$fake/bsdtar" COO_TEST_RUNNER="$fake/test-runner" COO_MV_BIN="$fake/mv" COO_FAKE_METADATA_PKG_MV_FAIL=1 "$pubroot/bin/update-upstream" 2>&1) || code=$?
assert_eq "$code" "1" "metadata second rename failure aborts update"
assert_eq "$(sha256sum "$pubroot/upstream.lock")" "$pub_lock_before" "metadata failure restores lock"
assert_eq "$(sha256sum "$pubroot/packages/cachy-omarchy-shell/PKGBUILD")" "$pub_pkg_before" "metadata failure preserves PKGBUILD"
assert_eq "$(cat "$pub_state/validated-build.manifest")" "$pub_pointer_before" "metadata failure preserves old manifest pointer"
assert_file_exists "$pub_state/$pub_old_release/artifacts/cachy-omarchy-shell-4.0.0-1-any.pkg.tar.zst" "metadata failure preserves old referenced release"

# A pacman-success/final-pointer-failure state is explicitly pending. Neither
# a new install nor rollback may trust the stale installed pointer afterwards.
postroot=$COO_TEST_SANDBOX/post-pacman-repo
cp -a "$root" "$postroot"
sed -i 's/OMARCHY_VERSION=4\.0\.1/OMARCHY_VERSION=4.0.0/; s/OMARCHY_COMMIT=2222222222222222222222222222222222222222/OMARCHY_COMMIT=f0020448ca87329199de7cb12f2015ebc4a3e5e7/; s/OMARCHY_TAG=v4\.0\.1/OMARCHY_TAG=v4.0.0/' "$postroot/upstream.lock"
sed -i "s/pkgver=4.0.1/pkgver=4.0.0/; s/pkgrel=2/pkgrel=1/; s/_commit='2222222222222222222222222222222222222222'/_commit='f0020448ca87329199de7cb12f2015ebc4a3e5e7'/" "$postroot/packages/cachy-omarchy-shell/PKGBUILD"
poststate=$COO_TEST_SANDBOX/post-pacman-state
cp -a "$COO_TEST_SANDBOX/state" "$poststate"
: >"$paclog"
code=0
out=$(COO_REPO_ROOT="$postroot" COO_STATE_DIR="$poststate" COO_PACMAN_BIN="$fake/pacman" COO_PACMAN_LOG="$paclog" COO_MV_BIN="$fake/mv" COO_FAKE_INSTALLED_MV_FAIL=1 "$postroot/bin/install-packages" --install 2>&1) || code=$?
assert_eq "$code" "14" "post-pacman installed pointer failure is reported"
assert_file_exists "$poststate/install-pending.manifest" "post-pacman failure leaves explicit pending state"
assert_eq "$(wc -l <"$paclog")" "1" "post-pacman failure ran pacman exactly once"
: >"$paclog"
code=0
out=$(COO_REPO_ROOT="$postroot" COO_STATE_DIR="$poststate" COO_PACMAN_BIN="$fake/pacman" COO_PACMAN_LOG="$paclog" "$postroot/bin/install-packages" --install 2>&1) || code=$?
assert_eq "$code" "1" "pending install blocks another install"
assert_eq "$(wc -l <"$paclog")" "0" "pending install blocks further pacman"
code=0
out=$(COO_REPO_ROOT="$postroot" COO_STATE_DIR="$poststate" COO_PACMAN_BIN="$fake/pacman" COO_PACMAN_LOG="$paclog" "$postroot/bin/rollback" 2>&1) || code=$?
assert_eq "$code" "1" "pending install blocks rollback"
assert_eq "$(wc -l <"$paclog")" "0" "pending rollback invokes no pacman"

exit "$ASSERT_FAILURES"
