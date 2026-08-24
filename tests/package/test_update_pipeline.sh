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

# U02 invokes the candidate's real default suite, whose runtime/package tests
# extract both packages.  Name the required inputs from the current package
# metadata and snapshot those exact archives before validation; never choose
# an arbitrary ignored build leftover by directory order or mtime.
shell_input_ver=$(grep -m1 '^pkgver=' "$REPO_ROOT/packages/cachy-omarchy-shell/PKGBUILD" | cut -d= -f2)
shell_input_rel=$(grep -m1 '^pkgrel=' "$REPO_ROOT/packages/cachy-omarchy-shell/PKGBUILD" | cut -d= -f2)
overlay_input_ver=$(grep -m1 '^pkgver=' "$REPO_ROOT/packages/cachy-omarchy-overlay/PKGBUILD" | cut -d= -f2)
overlay_input_rel=$(grep -m1 '^pkgrel=' "$REPO_ROOT/packages/cachy-omarchy-overlay/PKGBUILD" | cut -d= -f2)
required_shell_artifact="$REPO_ROOT/build/cachy-omarchy-shell-${shell_input_ver}-${shell_input_rel}-any.pkg.tar.zst"
required_overlay_artifact="$REPO_ROOT/build/cachy-omarchy-overlay-${overlay_input_ver}-${overlay_input_rel}-any.pkg.tar.zst"
for required_artifact in "$required_shell_artifact" "$required_overlay_artifact"; do
  [[ -f $required_artifact ]] || {
    printf '%s\n' "error: U02 required package artifact missing (run the approved build-before-test step): $required_artifact" >&2
    exit 1
  }
done
u02_artifact_fixture=$COO_TEST_SANDBOX/u02-package-artifacts
mkdir -p "$u02_artifact_fixture"
u02_shell_fixture="$u02_artifact_fixture/shell.pkg.tar.zst"
u02_overlay_fixture="$u02_artifact_fixture/overlay.pkg.tar.zst"
cp -a "$required_shell_artifact" "$u02_shell_fixture"
cp -a "$required_overlay_artifact" "$u02_overlay_fixture"
assert_eq "$(sha256sum "$u02_shell_fixture" | awk '{print $1}')" "$(sha256sum "$required_shell_artifact" | awk '{print $1}')" \
  "U02 snapshots the required shell package artifact"
assert_eq "$(sha256sum "$u02_overlay_fixture" | awk '{print $1}')" "$(sha256sum "$required_overlay_artifact" | awk '{print $1}')" \
  "U02 snapshots the required overlay package artifact"

# Task 5c: bin/update-upstream regenerates tests/data/upstream-helpers.txt
# by fetching the new pin's real tree (fix round 2). A synthetic sha with no
# real git object anywhere cannot exercise that honestly -- trusting
# $fake/git's exit code for that fetch, with no real repository behind it,
# is exactly the "verifies nothing" failure mode this project treats as its
# worst (fix round 2 caught itself doing this). So the v4.0.1 target here is
# a real commit in a real, small, disposable local repository, not a magic
# hex string. $fake/git below fakes only the one call a test cannot ask a
# real remote to answer honestly -- `ls-remote --tags`, i.e. what a live
# service currently advertises -- and passes every other subcommand
# straight through to the real system git, so the fetch this test exercises
# is a real fetch against real objects.
fixture_source=${COO_OMARCHY_GIT:-$REPO_ROOT/build/omarchy}
if [[ ! -d $fixture_source && -d $REPO_ROOT/packages/cachy-omarchy-shell/src/omarchy ]]; then
  fixture_source=$REPO_ROOT/packages/cachy-omarchy-shell/src/omarchy
fi
assert_file_exists "$fixture_source/shell/shell.qml" "U02 fixture starts from pinned upstream source"
fixture_upstream=$COO_TEST_SANDBOX/upstream-fixture
cp -a "$fixture_source" "$fixture_upstream"
for helper in omarchy omarchy-menu omarchy-theme-set omarchy-battery-status omarchy-weather-status; do
  printf '#!/usr/bin/env bash\n# fixture helper: %s\n' "$helper" >"$fixture_upstream/bin/$helper"
done
git init -q "$fixture_upstream"
git -C "$fixture_upstream" -c user.email=fixture@example.invalid -c user.name=fixture -c commit.gpgsign=false \
  add -A
git -C "$fixture_upstream" -c user.email=fixture@example.invalid -c user.name=fixture -c commit.gpgsign=false \
  commit -q -m 'v4.0.1 fixture'
fixture_commit=$(git -C "$fixture_upstream" rev-parse HEAD)
fixture_repo_url="file://$fixture_upstream"

cp -a "$REPO_ROOT/upstream.lock" "$REPO_ROOT/UPSTREAM.md" "$REPO_ROOT/SPEC.md" \
  "$REPO_ROOT/README.md" "$REPO_ROOT/README.ko-KR.md" "$root/"
# The real repository URL would make a real fetch of $fixture_commit fail
# (that commit exists only in the disposable repo above); point the pin at
# the repo that actually has it.
sed -i "s#^OMARCHY_REPOSITORY=.*#OMARCHY_REPOSITORY=$fixture_repo_url#" "$root/upstream.lock"
while IFS= read -r -d '' path; do
  mkdir -p "$root/$(dirname "$path")"
  cp -a "$REPO_ROOT/$path" "$root/$path"
done < <(git -C "$REPO_ROOT" ls-files -z packages/cachy-omarchy-shell packages/cachy-omarchy-overlay)

