#!/usr/bin/env bash
# M7: cachy-omarchy-doctor must be read-only and fail closed for broken trees.
set -uo pipefail
source "$REPO_ROOT/tests/lib/assert.sh"

DOCTOR=$REPO_ROOT/overlay/bin/cachy-omarchy-doctor
assert_file_exists "$DOCTOR" "doctor command exists"
[[ -x $DOCTOR ]] || { echo "FAIL: doctor command is executable"; exit 1; }

root=$COO_TEST_SANDBOX/extracted
prefix=$root/usr/share/cachy-omarchy
compat=$root/usr/lib/cachy-omarchy/compat/bin
hypr=$COO_TEST_SANDBOX/hypr
config=$COO_TEST_SANDBOX/config
user_config=$COO_TEST_SANDBOX/user-omarchy
state=$COO_TEST_SANDBOX/state
fake_bin=$COO_TEST_SANDBOX/fake-bin
mkdir -p "$prefix/upstream/shell" "$prefix/upstream/default/omarchy" "$compat" \
  "$root/usr/bin" "$root/usr/lib/systemd/user" "$hypr" "$config" "$user_config" "$state" "$fake_bin"
printf '// fixture shell\n' >"$prefix/upstream/shell/shell.qml"
printf '{}\n' >"$prefix/upstream/default/omarchy/omarchy-menu.jsonc"
printf '[Unit]\n' >"$root/usr/lib/systemd/user/cachy-omarchy-shell.service"
printf '# no conflicting bindings\n' >"$hypr/hyprland.conf"
for cmd in cachy-omarchy-launcher cachy-omarchy-bindings cachy-omarchy-keybindings; do
  printf '#!/usr/bin/env bash\nexit 0\n' >"$root/usr/bin/$cmd"
  chmod +x "$root/usr/bin/$cmd"
done
cat >"$root/usr/bin/cachy-omarchy-shell" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == --ipc && ${2:-} == shell && ${3:-} == ping ]]; then
  [[ ${COO_FAKE_PING_FAIL:-0} == 1 ]] && exit 1
  printf 'ok\n'
fi
exit 0
EOF
chmod +x "$root/usr/bin/cachy-omarchy-shell"
printf '#!/usr/bin/env bash\nexit 0\n' >"$fake_bin/pgrep"
printf '#!/usr/bin/env bash\nexit 0\n' >"$fake_bin/qs"
chmod +x "$fake_bin/pgrep" "$fake_bin/qs"
printf '#!/usr/bin/env bash\nexit 0\n' >"$compat/omarchy-shell"
chmod +x "$compat/omarchy-shell"

run_doctor() {
  COO_PREFIX_ROOT="$prefix" COO_COMPAT_BIN="$compat" COO_HYPR_DIR="$hypr" \
    COO_CONFIG_DIR="$config" COO_OMARCHY_CONFIG_DIR="$user_config" COO_STATE_DIR="$state" "$DOCTOR" 2>&1
}

printf 'do not modify\n' >"$config/sentinel"
before=$(sha256sum "$config/sentinel" | awk '{print $1}')
out=$(run_doctor); code=$?
assert_eq "$code" 0 "healthy extracted tree passes"
assert_eq "$(sha256sum "$config/sentinel" | awk '{print $1}')" "$before" "doctor does not alter config"
assert_contains "$out" "PASS: shell.qml" "healthy tree reports shell.qml"
assert_contains "$out" "PASS: launcher invocation" "healthy tree reports launcher reachability"
assert_contains "$out" "WARN: graphical-session auto-start" "auto-start remains explicitly unverified"
assert_contains "$out" "WARN: IPC ping not measurable" "absent process leaves IPC explicitly unmeasured"

out=$(PATH="$fake_bin:$PATH" WAYLAND_DISPLAY=fixture-wayland run_doctor); code=$?
assert_eq "$code" 0 "live IPC ping success passes"
assert_contains "$out" "PASS: IPC ping" "doctor performs bounded read-only IPC ping"
out=$(PATH="$fake_bin:$PATH" WAYLAND_DISPLAY=fixture-wayland COO_FAKE_PING_FAIL=1 run_doctor); code=$?
assert_eq "$code" 1 "live IPC ping failure fails"
assert_contains "$out" "FAIL: IPC ping" "failed IPC ping is explicit"

printf 'pending\n' >"$state/install-pending.manifest"
out=$(run_doctor); code=$?
assert_eq "$code" 1 "pending install fails closed"
assert_contains "$out" "FAIL: incomplete install state" "pending install is explicit"
rm -f "$state/install-pending.manifest"

printf 'not a manifest\n' >"$state/validated-build.manifest"
out=$(run_doctor); code=$?
assert_eq "$code" 1 "malformed manifest fails without false green"
assert_contains "$out" "FAIL: artifact/manifest mismatch" "manifest mismatch is explicit"
rm -f "$state/validated-build.manifest"

