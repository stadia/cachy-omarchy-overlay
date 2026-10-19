#!/usr/bin/env bash
# bin/build-packages·test-packages·install-packages·rollback 을 가짜 도구로
# 검사한다. 네트워크·실제 pacman·sudo·makepkg 는 쓰지 않는다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
# update-upstream 의 후보 스위트는 바깥 테스트의 COO_PACMAN_BIN 등을 물려받는다.
# 물려받은 값이 sudo 경로 단언을 가로채지 않도록 지운다.
unset COO_PACMAN_BIN COO_PACMAN_LOG COO_SUDO_BIN COO_VERCMP_BIN COO_ROLLBACK_SMOKE_BIN COO_TEST_RUNNER

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
cat >"$fake/pacman" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == -Q ]]; then
  case ${2:-} in
    cachy-omarchy-shell) [[ -n ${COO_FAKE_Q_SHELL:-} ]] || exit 1; printf '%s %s\n' "$2" "$COO_FAKE_Q_SHELL" ;;
    cachy-omarchy-overlay) [[ -n ${COO_FAKE_Q_OVERLAY:-} ]] || exit 1; printf '%s %s\n' "$2" "$COO_FAKE_Q_OVERLAY" ;;
    *) exit 1 ;;
  esac
  exit 0
fi
printf '%s\n' "$*" >>"$COO_PACMAN_LOG"
EOF
cat >"$fake/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >>"$COO_SUDO_LOG"
EOF
cat >"$fake/test-runner" <<'EOF'
#!/usr/bin/env bash
printf 'runner\n' >>"$COO_RUNNER_LOG"
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

run_build() {
  COO_REPO_ROOT="$root" COO_BUILD_DIR="$build" COO_MAKEPKG_BIN="$fake/makepkg" \
    COO_BSDTAR_BIN="$fake/bsdtar" "$root/bin/build-packages" "$@" 2>&1
}

# --clean (makechrootpkg) 는 제거됐다. 깨끗한 환경 증명은 CI resolve lane 이 한다.
code=0
out=$(run_build --clean) || code=$?
assert_eq "$code" "2" "build-packages rejects removed --clean"
assert_contains "$out" "unknown argument: --clean" "removed --clean is reported as unknown"

paclog=$COO_TEST_SANDBOX/pacman.log
sudolog=$COO_TEST_SANDBOX/sudo.log
runnerlog=$COO_TEST_SANDBOX/runner.log
reset_logs() { : >"$paclog"; : >"$sudolog"; : >"$runnerlog"; }

# --- build-packages: build/ 에만 쓴다 ---
mkdir -p "$build"
printf 'old\n' >"$build/cachy-omarchy-shell-4.0.3-1-any.pkg.tar.zst"
code=0; out=$(run_build) || code=$?
assert_eq "$code" "0" "build succeeds"
assert_file_exists "$build/$shell_now" "build writes the current shell artifact"
assert_file_exists "$build/$overlay_now" "build writes the current overlay artifact"
assert_eq "$(cat "$build/cachy-omarchy-shell-4.0.3-1-any.pkg.tar.zst")" "old" "build keeps older artifacts for rollback"
[[ -e ${XDG_STATE_HOME:?}/cachy-omarchy ]] && state=1 || state=0
assert_eq "$state" "0" "build writes no state directory"

for mode in BUILD AUDIT EXTRA; do
  fresh=$COO_TEST_SANDBOX/build-$mode
  code=0
  out=$(env "COO_FAKE_${mode}_FAIL=1" COO_FAKE_EXTRA=$([[ $mode == EXTRA ]] && echo 1 || echo 0) \
    COO_REPO_ROOT="$root" COO_BUILD_DIR="$fresh" COO_MAKEPKG_BIN="$fake/makepkg" \
    COO_BSDTAR_BIN="$fake/bsdtar" "$root/bin/build-packages" 2>&1) || code=$?
  [[ $code != 0 ]] && failed=1 || failed=0
  assert_eq "$failed" "1" "build $mode failure exits nonzero"
  published=$(find "$fresh" -name '*.pkg.tar.zst' 2>/dev/null | wc -l)
  assert_eq "$published" "0" "build $mode failure publishes nothing"
done
assert_contains "$out" "ambiguous build artifacts" "extra artifact is reported as ambiguous"