# Hermetic fixture: the live working tree's pkgrel (SPEC §49 U04 lets a local
# revision bump it at any time) must not leak into this sandbox, or every
# assertion below naming a shell artifact would only pass by accident of
# whatever pkgrel happens to be checked out. Pin it to a sentinel distinct
# from every pkgrel this test itself produces (U02 resets to 1, U04 bumps to
# 2), so a future assertion that hardcodes "-1-" or "-2-" for the *current*
# shell artifact fails on every run -- not only when the live tree disagrees.
shell_pkgrel_pin=5
sed -i "s/^pkgrel=.*/pkgrel=${shell_pkgrel_pin}/" "$root/packages/cachy-omarchy-shell/PKGBUILD"
shell_pkgrel_pin=$(grep -m1 '^pkgrel=' "$root/packages/cachy-omarchy-shell/PKGBUILD" | cut -d= -f2 | tr -d "'\"")

# Same hermetic problem, one package over: the overlay's own pkgver evolves
# independently of upstream/shell state (PKGBUILD's own comment: "업스트림
# 버전과 독립적으로 진화한다") and gets bumped for its own patch releases at
# any time -- exactly like the working tree carrying pkgver=0.1.1 while this
# file was last written against 0.1.0. Pin it to a sentinel distinct from
# every overlay pkgver the live tree has ever used, so a future assertion
# that hardcodes the overlay's literal pkgver/artifact name fails on every
# run -- not only when the live tree happens to still agree with it.
overlay_pkgver_pin=0.9.9
sed -i "s/^pkgver=.*/pkgver=${overlay_pkgver_pin}/" "$root/packages/cachy-omarchy-overlay/PKGBUILD"
overlay_pkgver_pin=$(grep -m1 '^pkgver=' "$root/packages/cachy-omarchy-overlay/PKGBUILD" | cut -d= -f2 | tr -d "'\"")
overlay_pkgrel_pin=$(grep -m1 '^pkgrel=' "$root/packages/cachy-omarchy-overlay/PKGBUILD" | cut -d= -f2 | tr -d "'\"")
overlay_artifact_pin="cachy-omarchy-overlay-${overlay_pkgver_pin}-${overlay_pkgrel_pin}-any.pkg.tar.zst"

# The candidate invokes the repository's default test runner. Copy every
# tracked executable input rather than maintaining a hand-picked list: a new
# script referenced by a new default test must reach the candidate too.
while IFS= read -r -d '' path; do
  mkdir -p "$root/$(dirname "$path")"
  cp -a "$REPO_ROOT/$path" "$root/$path"