release=validated-builds/fixture
artifact_dir=$state/$release/artifacts
mkdir -p "$artifact_dir"
printf shell >"$artifact_dir/cachy-omarchy-shell-4.0.0-1-any.pkg.tar.zst"
printf overlay >"$artifact_dir/cachy-omarchy-overlay-0.1.0-1-any.pkg.tar.zst"
shell_sum=$(sha256sum "$artifact_dir/cachy-omarchy-shell-4.0.0-1-any.pkg.tar.zst" | awk '{print $1}')
overlay_sum=$(sha256sum "$artifact_dir/cachy-omarchy-overlay-0.1.0-1-any.pkg.tar.zst" | awk '{print $1}')
write_valid_manifest() {
  cat >"$state/validated-build.manifest" <<EOF
RELEASE=$release
OMARCHY_VERSION=4.0.0
OMARCHY_COMMIT=1111111111111111111111111111111111111111
ARTIFACT=cachy-omarchy-shell-4.0.0-1-any.pkg.tar.zst $shell_sum
ARTIFACT=cachy-omarchy-overlay-0.1.0-1-any.pkg.tar.zst $overlay_sum
EOF
}
write_valid_manifest
out=$(run_doctor); code=$?
assert_eq "$code" 0 "strict valid manifest passes"
assert_contains "$out" "PASS: validated artifact/manifest" "valid manifest is reported validated"
printf 'ARTIFACT=cachy-omarchy-shell-4.0.0-1-any.pkg.tar.zst %s\n' "$shell_sum" >>"$state/validated-build.manifest"
out=$(run_doctor); code=$?
assert_eq "$code" 1 "duplicate shell artifact fails"
assert_contains "$out" "FAIL: artifact/manifest mismatch" "duplicate artifact is explicit"
write_valid_manifest
printf 'ARTIFACT=cachy-omarchy-unknown-1.0.0-1-any.pkg.tar.zst %s\n' "$shell_sum" >>"$state/validated-build.manifest"
out=$(run_doctor); code=$?
assert_eq "$code" 1 "unknown artifact type fails"
assert_contains "$out" "FAIL: artifact/manifest mismatch" "unknown artifact is explicit"
write_valid_manifest
printf 'UNEXPECTED=value\n' >>"$state/validated-build.manifest"
out=$(run_doctor); code=$?
assert_eq "$code" 1 "unknown manifest field fails"
assert_contains "$out" "FAIL: artifact/manifest mismatch" "unknown manifest field is explicit"
cat >"$state/validated-build.manifest" <<EOF
RELEASE=$release
OMARCHY_VERSION=4.0.0
OMARCHY_COMMIT=1111111111111111111111111111111111111111
ARTIFACT=wrong-shell-4.0.0-1-any.pkg.tar.zst $shell_sum
ARTIFACT=wrong-overlay-0.1.0-1-any.pkg.tar.zst $overlay_sum
EOF
out=$(run_doctor); code=$?
assert_eq "$code" 1 "two valid-looking wrong package names fail"
assert_contains "$out" "FAIL: artifact/manifest mismatch" "wrong package names are explicit"
write_valid_manifest
out=$(COO_SHA256_BIN=missing-sha256 run_doctor); code=$?
assert_eq "$code" 1 "manifest without checksum tool cannot pass"
assert_contains "$out" "FAIL: artifact/manifest mismatch" "missing checksum tool is explicit"
rm -rf "$state/$release" "$state/validated-build.manifest"

printf '{}\n' >"$config/shell.json"
out=$(run_doctor); code=$?
assert_eq "$code" 0 "inert reference copy is warning only"
assert_contains "$out" "WARN: inert shell.json" "inert shell.json is explicit"
rm -f "$config/shell.json"
printf '{}\n' >"$user_config/shell.json"
out=$(run_doctor); code=$?
assert_eq "$code" 0 "user shell override is warning only"
assert_contains "$out" "WARN: user shell override present" "user shell override is explicit"
rm -f "$user_config/shell.json"

rm -f "$prefix/upstream/shell/shell.qml"
out=$(run_doctor); code=$?
assert_eq "$code" 1 "missing shell.qml fails"
assert_contains "$out" "FAIL: shell.qml" "missing shell.qml is explicit"
printf '// fixture shell\n' >"$prefix/upstream/shell/shell.qml"

printf 'bind = SUPER, SPACE, exec, something\n' >"$hypr/hyprland.conf"
out=$(run_doctor); code=$?
assert_eq "$code" 1 "binding conflict fails without false green"
assert_contains "$out" "FAIL: Hyprland binding conflict" "binding conflict is explicit"

exit "$ASSERT_FAILURES"
