#!/usr/bin/env bash
# bin/check-upstream, bin/update-upstream and bin/bump-pkgrel against a
# disposable repository and a disposable local "upstream". Faked: `git
# ls-remote --tags` and fetch failure injection (a test cannot ask a real
# remote what it advertises), makepkg, bsdtar and the test runner. Every other
# git call is real. No network, pacman or sudo.
set -euo pipefail
# update-upstream hands these to the suite it runs, which includes this test
# when it is run for real; they must never steer the fixture at the real repo.
unset COO_OMARCHY_GIT COO_BUILD_DIR COO_REPO_ROOT
source "$(dirname "${BASH_SOURCE[0]}")/../lib/assert.sh"

pin_ver=$(awk -F= '$1 == "OMARCHY_VERSION" { print $2; exit }' "$REPO_ROOT/upstream.lock")
pin_commit=$(awk -F= '$1 == "OMARCHY_COMMIT" { print $2; exit }' "$REPO_ROOT/upstream.lock")
[[ $pin_ver =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && $pin_commit =~ ^[0-9a-f]{40}$ ]] || {
  printf 'error: cannot read the current pin from upstream.lock: %s %s\n' "$pin_ver" "$pin_commit" >&2
  exit 1
}
# The advertised "newer" tag is the pin's patch+1, so it is always above the pin.
next_ver=$(awk -F. '{ printf "%s.%s.%s\n", $1, $2, $3 + 1 }' <<<"$pin_ver")
ident=(-c user.email=fixture@example.invalid -c user.name=fixture -c commit.gpgsign=false)

# --- disposable upstream: an old commit (the pin) and a newer one ---
upstream=$COO_TEST_SANDBOX/upstream-fixture
mkdir -p "$upstream/bin"
git init -q "$upstream"
printf '#!/usr/bin/env bash\n# old\n' >"$upstream/bin/omarchy"
git -C "$upstream" add -A
git -C "$upstream" "${ident[@]}" commit -q -m "v$pin_ver fixture"
old_commit=$(git -C "$upstream" rev-parse HEAD)
printf '#!/usr/bin/env bash\n# new\n' >"$upstream/bin/omarchy-new-helper"
git -C "$upstream" add -A
git -C "$upstream" "${ident[@]}" commit -q -m "v$next_ver fixture"
new_commit=$(git -C "$upstream" rev-parse HEAD)

# --- disposable repository: the files the commands under test read ---
root=$COO_TEST_SANDBOX/repo
mkdir -p "$root/packages/cachy-omarchy-shell" "$root/packages/cachy-omarchy-overlay"
cp -a "$REPO_ROOT/bin" "$root/bin"
cp -a "$REPO_ROOT/lib" "$root/lib"
cp "$REPO_ROOT/packages/cachy-omarchy-shell/PKGBUILD" "$root/packages/cachy-omarchy-shell/"
cp "$REPO_ROOT/packages/cachy-omarchy-overlay/PKGBUILD" "$root/packages/cachy-omarchy-overlay/"
cp "$REPO_ROOT/README.md" "$REPO_ROOT/README.ko-KR.md" "$root/"
sed -e "s#^OMARCHY_REPOSITORY=.*#OMARCHY_REPOSITORY=file://$upstream#" \
    -e "s#^OMARCHY_COMMIT=.*#OMARCHY_COMMIT=$old_commit#" "$REPO_ROOT/upstream.lock" >"$root/upstream.lock"