done < <(git -C "$REPO_ROOT" ls-files -z bin)
chmod +x "$root/bin"/*
fake=$COO_TEST_SANDBOX/fake
mkdir -p "$fake"
log=$COO_TEST_SANDBOX/tools.log

cat >"$fake/git" <<'EOF'
#!/usr/bin/env bash
# Only ls-remote --tags is faked -- the one call a test cannot ask a real
# remote to answer honestly, since it's a live "what do you advertise right
# now" question. Every other subcommand (init/fetch/ls-tree/cat-file/...)
# passes straight through to the real system git, so a real fetch of the
# fixture repository below does real work against real objects.
if [[ ${1:-} == ls-remote && ${2:-} == --tags ]]; then
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
  printf '%s\n' '__FIXTURE_COMMIT__ refs/tags/v4.0.1^{}'
  printf '%s\n' '3333333333333333333333333333333333333333 refs/tags/v3.9.9'
  exit 0
fi
exec /usr/bin/git "$@"
EOF
sed -i "s/__FIXTURE_COMMIT__/$fixture_commit/" "$fake/git"
cat >"$fake/makepkg" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$(basename "$PWD")" >>"$COO_TOOL_LOG"
if [[ -n ${COO_EXPECT_UPSTREAM_COMMIT:-} ]]; then
  actual_upstream_commit=$(/usr/bin/git -C "$COO_OMARCHY_GIT" rev-parse --verify 'HEAD^{commit}')
  [[ $actual_upstream_commit == "$COO_EXPECT_UPSTREAM_COMMIT" ]] || {
    printf 'fake-makepkg: candidate source HEAD mismatch: %s\n' "$actual_upstream_commit" >&2
    exit 6
  }
  [[ -f $COO_OMARCHY_GIT/shell/services/PluginRegistry.qml ]] || {
    printf 'fake-makepkg: candidate source is not the newly fetched upstream tree\n' >&2
    exit 6
  }
  [[ -z ${COO_CANDIDATE_SOURCE_LOG:-} ]] || printf '%s\n' "$actual_upstream_commit" >>"$COO_CANDIDATE_SOURCE_LOG"
fi
if [[ ${COO_FAKE_BUILD_FAIL:-0} == 1 ]]; then
  echo 'fake-makepkg: forced build failure (COO_FAKE_BUILD_FAIL)' >&2
  exit 7
fi
mkdir -p "$PKGDEST"
if [[ $PWD == *cachy-omarchy-shell ]]; then
  ver=$(grep -m1 '^pkgver=' PKGBUILD | cut -d= -f2 | tr -d "'\"")
  rel=$(grep -m1 '^pkgrel=' PKGBUILD | cut -d= -f2 | tr -d "'\"")
  target="$PKGDEST/cachy-omarchy-shell-${ver}-${rel}-any.pkg.tar.zst"
  if [[ -n ${COO_FAKE_SHELL_ARTIFACT:-} ]]; then
    [[ -f $COO_FAKE_SHELL_ARTIFACT ]] || {
      printf 'error: required fake shell artifact missing: %s\n' "$COO_FAKE_SHELL_ARTIFACT" >&2
      exit 1
    }
    cp "$COO_FAKE_SHELL_ARTIFACT" "$target"
  else
    : >"$target"
  fi
else
  ver=$(grep -m1 '^pkgver=' PKGBUILD | cut -d= -f2 | tr -d "'\"")
  rel=$(grep -m1 '^pkgrel=' PKGBUILD | cut -d= -f2 | tr -d "'\"")
  target="$PKGDEST/cachy-omarchy-overlay-${ver}-${rel}-any.pkg.tar.zst"
  if [[ -n ${COO_FAKE_OVERLAY_ARTIFACT:-} ]]; then
    [[ -f $COO_FAKE_OVERLAY_ARTIFACT ]] || {
      printf 'error: required fake overlay artifact missing: %s\n' "$COO_FAKE_OVERLAY_ARTIFACT" >&2
      exit 1
    }
    cp "$COO_FAKE_OVERLAY_ARTIFACT" "$target"
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
# Records exactly the argv it was invoked with, then exits 0 without exec'ing
# anything -- proves the shape of the constructed command (privilege fix)
# without ever touching a real sudo or a real pacman.
cat >"$fake/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >>"$COO_SUDO_LOG"
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

# M7 RC doctor fixture reads only the fake-lane state.  It deliberately has no
# access to the caller's packages, session, or user configuration.
doctor_root=$COO_TEST_SANDBOX/doctor-root
doctor_prefix=$doctor_root/usr/share/cachy-omarchy
doctor_compat=$doctor_root/usr/lib/cachy-omarchy/compat/bin
doctor_fake=$COO_TEST_SANDBOX/doctor-fake
mkdir -p "$doctor_prefix/upstream/shell" "$doctor_prefix/upstream/default/omarchy" \
  "$doctor_compat" "$doctor_root/usr/bin" "$doctor_root/usr/lib/systemd/user" "$doctor_fake"
printf '// fixture shell\n' >"$doctor_prefix/upstream/shell/shell.qml"
printf '{}\n' >"$doctor_prefix/upstream/default/omarchy/omarchy-menu.jsonc"
for command in cachy-omarchy-shell cachy-omarchy-launcher cachy-omarchy-bindings cachy-omarchy-keybindings; do
  printf '#!/usr/bin/env bash\nexit 0\n' >"$doctor_root/usr/bin/$command"
  chmod +x "$doctor_root/usr/bin/$command"
done
printf '#!/usr/bin/env bash\nexit 0\n' >"$doctor_compat/omarchy-shell"
chmod +x "$doctor_compat/omarchy-shell"
mkdir -p "$doctor_prefix/upstream/bin"
printf '#!/usr/bin/env bash\nexit 0\n' >"$doctor_prefix/upstream/bin/omarchy-theme-set"
chmod +x "$doctor_prefix/upstream/bin/omarchy-theme-set"
ln -s ../share/cachy-omarchy/upstream/bin/omarchy-theme-set "$doctor_root/usr/bin/omarchy-theme-set"
ln -s ../lib/cachy-omarchy/compat/bin/omarchy-shell "$doctor_root/usr/bin/omarchy-shell"
cat >"$doctor_fake/pacman" <<'EOF'
#!/usr/bin/env bash
case ${1:-} in
  -Qqo)
    [[ ${2:-} == */uwsm-app ]] || exit 1
    printf 'uwsm\n'
    ;;
  # Verbose ownership output is unavailable; doctor must use -Qqo.
  -Qo) exit 1 ;;
  -Q)
    case ${2:-} in
      cachy-omarchy-shell|cachy-omarchy-overlay) printf '%s 0.1.0-1\n' "$2"; exit 0 ;;
      omarchy|omarchy-settings) exit 1 ;;
      *) exit 1 ;;
    esac
    ;;
  *) exit 2 ;;