# 두 번째 복사가 중간에 실패해도 build/ 에 현재 이름의 반쪽 파일이나 임시
# 파일이 남지 않아야 한다 (첫 번째 패키지도 게시되지 않는다).
cat >"$fake/install" <<'EOF2'
#!/usr/bin/env bash
dest=${!#}
src=${@: -2:1}
if [[ $dest == *cachy-omarchy-overlay-* ]]; then
  head -c 1 "$src" >"$dest"
  echo 'fake-install: forced write failure' >&2
  exit 5
fi
cp "$src" "$dest"
EOF2
chmod +x "$fake/install"
fresh=$COO_TEST_SANDBOX/build-INSTALL
code=0
out=$(COO_REPO_ROOT="$root" COO_BUILD_DIR="$fresh" COO_MAKEPKG_BIN="$fake/makepkg" \
  COO_BSDTAR_BIN="$fake/bsdtar" COO_INSTALL_BIN="$fake/install" "$root/bin/build-packages" 2>&1) || code=$?
[[ $code != 0 ]] && failed=1 || failed=0
assert_eq "$failed" "1" "build copy failure exits nonzero"
assert_eq "$(find "$fresh" -type f 2>/dev/null | wc -l)" "0" "build copy failure leaves no partial or temp file"

# --- test-packages: 현재 아티팩트가 있어야 러너를 부른다 ---
run_tests() {
  COO_REPO_ROOT="$root" COO_BUILD_DIR="$1" COO_TEST_RUNNER="$fake/test-runner" \
    COO_RUNNER_LOG="$runnerlog" "$root/bin/test-packages" 2>&1
}
reset_logs; code=0; out=$(run_tests "$COO_TEST_SANDBOX/empty-build") || code=$?
assert_eq "$code" "1" "test-packages missing artifact fails"
assert_contains "$out" "build artifact missing: $shell_now" "test-packages names the missing artifact"
assert_eq "$(wc -l <"$runnerlog")" "0" "test-packages missing artifact runs no tests"
reset_logs; code=0; out=$(COO_FAKE_TEST_MODE=skip run_tests "$build") || code=$?
assert_eq "$code" "1" "test-packages rejects an unexpected skip"
assert_contains "$out" "test runner skipped required coverage" "unexpected skip is explicit"
reset_logs; code=0; out=$(COO_FAKE_TEST_MODE=fail run_tests "$build") || code=$?
assert_eq "$code" "9" "test-packages propagates runner failure"
reset_logs; code=0; out=$(run_tests "$build") || code=$?
assert_eq "$code" "0" "test-packages passes on a green runner"
assert_contains "$out" "package tests passed" "test-packages reports success"

# --- install-packages: 현재 두 아티팩트만 설치한다 ---
run_install() {
  COO_REPO_ROOT="$root" COO_BUILD_DIR="$1" COO_PACMAN_BIN="$fake/pacman" \
    COO_PACMAN_LOG="$paclog" "$root/bin/install-packages" --install 2>&1
}
partial=$COO_TEST_SANDBOX/partial-build
mkdir -p "$partial"; cp "$build/$shell_now" "$partial/"
reset_logs; code=0; out=$(run_install "$partial") || code=$?
assert_eq "$code" "1" "install missing overlay fails"
assert_contains "$out" "build artifact missing: $overlay_now" "install names the missing artifact"
assert_eq "$(wc -l <"$paclog")" "0" "install missing overlay invokes no pacman"
reset_logs; code=0; out=$(run_install "$build") || code=$?
assert_eq "$code" "0" "install succeeds"
assert_eq "$(cat "$paclog")" "-U $build/$shell_now $build/$overlay_now" "install passes exactly the current pair"
code=0; out=$(COO_REPO_ROOT="$root" COO_BUILD_DIR="$build" COO_SUDO_LOG="$sudolog" PATH="$fake:$PATH" \
  "$root/bin/install-packages" --install 2>&1) || code=$?
assert_eq "$code" "0" "install as normal user succeeds"
assert_contains "$(cat "$sudolog")" "sudo pacman -U $build/$shell_now" "install elevates only the pacman transaction"
code=0; out=$(COO_REPO_ROOT="$root" COO_BUILD_DIR="$build" "$root/bin/install-packages" 2>&1) || code=$?
assert_eq "$code" "1" "install without --install refuses"

# --- rollback: 설치 버전보다 낮은 가장 새 build/ 아티팩트 ---
rb=$COO_TEST_SANDBOX/rollback-build
mkdir -p "$rb"
for f in cachy-omarchy-shell-4.0.2-1 cachy-omarchy-shell-4.0.9-1 cachy-omarchy-shell-4.0.10-1 \
         cachy-omarchy-overlay-0.2.0-1 cachy-omarchy-overlay-0.3.0-1; do
  : >"$rb/$f-any.pkg.tar.zst"
done
run_rollback() {
  COO_REPO_ROOT="$root" COO_BUILD_DIR="$rb" COO_PACMAN_BIN="$fake/pacman" \
    COO_PACMAN_LOG="$paclog" "$root/bin/rollback" 2>&1
}
reset_logs; code=0
out=$(COO_FAKE_Q_SHELL=4.0.10-1 COO_FAKE_Q_OVERLAY=0.3.0-1 COO_ROLLBACK_SMOKE_BIN="$fake/smoke" run_rollback) || code=$?
assert_eq "$code" "0" "rollback succeeds"
assert_eq "$(head -n1 "$paclog")" "-U $rb/cachy-omarchy-shell-4.0.9-1-any.pkg.tar.zst $rb/cachy-omarchy-overlay-0.2.0-1-any.pkg.tar.zst" \
  "rollback picks by vercmp"
assert_eq "$(tail -n1 "$paclog")" "smoke" "rollback smoke runs after pacman"
reset_logs; code=0
out=$(COO_FAKE_Q_SHELL=4.0.10-1 COO_FAKE_Q_OVERLAY=0.2.0-1 run_rollback) || code=$?
assert_eq "$code" "0" "rollback shell only succeeds"
assert_eq "$(cat "$paclog")" "-U $rb/cachy-omarchy-shell-4.0.9-1-any.pkg.tar.zst" "rollback shell only"
assert_contains "$out" "note: no older cachy-omarchy-overlay in build/" "rollback names the package it keeps"
reset_logs; code=0
out=$(COO_FAKE_Q_SHELL=4.0.2-1 COO_FAKE_Q_OVERLAY=0.2.0-1 run_rollback) || code=$?
assert_eq "$code" "1" "rollback nothing older fails"
assert_eq "$(wc -l <"$paclog")" "0" "rollback nothing older invokes no pacman"
reset_logs; code=0
out=$(COO_FAKE_Q_OVERLAY=0.3.0-1 run_rollback) || code=$?
assert_eq "$code" "1" "rollback not installed fails"
assert_contains "$out" "cachy-omarchy-shell is not installed" "rollback not installed is explicit"
assert_eq "$(wc -l <"$paclog")" "0" "rollback not installed invokes no pacman"
code=0; out=$(COO_FAKE_Q_SHELL=4.0.10-1 COO_FAKE_Q_OVERLAY=0.3.0-1 COO_REPO_ROOT="$root" COO_BUILD_DIR="$rb" \
  COO_SUDO_LOG="$sudolog" PATH="$fake:$PATH" "$root/bin/rollback" 2>&1) || code=$?
assert_eq "$code" "0" "rollback as normal user succeeds"
assert_contains "$(cat "$sudolog")" "sudo pacman -U" "rollback elevates only the pacman transaction"

# vercmp 가 없거나 실패하면 "더 낮은 버전 없음" 으로 뭉개지 말고 크게 실패한다.
reset_logs; code=0
out=$(COO_FAKE_Q_SHELL=4.0.10-1 COO_FAKE_Q_OVERLAY=0.3.0-1 COO_VERCMP_BIN="$fake/no-such-vercmp" run_rollback) || code=$?
assert_eq "$code" "1" "rollback without vercmp fails"
assert_contains "$out" "error: vercmp not found: $fake/no-such-vercmp" "missing vercmp is explicit"
assert_eq "$(wc -l <"$paclog")" "0" "rollback without vercmp invokes no pacman"
printf '#!/usr/bin/env bash\nexit 3\n' >"$fake/vercmp-fail"
printf '#!/usr/bin/env bash\necho newer\n' >"$fake/vercmp-junk"
chmod +x "$fake/vercmp-fail" "$fake/vercmp-junk"
for bad in vercmp-fail vercmp-junk; do
  reset_logs; code=0
  out=$(COO_FAKE_Q_SHELL=4.0.10-1 COO_FAKE_Q_OVERLAY=0.3.0-1 COO_VERCMP_BIN="$fake/$bad" run_rollback) || code=$?
  assert_eq "$code" "1" "rollback with $bad fails"
  assert_contains "$out" "error: vercmp failed" "$bad is explicit"
  assert_eq "$(wc -l <"$paclog")" "0" "rollback with $bad invokes no pacman"
done

exit "$ASSERT_FAILURES"
