#!/usr/bin/env bash
# update-upstream / check-upstream / bump-pkgrel pipeline: fake tools only, never network or pacman.
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

# 이 파일이 "현재 핀" 을 뜻할 때 쓰는 값은 upstream.lock 에서 읽는다. 핀을
# 옮기는 커맨드(bin/update-upstream)가 후보 트리에서 이 스위트를 그대로
# 돌리므로, 4.0.1 같은 리터럴을 박아 두면 핀 이동마다 이 파일이 같이 깨진다
# (4.0.3 핀 이동에서 실제로 5개 단언이 깨졌다 — 파이프라인 회귀가 아니라
# 리터럴이 낡은 것이었다). 픽스처가 "더 새 태그" 로 광고하는 버전은 핀의
# patch+1 로 파생한다: 광고 집합이 항상 핀보다 위에 있어야 update-upstream 이
# 실제로 이동 경로에 들어간다.
pin_ver=$(awk -F= '$1 == "OMARCHY_VERSION" { print $2; exit }' "$REPO_ROOT/upstream.lock")
pin_commit=$(awk -F= '$1 == "OMARCHY_COMMIT" { print $2; exit }' "$REPO_ROOT/upstream.lock")
next_ver=$(awk -F. '{ printf "%s.%s.%s\n", $1, $2, $3 + 1 }' <<<"$pin_ver")
[[ $pin_ver =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && $pin_commit =~ ^[0-9a-f]{40}$ ]] || {
  printf '%s\n' "error: upstream.lock 에서 현재 핀을 읽지 못했다: '$pin_ver' '$pin_commit'" >&2
  exit 1
}
# sed 스크립트에 넣는 버전 문자열은 정규식이므로 점을 이스케이프한다.
pin_ver_re=${pin_ver//./\\.}
next_ver_re=${next_ver//./\\.}

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
# worst (fix round 2 caught itself doing this). So the update target here is
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
# omarchy-weather-status 는 스텁으로 바꾸지 않는다: 후보 스위트의
# test_weather_helpers.sh 가 스테이징된 그대로 실행해 "Seoul · Temp 21°C"
# 출력을 기대하는데, 스텁은 아무것도 출력하지 않아 그 단언이 깨진다(4.0.1 핀
# 발행 때 실제로 깨짐). 커밋 전환 증명은 나머지 네 개 스텁으로 충분하다.
for helper in omarchy omarchy-menu omarchy-theme-set omarchy-battery-status; do
  printf '#!/usr/bin/env bash\n# fixture helper: %s\n' "$helper" >"$fixture_upstream/bin/$helper"
done
git init -q "$fixture_upstream"
git -C "$fixture_upstream" -c user.email=fixture@example.invalid -c user.name=fixture -c commit.gpgsign=false \
  add -A
git -C "$fixture_upstream" -c user.email=fixture@example.invalid -c user.name=fixture -c commit.gpgsign=false \
  commit -q -m "v$next_ver fixture"
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
  # __PIN_VER__ (the repo's pinned version) is annotated: direct ref is the tag
  if [[ ${COO_FAKE_NO_UPDATE:-0} == 1 ]]; then
    printf '%s\n' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa refs/tags/v__PIN_VER__'
    printf '%s\n' '__PIN_COMMIT__ refs/tags/v__PIN_VER__^{}'
    exit 0
  fi
  if [[ ${COO_FAKE_LIGHTWEIGHT:-0} == 1 ]]; then
    printf '%s\n' '__PIN_COMMIT__ refs/tags/v__PIN_VER__'
    printf '%s\n' '4444444444444444444444444444444444444444 refs/tags/v__NEXT_VER__'
    exit 0
  fi
  printf '%s\n' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa refs/tags/v__PIN_VER__'
  printf '%s\n' '__PIN_COMMIT__ refs/tags/v__PIN_VER__^{}'
  printf '%s\n' '1111111111111111111111111111111111111111 refs/tags/v__NEXT_VER__'
  printf '%s\n' '__FIXTURE_COMMIT__ refs/tags/v__NEXT_VER__^{}'
  printf '%s\n' '3333333333333333333333333333333333333333 refs/tags/v3.9.9'
  exit 0
fi
exec /usr/bin/git "$@"
EOF
sed -i "s/__FIXTURE_COMMIT__/$fixture_commit/; s/__PIN_COMMIT__/$pin_commit/g; s/__PIN_VER__/$pin_ver/g; s/__NEXT_VER__/$next_ver/g" "$fake/git"
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
cat >"$fake/mv" <<'EOF'
#!/usr/bin/env bash
if [[ ${COO_FAKE_METADATA_PKG_MV_FAIL:-0} == 1 && ${COO_UPDATE_METADATA_PUBLISH:-} == pkg ]]; then exit 13; fi
/usr/bin/mv "$@"
EOF
cat >"$fake/pacman" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$COO_PACMAN_LOG"
EOF
cat >"$fake/test-runner" <<'EOF'
#!/usr/bin/env bash
case ${COO_FAKE_TEST_MODE:-pass} in
  pass) printf 'all test coverage ran\n' ;;
  skip) printf 'skip: installed tree absent\n' ;;
  fail) printf 'FAIL: runtime\n'; exit 9 ;;