esac
EOF
for command in pgrep hyprctl quickshell uwsm-app; do printf '#!/usr/bin/env bash\nexit 1\n' >"$doctor_fake/$command"; done
chmod +x "$doctor_fake"/*
printf 'ID=arch\n' >"$doctor_root/os-release"
# The lock-screen PAM service lives outside every package prefix, so pin it to
# the fixture as well -- the fake lane must not read the real /etc/pam.d.
doctor_pam=$doctor_root/pam/omarchy-lock-password
mkdir -p "$(dirname "$doctor_pam")"
printf '#%%PAM-1.0\n' >"$doctor_pam"
run_rc_doctor() {
  local state=$1
  PATH="$doctor_fake:/usr/bin:/bin" WAYLAND_DISPLAY= OMARCHY_PATH="$doctor_prefix/upstream" \
    COO_OS_RELEASE="$doctor_root/os-release" COO_PREFIX_ROOT="$doctor_prefix" COO_COMPAT_BIN="$doctor_compat" \
    COO_HYPR_DIR="$COO_TEST_SANDBOX/doctor-hypr" COO_CONFIG_DIR="$COO_TEST_SANDBOX/doctor-config" \
    COO_OMARCHY_CONFIG_DIR="$COO_TEST_SANDBOX/doctor-omarchy" COO_STATE_DIR="$state" \
    COO_OMARCHY_PATH="$doctor_prefix/upstream" COO_OMARCHY_STATE_DIR="$COO_TEST_SANDBOX/doctor-omarchy-state" \
    COO_PAM_LOCK_FILE="$doctor_pam" \
    COO_SHA256_BIN=sha256sum COO_IPC_TIMEOUT=2s \
    "$REPO_ROOT/overlay/bin/cachy-omarchy-doctor" 2>&1
}

# U01: discovery is read-only and does not invoke build tools.
lock_before=$(sha256sum "$root/upstream.lock")
pkg_before=$(sha256sum "$root/packages/cachy-omarchy-shell/PKGBUILD")
out=$(COO_REPO_ROOT="$root" COO_GIT_BIN="$fake/git" "$root/bin/check-upstream" 2>&1); code=$?
assert_eq "$code" "0" "U01 no-update exits cleanly"
assert_contains "$out" "update available" "U01 reports available update"
assert_contains "$out" "$fixture_commit" "U01 uses annotated tag peeled commit"
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
assert_contains "$manifest_src" "$overlay_artifact_pin" "manifest binds overlay artifact"
release=$(awk -F= '$1 == "RELEASE" { print $2 }' "$manifest")
# Derived from the fixture's own (hermetically pinned) PKGBUILD, not a
# hardcoded pkgrel -- see shell_pkgrel_pin above.
shell_artifact_v400="cachy-omarchy-shell-4.0.0-${shell_pkgrel_pin}-any.pkg.tar.zst"
assert_file_exists "$COO_TEST_SANDBOX/state/$release/artifacts/$shell_artifact_v400" "manifest points to immutable shell release"

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
# Independence is a relation (before vs. after a shell-only bump), not a
# literal -- capture the overlay's pkgver here, before anything touches this
# checkout, so it can be compared against itself post-build below.
dyn_overlay_ver_before=$(grep -m1 '^pkgver=' "$dyn/packages/cachy-omarchy-overlay/PKGBUILD" | cut -d= -f2 | tr -d "'\"")
sed -i 's/OMARCHY_VERSION=4.0.0/OMARCHY_VERSION=4.0.1/; s/f0020448ca87329199de7cb12f2015ebc4a3e5e7/5555555555555555555555555555555555555555/' "$dyn/upstream.lock"
sed -i "s/pkgver=4.0.0/pkgver=4.0.1/; s/_commit='[0-9a-f]*'/_commit='5555555555555555555555555555555555555555'/" "$dyn/packages/cachy-omarchy-shell/PKGBUILD"
COO_TOOL_LOG="$log" COO_REPO_ROOT="$dyn" COO_BUILD_DIR="$COO_TEST_SANDBOX/dynamic-build" COO_STATE_DIR="$COO_TEST_SANDBOX/dynamic-state" COO_MAKEPKG_BIN="$fake/makepkg" COO_BSDTAR_BIN="$fake/bsdtar" "$dyn/bin/build-packages" >/dev/null
dynamic_manifest=$(cat "$COO_TEST_SANDBOX/dynamic-state/validated-build.manifest")
assert_contains "$dynamic_manifest" "OMARCHY_VERSION=4.0.1" "dynamic lock version reaches manifest"
# Read the expected name back out of the dynamic fixture's own PKGBUILD
# (the sed above only touches pkgver, so pkgrel is inherited) instead of
# hardcoding it, so this label is actually true.
dyn_shell_ver=$(grep -m1 '^pkgver=' "$dyn/packages/cachy-omarchy-shell/PKGBUILD" | cut -d= -f2 | tr -d "'\"")
dyn_shell_rel=$(grep -m1 '^pkgrel=' "$dyn/packages/cachy-omarchy-shell/PKGBUILD" | cut -d= -f2 | tr -d "'\"")
assert_contains "$dynamic_manifest" "cachy-omarchy-shell-${dyn_shell_ver}-${dyn_shell_rel}-any.pkg.tar.zst" "dynamic shell artifact name is used"
# "Independent" means a shell-only upstream bump leaves the overlay's own
# pkgver exactly as it was before the bump -- a before/after comparison, not
# a hardcoded literal. This fails if a shell bump ever does change it, and
# passes at whatever overlay pkgver the fixture happens to carry.
dyn_overlay_ver_after=$(grep -m1 '^pkgver=' "$dyn/packages/cachy-omarchy-overlay/PKGBUILD" | cut -d= -f2 | tr -d "'\"")
assert_eq "$dyn_overlay_ver_after" "$dyn_overlay_ver_before" "overlay version remains independent"
dyn_overlay_rel=$(grep -m1 '^pkgrel=' "$dyn/packages/cachy-omarchy-overlay/PKGBUILD" | cut -d= -f2 | tr -d "'\"")
assert_contains "$dynamic_manifest" "cachy-omarchy-overlay-${dyn_overlay_ver_after}-${dyn_overlay_rel}-any.pkg.tar.zst" "dynamic overlay artifact name is used"

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
assert_contains "$(cat "$paclog")" "$shell_artifact_v400" "U09 installs exact current shell"
assert_eq "$(cat "$prior/artifacts/$old_shell")" "old-shell" "U09 previous shell remains archived"
assert_eq "$(cat "$prior/artifacts/$old_overlay")" "old-overlay" "U09 previous overlay remains archived"
assert_file_exists "$COO_TEST_SANDBOX/state/installed-build.manifest" "U09 finalizes installed build pointer"
code=0
out=$(run_rc_doctor "$COO_TEST_SANDBOX/state") || code=$?
assert_eq "$code" "0" "U09 installed pair is doctor-healthy"
assert_contains "$out" "PASS: installed artifact/manifest (4.0.0" "U09 doctor reads installed pair"
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
assert_contains "$(cat "$COO_TEST_SANDBOX/state/installed-build.manifest")" "OMARCHY_VERSION=3.9.9" "U10 rollback records the installed prior pair"
code=0
out=$(run_rc_doctor "$COO_TEST_SANDBOX/state") || code=$?
assert_eq "$code" "0" "U10 rolled-back pair is doctor-healthy"
assert_contains "$out" "PASS: installed artifact/manifest (3.9.9" "U10 doctor reflects rolled-back pair"

# Privilege handling (release-blocking defect): install-packages/rollback must
# elevate only the pacman transaction (SPEC §37's documented `sudo pacman -U
# ...`), never require the whole script to run as root. Before the fix,
# "$pacman_bin" -U ... was a single literal word "pacman" with no sudo
# involved at all, so this asserts the *shape* of the constructed command --
# not merely that the script exits 0 -- which is exactly what the old code
# fails to produce. $fake is prepended to PATH for these calls; every other
# fake tool in it is a transparent pass-through by default (see fake/mv,
# fake/install, fake/sha256sum above), so only "sudo" resolution is actually
# exercised here. Must run before update-upstream/bump-pkgrel below mutate
# $root's checkout out from under this pinned validated-build.manifest.
priv_state=$COO_TEST_SANDBOX/priv-state
cp -a "$COO_TEST_SANDBOX/state" "$priv_state"
mapfile -t priv_artifacts < <(sed -n 's/^ARTIFACT=\([^ ]*\) .*/\1/p' "$priv_state/validated-build.manifest")
assert_eq "${#priv_artifacts[@]}" "2" "privilege fixture manifest names exactly two artifacts"