sed -i -e "s/^_commit=.*/_commit='$old_commit'/" -e 's/^pkgrel=.*/pkgrel=5/' "$root/packages/cachy-omarchy-shell/PKGBUILD"
sed -i -E "s#^([|] \`cachy-omarchy-shell\` [|] )[^|]*[^| ] *[|]#\1$pin_ver-5 |#" "$root/README.md" "$root/README.ko-KR.md"
sed -i -e 's/^pkgver=.*/pkgver=0.9.9/' "$root/packages/cachy-omarchy-overlay/PKGBUILD"
chmod +x "$root"/bin/*
git init -q "$root"
printf 'build/\npackages/*/src/\npackages/*/pkg/\npackages/*/omarchy/\n' >"$root/.gitignore"
git -C "$root" add -A
git -C "$root" "${ident[@]}" commit -q -m fixture
fixture_head=$(git -C "$root" rev-parse HEAD)
reset_repo() {
  git -C "$root" reset -q --hard "$fixture_head"
  git -C "$root" clean -fdxq
  rm -rf "$root/build" "$root"/packages/*/{src,pkg,omarchy}
  git clone -q "$upstream" "$root/build/omarchy"
  git -C "$root/build/omarchy" checkout -q --detach "$old_commit"
}

# --- fake tools ---
fake=$COO_TEST_SANDBOX/fake
mkdir -p "$fake"
log=$COO_TEST_SANDBOX/tools.log
cat >"$fake/git" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == ls-remote && ${2:-} == --tags ]]; then
  if [[ ${COO_FAKE_NO_UPDATE:-0} == 1 ]]; then
    printf '%s\n' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa refs/tags/v__PIN_VER__'
    printf '%s\n' '__OLD__ refs/tags/v__PIN_VER__^{}'
    exit 0
  fi
  if [[ ${COO_FAKE_LIGHTWEIGHT:-0} == 1 ]]; then
    printf '%s\n' '__OLD__ refs/tags/v__PIN_VER__'
    printf '%s\n' '4444444444444444444444444444444444444444 refs/tags/v__NEXT_VER__'
    exit 0
  fi
  printf '%s\n' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa refs/tags/v__PIN_VER__'
  printf '%s\n' '__OLD__ refs/tags/v__PIN_VER__^{}'
  printf '%s\n' '1111111111111111111111111111111111111111 refs/tags/v__NEXT_VER__'
  printf '%s\n' '__NEW__ refs/tags/v__NEXT_VER__^{}'
  printf '%s\n' '3333333333333333333333333333333333333333 refs/tags/v3.9.9-rc1'
  exit 0
fi
if [[ ${COO_FAKE_FETCH_FAIL:-0} == 1 && ${3:-} == fetch ]]; then
  echo 'fake-git: forced fetch failure' >&2
  exit 128
fi
exec /usr/bin/git "$@"
EOF
sed -i "s/__OLD__/$old_commit/g; s/__NEW__/$new_commit/g; s/__PIN_VER__/$pin_ver/g; s/__NEXT_VER__/$next_ver/g" "$fake/git"
cat >"$fake/makepkg" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
head=$(/usr/bin/git -C "$COO_OMARCHY_GIT" rev-parse 'HEAD^{commit}')
printf '%s %s\n' "$(basename "$PWD")" "$head" >>"$COO_TOOL_LOG"
[[ ${COO_FAKE_BUILD_FAIL:-0} != 1 ]] || { echo 'fake-makepkg: forced build failure' >&2; exit 7; }
name=$(basename "$PWD")
ver=$(grep -m1 '^pkgver=' PKGBUILD | cut -d= -f2 | tr -d "'\"")
rel=$(grep -m1 '^pkgrel=' PKGBUILD | cut -d= -f2 | tr -d "'\"")
mkdir -p "$PKGDEST"
printf '%s\n' "$name-$ver-$rel" >"$PKGDEST/$name-$ver-$rel-any.pkg.tar.zst"
EOF
cat >"$fake/bsdtar" <<'EOF'
#!/usr/bin/env bash
if [[ ${COO_FAKE_AUDIT_FAIL:-0} == 1 ]]; then echo etc/os-release; else echo usr/share/cachy-omarchy/ok; fi
EOF
cat >"$fake/test-runner" <<'EOF'
#!/usr/bin/env bash
printf 'runner\n' >>"$COO_TOOL_LOG"
case ${COO_FAKE_TEST_MODE:-pass} in
  pass) printf 'all test coverage ran\n' ;;
  skip) printf 'skip: installed tree absent\n' ;;
  fail) printf 'FAIL: runtime\n'; exit 9 ;;
esac
EOF
chmod +x "$fake"/*

run_check() { env COO_REPO_ROOT="$root" COO_GIT_BIN="$fake/git" "$@" "$root/bin/check-upstream" 2>&1; }
run_update() {
  env COO_REPO_ROOT="$root" COO_GIT_BIN="$fake/git" COO_TOOL_LOG="$log" COO_MAKEPKG_BIN="$fake/makepkg" \
    COO_BSDTAR_BIN="$fake/bsdtar" COO_TEST_RUNNER="$fake/test-runner" \
    "$@" "$root/bin/update-upstream" 2>&1
}
seed_build() {
  mkdir -p "$root/build"
  printf 'old shell\n' >"$root/build/$shell_old"
  printf 'old overlay\n' >"$root/build/$overlay_art"
}
clone_head() { git -C "$root/build/omarchy" rev-parse HEAD; }
tracked_dirty() { git -C "$root" status --porcelain | wc -l; }
shell_new=cachy-omarchy-shell-$next_ver-1-any.pkg.tar.zst
shell_old=cachy-omarchy-shell-$pin_ver-5-any.pkg.tar.zst
overlay_art=cachy-omarchy-overlay-0.9.9-1-any.pkg.tar.zst

# --- check-upstream is read-only ---
reset_repo
out=$(run_check) && code=0 || code=$?
assert_eq "$code" "0" "check-upstream exits cleanly"
assert_contains "$out" "update available" "check-upstream reports an available update"
assert_contains "$out" "$new_commit" "check-upstream uses the annotated tag's peeled commit"
out=$(run_check COO_FAKE_LIGHTWEIGHT=1) && code=0 || code=$?
assert_contains "$out" "4444444444444444444444444444444444444444" "check-upstream uses a lightweight tag's direct commit"
assert_eq "$(tracked_dirty)" "0" "check-upstream leaves the repository clean"

# --- update-upstream: nothing to do ---
: >"$log"
out=$(run_update COO_FAKE_NO_UPDATE=1) && code=0 || code=$?
assert_eq "$code" "0" "update no-op exits cleanly"
assert_contains "$out" "up to date" "update reports up to date"
assert_eq "$(wc -l <"$log")" "0" "update no-op builds nothing"
assert_eq "$(clone_head)" "$old_commit" "update no-op leaves build/omarchy alone"

# --- update-upstream: success, in one run ---
reset_repo
mkdir -p "$root/packages/cachy-omarchy-shell/src/stale" "$root/packages/cachy-omarchy-shell/pkg" "$root/packages/cachy-omarchy-shell/omarchy"
: >"$log"
out=$(run_update) && code=0 || code=$?
assert_eq "$code" "0" "update succeeds in one run"
assert_contains "$out" "ready: Omarchy $next_ver $new_commit" "update reports the new pin"
assert_contains "$out" "UPSTREAM.md requires human" "update defers UPSTREAM.md to a human"
lock=$(cat "$root/upstream.lock"); pkg=$(cat "$root/packages/cachy-omarchy-shell/PKGBUILD")
assert_contains "$lock" "OMARCHY_VERSION=$next_ver" "lock version moves"
assert_contains "$lock" "OMARCHY_COMMIT=$new_commit" "lock uses the peeled commit"
assert_contains "$lock" "OMARCHY_TAG=v$next_ver" "lock tag moves"
assert_contains "$pkg" "pkgver=$next_ver" "shell pkgver moves"
assert_contains "$pkg" "pkgrel=1" "shell pkgrel resets to one"
assert_contains "$pkg" "_commit='$new_commit'" "shell _commit moves"
assert_eq "$(grep -m1 '^pkgver=' "$root/packages/cachy-omarchy-overlay/PKGBUILD")" "pkgver=0.9.9" "overlay version is independent"
assert_eq "$(clone_head)" "$new_commit" "build/omarchy is checked out at the new pin"
assert_eq "$(grep -c "cachy-omarchy-shell $new_commit" "$log")" "1" "the shell is built from the new commit"
assert_eq "$(grep -c '^runner$' "$log")" "1" "the suite runs once"
[[ -e $root/packages/cachy-omarchy-shell/src ]] && stale=1 || stale=0
assert_eq "$stale" "0" "makepkg's stale src cache is dropped"
assert_file_exists "$root/build/$shell_new" "the new shell artifact lands in build/"
assert_file_exists "$root/build/$overlay_art" "the overlay artifact lands in build/"
assert_eq "$(find "$root/build" -maxdepth 1 -name '*.pkg.tar.zst' | wc -l)" "2" "a fresh build leaves exactly two artifacts"
for readme in README.md README.ko-KR.md; do
  assert_contains "$(grep -F '`cachy-omarchy-shell` |' "$root/$readme" | head -1)" "| $next_ver-1 |" "$readme version row moves with the PKGBUILD"
done

# --- update-upstream: every failure stage reverts everything ---
for mode in fetch build audit test; do
  reset_repo
  seed_build
  : >"$log"
  case $mode in
    fetch) envs=(COO_FAKE_FETCH_FAIL=1); expected='could not fetch' ;;
    build) envs=(COO_FAKE_BUILD_FAIL=1); expected='fake-makepkg: forced build failure' ;;
    audit) envs=(COO_FAKE_AUDIT_FAIL=1); expected='archive audit failed' ;;
    test) envs=(COO_FAKE_TEST_MODE=skip); expected='test runner skipped required coverage' ;;
  esac
  out=$(run_update "${envs[@]}") && code=0 || code=$?
  [[ $code != 0 ]] && failed=1 || failed=0
  assert_eq "$failed" "1" "$mode failure exits nonzero"
  assert_contains "$out" "$expected" "$mode failure fails at its own stage"
  assert_contains "$out" "reverted:" "$mode failure reports the revert"
  assert_eq "$(tracked_dirty)" "0" "$mode failure leaves tracked files at HEAD"
  assert_eq "$(clone_head)" "$old_commit" "$mode failure returns build/omarchy to the old pin"
  [[ -e $root/build/$shell_new ]] && left=1 || left=0
  assert_eq "$left" "0" "$mode failure leaves no new-pin artifact"
  assert_eq "$(cat "$root/build/$shell_old")" "old shell" "$mode failure keeps the old shell artifact"
  assert_eq "$(cat "$root/build/$overlay_art")" "old overlay" "$mode failure puts the overwritten overlay artifact back"
  assert_eq "$(find "$root/packages/cachy-omarchy-shell" -maxdepth 1 \( -name src -o -name pkg -o -name omarchy \) | wc -l)" "0" "$mode failure drops makepkg's caches"
  assert_eq "$(git -C "$root" diff HEAD --stat -- README.md README.ko-KR.md | wc -l)" "0" "$mode failure restores the README tables"
done

# --- artifacts that did not exist before a failed run do not survive it ---
reset_repo
: >"$log"
out=$(run_update COO_FAKE_TEST_MODE=fail) && code=0 || code=$?
assert_eq "$code" "9" "a failed update with an empty build/ fails"
[[ -e $root/build/$overlay_art ]] && left=1 || left=0
assert_eq "$left" "0" "the overlay artifact the rejected run published is removed"

# --- the same version re-tagged to another commit is a new revision ---
reset_repo
seed_build
# the fake remote advertises the next version; pretend the pin already has it
sed -i "s#^OMARCHY_VERSION=.*#OMARCHY_VERSION=$next_ver#" "$root/upstream.lock"
sed -i -e "s/^pkgver=.*/pkgver=$next_ver/" "$root/packages/cachy-omarchy-shell/PKGBUILD"
sed -i -E "s#^([|] \`cachy-omarchy-shell\` [|] )[^|]*[^| ] *[|]#\1$next_ver-5 |#" "$root/README.md" "$root/README.ko-KR.md"
git -C "$root" "${ident[@]}" commit -q -am 'same version, other commit'
printf 'old shell\n' >"$root/build/cachy-omarchy-shell-$next_ver-5-any.pkg.tar.zst"
out=$(run_update) && code=0 || code=$?
assert_eq "$code" "0" "a re-tag of the pinned version updates"
assert_contains "$(cat "$root/packages/cachy-omarchy-shell/PKGBUILD")" "pkgrel=6" "a re-tag bumps pkgrel instead of reusing the file name"
assert_file_exists "$root/build/cachy-omarchy-shell-$next_ver-6-any.pkg.tar.zst" "the re-tag builds under a new file name"
reset_repo
seed_build
sed -i "s#^OMARCHY_COMMIT=.*#OMARCHY_COMMIT=$old_commit#;s#^OMARCHY_VERSION=.*#OMARCHY_VERSION=$next_ver#" "$root/upstream.lock"
sed -i -e "s/^pkgver=.*/pkgver=$next_ver/" "$root/packages/cachy-omarchy-shell/PKGBUILD"
sed -i -E "s#^([|] \`cachy-omarchy-shell\` [|] )[^|]*[^| ] *[|]#\1$next_ver-5 |#" "$root/README.md" "$root/README.ko-KR.md"
git -C "$root" "${ident[@]}" commit -q -am 'same version, other commit'
printf 'old shell\n' >"$root/build/cachy-omarchy-shell-$next_ver-5-any.pkg.tar.zst"
out=$(run_update COO_FAKE_TEST_MODE=fail) && code=0 || code=$?
assert_eq "$code" "9" "a failed re-tag update fails"
assert_eq "$(cat "$root/build/cachy-omarchy-shell-$next_ver-5-any.pkg.tar.zst")" "old shell" "a failed re-tag keeps the old artifact under its own name"
[[ -e $root/build/cachy-omarchy-shell-$next_ver-6-any.pkg.tar.zst ]] && left=1 || left=0
assert_eq "$left" "0" "a failed re-tag leaves no new revision behind"

# --- the runner's own exit code survives; --keep leaves the failed state ---
reset_repo
out=$(run_update COO_FAKE_TEST_MODE=fail) && code=0 || code=$?
assert_eq "$code" "9" "a failing suite propagates its exit code"
reset_repo
out=$(env COO_REPO_ROOT="$root" COO_GIT_BIN="$fake/git" COO_TOOL_LOG="$log" COO_MAKEPKG_BIN="$fake/makepkg" \
  COO_BSDTAR_BIN="$fake/bsdtar" COO_TEST_RUNNER="$fake/test-runner" \
  COO_FAKE_TEST_MODE=fail "$root/bin/update-upstream" --keep 2>&1) && code=0 || code=$?
assert_eq "$code" "9" "--keep still fails"
assert_contains "$out" "kept:" "--keep reports that nothing was reverted"
assert_contains "$(cat "$root/upstream.lock")" "OMARCHY_VERSION=$next_ver" "--keep leaves the moved lock"
assert_eq "$(clone_head)" "$new_commit" "--keep leaves build/omarchy at the new pin"
assert_contains "$out" "build/omarchy" "--keep says the clone stays at the new pin"
assert_contains "$(cat "$root/packages/cachy-omarchy-shell/PKGBUILD")" "pkgver=$next_ver" "--keep leaves the moved PKGBUILD"
assert_file_exists "$root/build/$shell_new" "--keep leaves the new artifact"

# --- a clone this run created does not outlive a failed run ---
reset_repo
rm -rf "$root/build/omarchy"
out=$(run_update COO_FAKE_BUILD_FAIL=1) && code=0 || code=$?
assert_eq "$code" "7" "a failed update with no prior clone fails"
[[ -e $root/build/omarchy ]] && left=1 || left=0
assert_eq "$left" "0" "the clone the run created is removed again"
assert_eq "$(tracked_dirty)" "0" "and the tracked files are back at HEAD"

# --- a missing clone is created; local edits to the moved files are refused ---
reset_repo
rm -rf "$root/build/omarchy"
out=$(run_update) && code=0 || code=$?
assert_eq "$code" "0" "update clones build/omarchy when it is missing"
assert_eq "$(clone_head)" "$new_commit" "the fresh clone is at the new pin"
reset_repo
printf '# local edit\n' >>"$root/upstream.lock"
out=$(run_update) && code=0 || code=$?
assert_eq "$code" "1" "update refuses uncommitted edits to the files it rewrites"
assert_contains "$out" "uncommitted changes" "the refusal names the reason"
assert_eq "$(clone_head)" "$old_commit" "the refusal touches nothing"
git -C "$root" checkout -q HEAD -- upstream.lock
printf '# local edit\n' >>"$root/packages/cachy-omarchy-shell/PKGBUILD"
out=$(run_update) && code=0 || code=$?
assert_eq "$code" "1" "update refuses uncommitted edits to the PKGBUILD"
git -C "$root" checkout -q HEAD -- packages/cachy-omarchy-shell/PKGBUILD
printf '# staged edit\n' >>"$root/README.md"
git -C "$root" add README.md
out=$(run_update) && code=0 || code=$?
assert_eq "$code" "1" "update refuses staged-only edits to a file it rewrites"
git -C "$root" reset -q HEAD -- README.md
git -C "$root" checkout -q HEAD -- README.md

# --- bump-pkgrel is an explicit local revision: no lock or version change ---
reset_repo
lock_before=$(sha256sum "$root/upstream.lock")
version_before=$(grep -m1 '^pkgver=' "$root/packages/cachy-omarchy-shell/PKGBUILD")
out=$(COO_REPO_ROOT="$root" "$root/bin/bump-pkgrel" 2>&1) && code=0 || code=$?
assert_eq "$code" "0" "bump-pkgrel exits cleanly"
assert_contains "$out" "5 -> 6" "bump-pkgrel reports the increment"
assert_eq "$(grep -m1 '^pkgrel=' "$root/packages/cachy-omarchy-shell/PKGBUILD")" "pkgrel=6" "bump-pkgrel increments only pkgrel"
assert_eq "$(grep -m1 '^pkgver=' "$root/packages/cachy-omarchy-shell/PKGBUILD")" "$version_before" "bump-pkgrel preserves pkgver"
assert_eq "$(sha256sum "$root/upstream.lock")" "$lock_before" "bump-pkgrel preserves the lock"

exit "$ASSERT_FAILURES"