esac
EOF
chmod +x "$fake"/*

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
out=$(WAYLAND_DISPLAY= COO_UPDATE_PIPELINE_NESTED=1 COO_REPO_ROOT="$root" COO_GIT_BIN="$fake/git" COO_BUILD_DIR="$update_build" COO_OMARCHY_GIT="$old_source_fixture" COO_EXPECT_UPSTREAM_COMMIT="$fixture_commit" COO_CANDIDATE_SOURCE_LOG="$candidate_source_log" COO_TOOL_LOG="$log" COO_MAKEPKG_BIN="$fake/makepkg" COO_BSDTAR_BIN="$fake/bsdtar" COO_FAKE_SHELL_ARTIFACT="$u02_shell_fixture" COO_FAKE_OVERLAY_ARTIFACT="$u02_overlay_fixture" COO_PACMAN_BIN="$fake/pacman" COO_PACMAN_LOG="$pac_update" "$root/bin/update-upstream" 2>&1) || code=$?
assert_eq "$code" "0" "U02 update validates and publishes candidate"
# The nested candidate suite is the only record of why it rejected the pin.
(( code )) && printf '%s\n' "$out" | grep -E '^(FAIL|SKIP|skip:|error:|warn:)' | sed 's/^/      candidate: /'
assert_eq "$(sort -u "$candidate_source_log")" "$fixture_commit" "U02 candidate build uses the newly discovered commit"
assert_contains "$out" "PASS tests/runtime/test_wrapper.sh" "candidate default suite runs runtime wrapper test"
assert_contains "$out" "PASS tests/package/test_package_files.sh" "candidate default suite reaches package files test"
assert_contains "$out" "PASS tests/runtime/test_doctor.sh" "candidate default suite reaches doctor test"
updated_lock=$(cat "$root/upstream.lock")
updated_pkg=$(cat "$root/packages/cachy-omarchy-shell/PKGBUILD")
assert_contains "$updated_lock" "OMARCHY_VERSION=$next_ver" "U02 lock version updates"
assert_contains "$updated_lock" "OMARCHY_COMMIT=$fixture_commit" "U02 lock uses peeled commit"
assert_contains "$updated_lock" "OMARCHY_TAG=v$next_ver" "U02 lock tag updates"
assert_contains "$updated_pkg" "pkgver=$next_ver" "U03 shell pkgver updates"
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
# 기대 집합은 fixture repo 가 실제로 커밋한 bin/ 목록과 같아야 한다 —
# update-upstream 과 같은 의미론(ls-tree --name-only HEAD -- bin/)으로
# 동적으로 뽑는다. 이 fixture 는 핀된 업스트림 소스를 통째로 베낀 뒤 네 개
# 헬퍼만 스텁으로 덮어쓴 트리라 bin/ 이 진짜 전체 목록이다(4.0.1 발행 후보
# 스위트에서 U02 가 처음 끝까지 도달하면서, 하드코드된 5-이름 목록과의
# 불일치가 노출됐다). "인벤토리가 핀된 커밋의 트리를 실제로 읽었다" 는 것을
# 검증하는 것이 목적이지 이름 다섯 개를 검증하는 것이 아니다.
expected_fixture_names=$(git -C "$fixture_upstream" ls-tree --name-only HEAD -- bin/ | sed 's|^bin/||' | LC_ALL=C sort)
assert_eq "$inventory_names_actual" "$expected_fixture_names" "U02 inventory content is exactly the fixture repository's real bin/ tree"
assert_eq "$(grep -m1 '^pkgver=' "$root/packages/cachy-omarchy-overlay/PKGBUILD")" "$overlay_pkgver_before_update" "U02 overlay version is independent"
assert_eq "$(wc -l <"$pac_update")" "0" "U02 update never invokes pacman"
# The validated candidate artifacts are copied next to the older builds
# (bin/rollback installs from build/). Names come from the updated metadata.
u02_names=$(source "$root/bin/package-names.sh" && coo_current_artifacts "$root" &&
  printf '%s\n' "$COO_SHELL_ARTIFACT" "$COO_OVERLAY_ARTIFACT")
for name in $u02_names; do
  assert_file_exists "$update_build/$name" "U02 copies candidate artifact into build/: $name"
done
assert_eq "$(find "$update_build" -maxdepth 1 -type f -name '*.pkg.tar.zst' | wc -l)" "2" "U02 build/ receives exactly the two candidate artifacts"
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
  # U02 changed root to $next_ver; each failure fixture must start at the prior pin
  # so update-upstream actually enters its patch/build/audit/test stage.
  sed -i "s/OMARCHY_VERSION=$next_ver_re/OMARCHY_VERSION=$pin_ver/; s/OMARCHY_COMMIT=$fixture_commit/OMARCHY_COMMIT=$pin_commit/; s/OMARCHY_TAG=v$next_ver_re/OMARCHY_TAG=v$pin_ver/" "$failroot/upstream.lock"
  sed -i "s/pkgver=$next_ver_re/pkgver=$pin_ver/; s/pkgrel=2/pkgrel=1/; s/_commit='$fixture_commit'/_commit='$pin_commit'/" "$failroot/packages/cachy-omarchy-shell/PKGBUILD"
  before_lock=$(sha256sum "$failroot/upstream.lock")
  before_pkg=$(sha256sum "$failroot/packages/cachy-omarchy-shell/PKGBUILD")
  fail_pac=$COO_TEST_SANDBOX/fail-$mode-pacman.log
  : >"$fail_pac"
  envs=(COO_REPO_ROOT="$failroot" COO_GIT_BIN="$fake/git" COO_BUILD_DIR="$COO_TEST_SANDBOX/fail-$mode-build" COO_TOOL_LOG="$log" COO_MAKEPKG_BIN="$fake/makepkg" COO_BSDTAR_BIN="$fake/bsdtar" COO_TEST_RUNNER="$fake/test-runner" COO_PACMAN_BIN="$fake/pacman" COO_PACMAN_LOG="$fail_pac")
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
  assert_eq "$(find "$COO_TEST_SANDBOX/fail-$mode-build" -name '*.pkg.tar.zst' 2>/dev/null | wc -l)" "0" "U$mode failure copies no artifact into build/"
done

# Metadata publication is a transaction boundary: a failed second rename must leave both tracked inputs intact.
pubroot=$COO_TEST_SANDBOX/metadata-publish-repo
cp -a "$root" "$pubroot"
sed -i "s/OMARCHY_VERSION=$next_ver_re/OMARCHY_VERSION=$pin_ver/; s/OMARCHY_COMMIT=$fixture_commit/OMARCHY_COMMIT=$pin_commit/; s/OMARCHY_TAG=v$next_ver_re/OMARCHY_TAG=v$pin_ver/" "$pubroot/upstream.lock"
sed -i "s/pkgver=$next_ver_re/pkgver=$pin_ver/; s/pkgrel=2/pkgrel=1/; s/_commit='$fixture_commit'/_commit='$pin_commit'/" "$pubroot/packages/cachy-omarchy-shell/PKGBUILD"
pub_lock_before=$(sha256sum "$pubroot/upstream.lock")
pub_pkg_before=$(sha256sum "$pubroot/packages/cachy-omarchy-shell/PKGBUILD")
code=0
out=$(COO_REPO_ROOT="$pubroot" COO_GIT_BIN="$fake/git" COO_BUILD_DIR="$COO_TEST_SANDBOX/metadata-publish-build" COO_TOOL_LOG="$log" COO_MAKEPKG_BIN="$fake/makepkg" COO_BSDTAR_BIN="$fake/bsdtar" COO_TEST_RUNNER="$fake/test-runner" COO_MV_BIN="$fake/mv" COO_FAKE_METADATA_PKG_MV_FAIL=1 "$pubroot/bin/update-upstream" 2>&1) || code=$?
assert_eq "$code" "1" "metadata second rename failure aborts update"
# Same reasoning as the U05-U08 loop: exit 1 alone does not distinguish this
# from an earlier, unrelated abort (e.g. the inventory fetch failing first).
assert_contains "$out" "could not publish shell PKGBUILD; upstream.lock restored" \
  "metadata second rename failure fails at its own stage, not earlier"
assert_eq "$(sha256sum "$pubroot/upstream.lock")" "$pub_lock_before" "metadata failure restores lock"
assert_eq "$(sha256sum "$pubroot/packages/cachy-omarchy-shell/PKGBUILD")" "$pub_pkg_before" "metadata failure preserves PKGBUILD"

exit "$ASSERT_FAILURES"