sudo_log=$COO_TEST_SANDBOX/sudo.log
: >"$sudo_log"
code=0
out=$(COO_REPO_ROOT="$root" COO_STATE_DIR="$priv_state" COO_SUDO_LOG="$sudo_log" PATH="$fake:$PATH" "$root/bin/install-packages" --install 2>&1) || code=$?
assert_eq "$code" "0" "install-packages succeeds as a normal user with no COO_PACMAN_BIN override"
sudo_line=$(cat "$sudo_log")
assert_contains "$sudo_line" "sudo pacman -U" "install-packages elevates only the pacman transaction via sudo"
assert_contains "$sudo_line" "${priv_artifacts[0]}" "sudo pacman invocation names the current shell artifact"
assert_contains "$sudo_line" "${priv_artifacts[1]}" "sudo pacman invocation names the current overlay artifact"

# COO_PACMAN_BIN must still bypass sudo entirely and unchanged (five other
# call sites in this file rely on exactly this override behavior).
priv_state_override=$COO_TEST_SANDBOX/priv-state-override
cp -a "$COO_TEST_SANDBOX/state" "$priv_state_override"
: >"$sudo_log"
: >"$paclog"
COO_REPO_ROOT="$root" COO_STATE_DIR="$priv_state_override" COO_PACMAN_BIN="$fake/pacman" COO_PACMAN_LOG="$paclog" COO_SUDO_LOG="$sudo_log" PATH="$fake:$PATH" "$root/bin/install-packages" --install >/dev/null
assert_eq "$(wc -l <"$sudo_log")" "0" "COO_PACMAN_BIN override never touches sudo"
assert_contains "$(cat "$paclog")" "-U" "COO_PACMAN_BIN override still invokes pacman directly"

# rollback must exhibit the same elevation shape as install-packages.
priv_rollback_state=$COO_TEST_SANDBOX/priv-rollback-state
cp -a "$COO_TEST_SANDBOX/state" "$priv_rollback_state"
: >"$sudo_log"
code=0
out=$(COO_REPO_ROOT="$root" COO_STATE_DIR="$priv_rollback_state" COO_SUDO_LOG="$sudo_log" PATH="$fake:$PATH" "$root/bin/rollback" 2>&1) || code=$?
assert_eq "$code" "0" "rollback succeeds as a normal user with no COO_PACMAN_BIN override"
assert_contains "$(cat "$sudo_log")" "sudo pacman -U" "rollback elevates only the pacman transaction via sudo"

# M7 follow-up: rollback finalization failure is ambiguous after pacman, so its
# pending marker must block all later package-manager actions and doctor must
# fail closed rather than trusting the previous installed pointer.
rollback_pending_state=$COO_TEST_SANDBOX/rollback-pending-state
cp -a "$COO_TEST_SANDBOX/state" "$rollback_pending_state"
rm -f "$rollback_pending_state/install-pending.manifest"
: >"$paclog"
code=0
out=$(COO_REPO_ROOT="$root" COO_STATE_DIR="$rollback_pending_state" COO_PACMAN_BIN="$fake/pacman" COO_PACMAN_LOG="$paclog" COO_MV_BIN="$fake/mv" COO_FAKE_INSTALLED_MV_FAIL=1 "$root/bin/rollback" 2>&1) || code=$?
assert_eq "$code" "14" "rollback finalization failure is reported"
assert_eq "$(wc -l <"$paclog")" "1" "rollback finalization failure ran pacman once"
assert_file_exists "$rollback_pending_state/install-pending.manifest" "rollback finalization failure retains pending marker"
code=0
out=$(run_rc_doctor "$rollback_pending_state") || code=$?
assert_eq "$code" "1" "rollback pending state fails doctor"
assert_contains "$out" "FAIL: incomplete install state" "rollback pending state is explicit"
: >"$paclog"
code=0
out=$(COO_REPO_ROOT="$root" COO_STATE_DIR="$rollback_pending_state" COO_PACMAN_BIN="$fake/pacman" COO_PACMAN_LOG="$paclog" "$root/bin/install-packages" --install 2>&1) || code=$?
assert_eq "$code" "1" "rollback pending state blocks install"
assert_eq "$(wc -l <"$paclog")" "0" "rollback pending install invokes no pacman"
code=0
out=$(COO_REPO_ROOT="$root" COO_STATE_DIR="$rollback_pending_state" COO_PACMAN_BIN="$fake/pacman" COO_PACMAN_LOG="$paclog" "$root/bin/rollback" 2>&1) || code=$?
assert_eq "$code" "1" "rollback pending state blocks another rollback"
assert_eq "$(wc -l <"$paclog")" "0" "rollback pending rollback invokes no pacman"

# Dangling state pointers count as state that cannot be trusted, not absence.
# The fixture validates both the pending guard and installed pointer before any
# fake pacman invocation.
dangling_state=$COO_TEST_SANDBOX/dangling-state
cp -a "$COO_TEST_SANDBOX/state" "$dangling_state"
rm -f "$dangling_state/install-pending.manifest"
ln -s missing-pending.manifest "$dangling_state/install-pending.manifest"
code=0
out=$(run_rc_doctor "$dangling_state") || code=$?
assert_eq "$code" "1" "dangling pending marker fails doctor"
assert_contains "$out" "FAIL: incomplete install state" "dangling pending marker is explicit"
: >"$paclog"
code=0
out=$(COO_REPO_ROOT="$root" COO_STATE_DIR="$dangling_state" COO_PACMAN_BIN="$fake/pacman" COO_PACMAN_LOG="$paclog" "$root/bin/install-packages" --install 2>&1) || code=$?
assert_eq "$code" "1" "dangling pending marker blocks install"
assert_eq "$(wc -l <"$paclog")" "0" "dangling pending install invokes no pacman"
code=0
out=$(COO_REPO_ROOT="$root" COO_STATE_DIR="$dangling_state" COO_PACMAN_BIN="$fake/pacman" COO_PACMAN_LOG="$paclog" "$root/bin/rollback" 2>&1) || code=$?
assert_eq "$code" "1" "dangling pending marker blocks rollback"
assert_eq "$(wc -l <"$paclog")" "0" "dangling pending rollback invokes no pacman"
rm -f "$dangling_state/install-pending.manifest" "$dangling_state/installed-build.manifest"
ln -s missing-installed.manifest "$dangling_state/installed-build.manifest"
code=0
out=$(run_rc_doctor "$dangling_state") || code=$?
assert_eq "$code" "1" "dangling installed pointer fails doctor"
assert_contains "$out" "FAIL: installed artifact/manifest mismatch" "dangling installed pointer is explicit"
: >"$paclog"
code=0
out=$(COO_REPO_ROOT="$root" COO_STATE_DIR="$dangling_state" COO_PACMAN_BIN="$fake/pacman" COO_PACMAN_LOG="$paclog" "$root/bin/install-packages" --install 2>&1) || code=$?
assert_eq "$code" "1" "dangling installed pointer blocks install"
assert_eq "$(wc -l <"$paclog")" "0" "dangling installed pointer invokes no pacman"

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
# Its caller source deliberately remains on the old pin. The candidate must
# fetch the newly discovered tag rather than copying COO_OMARCHY_GIT verbatim.
old_source_fixture=$COO_TEST_SANDBOX/old-source-fixture
mkdir -p "$old_source_fixture"
git init -q "$old_source_fixture"
printf 'old upstream fixture\n' >"$old_source_fixture/old-source-marker"
git -C "$old_source_fixture" add old-source-marker
git -C "$old_source_fixture" -c user.email=fixture@example.invalid -c user.name=fixture -c commit.gpgsign=false \
  commit -q -m 'old pin fixture'
old_source_commit=$(git -C "$old_source_fixture" rev-parse HEAD)
assert_eq "$(git -C "$old_source_fixture" rev-parse HEAD)" "$old_source_commit" "U02 caller source stays at old fixture commit"
if [[ $old_source_commit == "$fixture_commit" ]]; then
  printf 'FAIL: U02 caller source differs from the newly discovered commit\n'
  ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
else
  printf 'ok:   U02 caller source differs from the newly discovered commit\n'
fi

update_state=$COO_TEST_SANDBOX/update-state
update_build=$COO_TEST_SANDBOX/update-build
pac_update=$COO_TEST_SANDBOX/update-pacman.log
candidate_source_log=$COO_TEST_SANDBOX/candidate-source.log
: >"$pac_update"
: >"$candidate_source_log"
# "Independent" means this shell-only upstream update leaves the overlay's
# own pkgver exactly as it was beforehand -- capture that here, immediately
# before the call, and compare it to itself afterward. A literal like
# "pkgver=0.1.0" would only ever test that the fixture happens to still
# carry that value, and would fail on every legitimate overlay release even
# though nothing about independence changed.
overlay_pkgver_before_update=$(grep -m1 '^pkgver=' "$root/packages/cachy-omarchy-overlay/PKGBUILD")
code=0
out=$(WAYLAND_DISPLAY= COO_UPDATE_PIPELINE_NESTED=1 COO_REPO_ROOT="$root" COO_GIT_BIN="$fake/git" COO_STATE_DIR="$update_state" COO_BUILD_DIR="$update_build" COO_OMARCHY_GIT="$old_source_fixture" COO_EXPECT_UPSTREAM_COMMIT="$fixture_commit" COO_CANDIDATE_SOURCE_LOG="$candidate_source_log" COO_TOOL_LOG="$log" COO_MAKEPKG_BIN="$fake/makepkg" COO_BSDTAR_BIN="$fake/bsdtar" COO_FAKE_SHELL_ARTIFACT="$u02_shell_fixture" COO_FAKE_OVERLAY_ARTIFACT="$u02_overlay_fixture" COO_PACMAN_BIN="$fake/pacman" COO_PACMAN_LOG="$pac_update" "$root/bin/update-upstream" 2>&1) || code=$?
assert_eq "$code" "0" "U02 update validates and publishes candidate"
assert_eq "$(sort -u "$candidate_source_log")" "$fixture_commit" "U02 candidate build uses the newly discovered commit"
assert_contains "$out" "PASS tests/runtime/test_m3_docs.sh" "candidate default suite runs M3 docs test"
assert_contains "$out" "PASS tests/package/test_package_files.sh" "candidate default suite reaches package files test"
assert_contains "$out" "PASS tests/runtime/test_support_contract.sh" "candidate default suite reaches support contract test"
updated_lock=$(cat "$root/upstream.lock")
updated_pkg=$(cat "$root/packages/cachy-omarchy-shell/PKGBUILD")
assert_contains "$updated_lock" "OMARCHY_VERSION=4.0.1" "U02 lock version updates"
assert_contains "$updated_lock" "OMARCHY_COMMIT=$fixture_commit" "U02 lock uses peeled commit"
assert_contains "$updated_lock" "OMARCHY_TAG=v4.0.1" "U02 lock tag updates"
assert_contains "$updated_pkg" "pkgver=4.0.1" "U03 shell pkgver updates"
assert_contains "$updated_pkg" "pkgrel=1" "U03 pkgrel resets to one"
assert_contains "$updated_pkg" "_commit='$fixture_commit'" "U02 shell commit updates"
# The happy path alone only proves regeneration ran, not that it published
# what it actually read from the pinned tree -- the one thing the
# implementer's own comment (bin/update-upstream) calls the step's single
# forbidden failure mode: publishing a list that was not read from the
# pinned commit. Assert both the header and the exact name set against the
# fixture repository's real bin/ contents.
updated_inventory=$(cat "$root/tests/data/upstream-helpers.txt")
assert_contains "$updated_inventory" "# commit: $fixture_commit" "U02 inventory header moves to the new pin"
inventory_names_actual=$(grep -v '^#' "$root/tests/data/upstream-helpers.txt" | grep -v '^[[:space:]]*$')
expected_fixture_names=$(printf '%s
' omarchy omarchy-battery-status omarchy-menu omarchy-theme-set omarchy-weather-status | LC_ALL=C sort)
assert_eq "$inventory_names_actual" "$expected_fixture_names" "U02 inventory content is exactly the fixture repository's real bin/ tree"
assert_eq "$(grep -m1 '^pkgver=' "$root/packages/cachy-omarchy-overlay/PKGBUILD")" "$overlay_pkgver_before_update" "U02 overlay version is independent"
assert_eq "$(wc -l <"$pac_update")" "0" "U02 update never invokes pacman"
assert_contains "$out" "UPSTREAM.md requires human" "UPSTREAM.md deferred with explicit reason"

# M7 U02 linkage: a successful candidate update leaves a checksum-valid
# manifest that the read-only doctor reports as healthy.  It is not installed.
code=0
out=$(run_rc_doctor "$update_state") || code=$?
assert_eq "$code" "0" "U02 update manifest is doctor-healthy"
assert_contains "$out" "PASS: validated artifact/manifest (4.0.1" "U02 doctor reads updated manifest"
assert_contains "$out" "WARN: installed artifact/manifest not present" "U02 doctor distinguishes uninstalled build"

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
  sed -i "s/OMARCHY_VERSION=4\.0\.1/OMARCHY_VERSION=4.0.0/; s/OMARCHY_COMMIT=$fixture_commit/OMARCHY_COMMIT=f0020448ca87329199de7cb12f2015ebc4a3e5e7/; s/OMARCHY_TAG=v4\.0\.1/OMARCHY_TAG=v4.0.0/" "$failroot/upstream.lock"
  sed -i "s/pkgver=4.0.1/pkgver=4.0.0/; s/pkgrel=2/pkgrel=1/; s/_commit='$fixture_commit'/_commit='f0020448ca87329199de7cb12f2015ebc4a3e5e7'/" "$failroot/packages/cachy-omarchy-shell/PKGBUILD"
  before_lock=$(sha256sum "$failroot/upstream.lock")
  before_pkg=$(sha256sum "$failroot/packages/cachy-omarchy-shell/PKGBUILD")
  fail_pac=$COO_TEST_SANDBOX/fail-$mode-pacman.log
  : >"$fail_pac"
  envs=(COO_REPO_ROOT="$failroot" COO_GIT_BIN="$fake/git" COO_STATE_DIR="$COO_TEST_SANDBOX/fail-$mode-state" COO_BUILD_DIR="$COO_TEST_SANDBOX/fail-$mode-build" COO_TOOL_LOG="$log" COO_MAKEPKG_BIN="$fake/makepkg" COO_BSDTAR_BIN="$fake/bsdtar" COO_TEST_RUNNER="$fake/test-runner" COO_PACMAN_BIN="$fake/pacman" COO_PACMAN_LOG="$fail_pac")
  # Exit code alone is not proof of *which* stage failed -- fix round 2 found
  # this file trusting a bare "exit 1" from three different stages at once,
  # passing even when the earlier inventory-fetch step aborted before ever
  # reaching patch/audit/test. Each mode also gets a text marker that only
  # its own real failure path can produce, so a regression that short-circuits
  # earlier (same exit code, wrong reason) fails this line instead of hiding
  # behind the coincidence.
  case $mode in
    patch) envs+=(COO_PATCH_FAIL=1); update_id=U05; expected_code=1
      expected_evidence='patch application failed' ;;
    build) envs+=(COO_FAKE_BUILD_FAIL=1); update_id=U06; expected_code=7
      expected_evidence='fake-makepkg: forced build failure' ;;
    audit) envs+=(COO_FAKE_AUDIT_FAIL=1); update_id=U07; expected_code=1
      expected_evidence='archive audit failed' ;;
    test) envs+=(COO_FAKE_TEST_MODE=skip); update_id=U08; expected_code=1
      expected_evidence='test runner skipped required coverage' ;;
  esac
  code=0
  out=$(env "${envs[@]}" "$failroot/bin/update-upstream" 2>&1) || code=$?
  assert_eq "$code" "$expected_code" "$update_id $mode failure blocks publish"
  assert_contains "$out" "$expected_evidence" "$update_id $mode failure fails at its own stage, not earlier"
  assert_eq "$(sha256sum "$failroot/upstream.lock")" "$before_lock" "U$mode failure preserves lock"
  assert_eq "$(sha256sum "$failroot/packages/cachy-omarchy-shell/PKGBUILD")" "$before_pkg" "U$mode failure preserves PKGBUILD"
  assert_eq "$(wc -l <"$fail_pac")" "0" "U$mode failure invokes no pacman"
done

# Metadata publication is a transaction boundary: a failed second rename must
# leave both tracked inputs and the old authoritative pointer/release intact.
pubroot=$COO_TEST_SANDBOX/metadata-publish-repo
cp -a "$root" "$pubroot"
sed -i "s/OMARCHY_VERSION=4\.0\.1/OMARCHY_VERSION=4.0.0/; s/OMARCHY_COMMIT=$fixture_commit/OMARCHY_COMMIT=f0020448ca87329199de7cb12f2015ebc4a3e5e7/; s/OMARCHY_TAG=v4\.0\.1/OMARCHY_TAG=v4.0.0/" "$pubroot/upstream.lock"
sed -i "s/pkgver=4.0.1/pkgver=4.0.0/; s/pkgrel=2/pkgrel=1/; s/_commit='$fixture_commit'/_commit='f0020448ca87329199de7cb12f2015ebc4a3e5e7'/" "$pubroot/packages/cachy-omarchy-shell/PKGBUILD"
pub_state=$COO_TEST_SANDBOX/metadata-publish-state
cp -a "$COO_TEST_SANDBOX/state" "$pub_state"
pub_lock_before=$(sha256sum "$pubroot/upstream.lock")
pub_pkg_before=$(sha256sum "$pubroot/packages/cachy-omarchy-shell/PKGBUILD")
pub_pointer_before=$(cat "$pub_state/validated-build.manifest")
pub_old_release=$(awk -F= '$1 == "RELEASE" { print $2; exit }' "$pub_state/validated-build.manifest")
code=0
out=$(COO_REPO_ROOT="$pubroot" COO_GIT_BIN="$fake/git" COO_STATE_DIR="$pub_state" COO_BUILD_DIR="$COO_TEST_SANDBOX/metadata-publish-build" COO_TOOL_LOG="$log" COO_MAKEPKG_BIN="$fake/makepkg" COO_BSDTAR_BIN="$fake/bsdtar" COO_TEST_RUNNER="$fake/test-runner" COO_MV_BIN="$fake/mv" COO_FAKE_METADATA_PKG_MV_FAIL=1 "$pubroot/bin/update-upstream" 2>&1) || code=$?
assert_eq "$code" "1" "metadata second rename failure aborts update"
# Same reasoning as the U05-U08 loop: exit 1 alone does not distinguish this
# from an earlier, unrelated abort (e.g. the inventory fetch failing first).
assert_contains "$out" "could not publish shell PKGBUILD; upstream.lock restored" \
  "metadata second rename failure fails at its own stage, not earlier"
assert_eq "$(sha256sum "$pubroot/upstream.lock")" "$pub_lock_before" "metadata failure restores lock"
assert_eq "$(sha256sum "$pubroot/packages/cachy-omarchy-shell/PKGBUILD")" "$pub_pkg_before" "metadata failure preserves PKGBUILD"
assert_eq "$(cat "$pub_state/validated-build.manifest")" "$pub_pointer_before" "metadata failure preserves old manifest pointer"
assert_file_exists "$pub_state/$pub_old_release/artifacts/$shell_artifact_v400" "metadata failure preserves old referenced release"

# A pacman-success/final-pointer-failure state is explicitly pending. Neither
# a new install nor rollback may trust the stale installed pointer afterwards.
postroot=$COO_TEST_SANDBOX/post-pacman-repo
cp -a "$root" "$postroot"
sed -i "s/OMARCHY_VERSION=4\.0\.1/OMARCHY_VERSION=4.0.0/; s/OMARCHY_COMMIT=$fixture_commit/OMARCHY_COMMIT=f0020448ca87329199de7cb12f2015ebc4a3e5e7/; s/OMARCHY_TAG=v4\.0\.1/OMARCHY_TAG=v4.0.0/" "$postroot/upstream.lock"
# poststate below still carries the never-touched original validated
# manifest from the very first build (pinned to shell_pkgrel_pin), so
# postroot's checkout must reconstruct that exact pin -- a hardcoded "1"
# here would silently diverge from it and break install-packages'
# cross-check between the manifest and this checkout.
sed -i "s/pkgver=4.0.1/pkgver=4.0.0/; s/pkgrel=2/pkgrel=${shell_pkgrel_pin}/; s/_commit='$fixture_commit'/_commit='f0020448ca87329199de7cb12f2015ebc4a3e5e7'/" "$postroot/packages/cachy-omarchy-shell/PKGBUILD"
poststate=$COO_TEST_SANDBOX/post-pacman-state
cp -a "$COO_TEST_SANDBOX/state" "$poststate"
: >"$paclog"
code=0
out=$(COO_REPO_ROOT="$postroot" COO_STATE_DIR="$poststate" COO_PACMAN_BIN="$fake/pacman" COO_PACMAN_LOG="$paclog" COO_MV_BIN="$fake/mv" COO_FAKE_INSTALLED_MV_FAIL=1 "$postroot/bin/install-packages" --install 2>&1) || code=$?
assert_eq "$code" "14" "post-pacman installed pointer failure is reported"
assert_file_exists "$poststate/install-pending.manifest" "post-pacman failure leaves explicit pending state"
assert_eq "$(wc -l <"$paclog")" "1" "post-pacman failure ran pacman exactly once"
code=0
out=$(run_rc_doctor "$poststate") || code=$?
assert_eq "$code" "1" "pending post-pacman state fails doctor"
assert_contains "$out" "FAIL: incomplete install state" "pending doctor diagnosis requires operator recovery"
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
