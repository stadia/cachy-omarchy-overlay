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
# A caller may export doctor or former fixture controls. Keep the fixture
# baseline hermetic; only the namespaced controls below enable special cases.
unset COO_IPC_TIMEOUT COO_TEST_DOCTOR_SHA256_BIN \
  COO_FAKE_PROCESS COO_FAKE_PING_FAIL COO_FAKE_OFFICIAL_PRESENT COO_TEST_WAYLAND_DISPLAY \
  TEST_DOCTOR_PROCESS TEST_DOCTOR_PING_FAIL TEST_DOCTOR_OFFICIAL_PRESENT \
  TEST_DOCTOR_WAYLAND_DISPLAY TEST_DOCTOR_UWSM_APP
mkdir -p "$prefix/upstream/shell" "$prefix/upstream/default/omarchy" "$compat" \
  "$root/usr/bin" "$root/usr/lib/systemd/user" "$hypr" "$config" "$user_config" "$state" "$fake_bin"
printf '// fixture shell\n' >"$prefix/upstream/shell/shell.qml"
printf '{}\n' >"$prefix/upstream/default/omarchy/omarchy-menu.jsonc"
printf '# no conflicting bindings\n' >"$hypr/hyprland.conf"
os_release=$COO_TEST_SANDBOX/os-release
printf 'ID=cachyos\n' >"$os_release"
omarchy_state=$COO_TEST_SANDBOX/.local/state/omarchy
for cmd in cachy-omarchy-launcher cachy-omarchy-bindings cachy-omarchy-keybindings; do
  printf '#!/usr/bin/env bash\nexit 0\n' >"$root/usr/bin/$cmd"
  chmod +x "$root/usr/bin/$cmd"
done
cat >"$root/usr/bin/cachy-omarchy-shell" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == --ipc && ${2:-} == shell && ${3:-} == ping ]]; then
  [[ ${TEST_DOCTOR_PING_FAIL:-0} == 1 ]] && exit 1
  printf 'ok\n'
fi
exit 0
EOF
chmod +x "$root/usr/bin/cachy-omarchy-shell"
cat >"$fake_bin/pgrep" <<'EOF'
#!/usr/bin/env bash
[[ ${TEST_DOCTOR_PROCESS:-0} == 1 ]]
EOF
cat >"$fake_bin/qs" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
# Test-local jq accepts exactly doctor's array-length query and the known
# valid fixture arrays. All other input is unreadable, so malformed fixture
# history follows doctor's warning path without an external interpreter.
cat >"$fake_bin/jq" <<'EOF'
#!/usr/bin/env bash
query='if type == "array" then length else empty end'
[[ $# -eq 3 && $1 == -r && $2 == "$query" && -r $3 ]] || exit 2
payload=$(<"$3")
case $payload in
  '[]') printf '0\n' ;;
  '[{"type":"text","text":"gamma"}]') printf '1\n' ;;
  '[{"type":"text","text":"alpha"},{"type":"text","text":"beta"}]') printf '2\n' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$fake_bin/jq"
grep -q 'python3' "$fake_bin/jq" && jq_uses_python=1 || jq_uses_python=0
assert_eq "$jq_uses_python" "0" "fake jq has no undeclared Python dependency"
cat >"$fake_bin/pacman" <<'EOF'
#!/usr/bin/env bash
case ${1:-} in
  -Qqo)
    printf '%s\n' "$1" >>"${COO_PACMAN_OWNER_LOG:?}"
    [[ ${2:-} == "$TEST_DOCTOR_UWSM_APP" ]] || exit 1
    printf 'uwsm\n'
    ;;
  -Qo)
    # Verbose ownership prose is intentionally unavailable: doctor must use
    # the quiet package-name query, not parse localized human output.
    printf '%s\n' "$1" >>"${COO_PACMAN_OWNER_LOG:?}"
    exit 1
    ;;
  -Q)
    printf '%s\n' "${2:-}" >>"${COO_PACMAN_LOG:?}"
    case ${2:-} in
      omarchy|omarchy-settings)
        [[ ${TEST_DOCTOR_OFFICIAL_PRESENT:-} == "$2" ]] && { printf '%s 1.0-1\n' "$2"; exit 0; }
        ;;
    esac
    exit 1
    ;;
  *) exit 2 ;;
esac
EOF
for cmd in hyprctl quickshell uwsm-app; do printf '#!/usr/bin/env bash\nexit 0\n' >"$fake_bin/$cmd"; done
chmod +x "$fake_bin/pgrep" "$fake_bin/qs" "$fake_bin/pacman" "$fake_bin/hyprctl" "$fake_bin/quickshell" "$fake_bin/uwsm-app"
printf '#!/usr/bin/env bash\nexit 0\n' >"$compat/omarchy-shell"
chmod +x "$compat/omarchy-shell"
mkdir -p "$prefix/upstream/bin"
printf '#!/usr/bin/env bash\nexit 0\n' >"$prefix/upstream/bin/omarchy-theme-set"
chmod +x "$prefix/upstream/bin/omarchy-theme-set"
ln -s ../share/cachy-omarchy/upstream/bin/omarchy-theme-set "$root/usr/bin/omarchy-theme-set"
ln -s ../lib/cachy-omarchy/compat/bin/omarchy-shell "$root/usr/bin/omarchy-shell"

pacman_log=$COO_TEST_SANDBOX/pacman.log
owner_query_log=$COO_TEST_SANDBOX/pacman-owner-query.log
: >"$owner_query_log"
export COO_PACMAN_OWNER_LOG=$owner_query_log
run_doctor() {
  PATH="$fake_bin:/usr/bin:/bin" WAYLAND_DISPLAY="${TEST_DOCTOR_WAYLAND_DISPLAY:-}" \
    OMARCHY_PATH="$prefix/upstream" TEST_DOCTOR_UWSM_APP="$fake_bin/uwsm-app" \
    COO_PACMAN_LOG="$pacman_log" COO_PREFIX_ROOT="$prefix" COO_COMPAT_BIN="$compat" COO_HYPR_DIR="$hypr" \
    COO_CONFIG_DIR="$config" COO_OMARCHY_CONFIG_DIR="$user_config" COO_STATE_DIR="$state" \
    COO_OMARCHY_PATH="$prefix/upstream" COO_OS_RELEASE="$os_release" \
    COO_OMARCHY_STATE_DIR="$omarchy_state" \
    COO_SHA256_BIN="${COO_TEST_DOCTOR_SHA256_BIN:-sha256sum}" "$DOCTOR" 2>&1
}

run_doctor_with_sha() {
  COO_TEST_DOCTOR_SHA256_BIN=$1 run_doctor
}

printf 'do not modify\n' >"$config/sentinel"
before=$(sha256sum "$config/sentinel" | awk '{print $1}')
out=$(run_doctor); code=$?
assert_eq "$code" 0 "healthy extracted tree passes"
assert_eq "$(sha256sum "$config/sentinel" | awk '{print $1}')" "$before" "doctor does not alter config"
assert_contains "$out" "PASS: shell.qml" "healthy tree reports shell.qml"
assert_contains "$out" "PASS: launcher invocation" "healthy tree reports launcher reachability"
assert_contains "$out" "WARN: Quickshell process not observed" "baseline does not inherit a real Quickshell process"
assert_contains "$out" "WARN: IPC ping not measurable" "absent process leaves IPC explicitly unmeasured"
assert_contains "$(cat "$pacman_log")" "omarchy" "doctor queries official omarchy package"
assert_contains "$(cat "$pacman_log")" "omarchy-settings" "doctor queries official omarchy-settings package"
assert_eq "$(cat "$owner_query_log")" "-Qqo"   "healthy doctor queries uwsm-app ownership with pacman -Qqo"

# Every doctor override except deliberately injected COO_IPC_TIMEOUT is pinned
# by run_doctor. Hostile inherited values must not redirect this fixture.
out_hostile=$(COO_PREFIX_ROOT=/hostile COO_COMPAT_BIN=/hostile COO_HYPR_DIR=/hostile \
  COO_CONFIG_DIR=/hostile COO_STATE_DIR=/hostile COO_OMARCHY_CONFIG_DIR=/hostile \
  COO_OMARCHY_PATH=/hostile COO_OS_RELEASE=/hostile COO_OMARCHY_STATE_DIR=/hostile \
  COO_SHA256_BIN=missing-sha256 run_doctor); hostile_code=$?
assert_eq "$hostile_code" "0" "hostile doctor overrides cannot corrupt fixture health"
assert_contains "$out_hostile" "PASS: shell.qml ($prefix/upstream/shell/shell.qml)" \
  "fixture keeps its own OMARCHY_PATH despite hostile override"

# Legacy fake controls must not leak into an otherwise baseline doctor call.
out_hostile_controls=$(COO_FAKE_PROCESS=1 COO_FAKE_PING_FAIL=1 \
  COO_FAKE_OFFICIAL_PRESENT=omarchy COO_TEST_WAYLAND_DISPLAY=hostile-wayland run_doctor); hostile_controls_code=$?
assert_eq "$hostile_controls_code" "0" "hostile inherited fake controls cannot corrupt baseline"
assert_contains "$out_hostile_controls" "WARN: Quickshell process not observed" \
  "hostile fake process control is ignored"
assert_contains "$out_hostile_controls" "PASS: official package absent: omarchy" \
  "hostile fake official-package control is ignored"

# 세션 환경은 uwsm 이 공급한다. doctor 자체의 fallback 경로가 이 사실을 가리면
# 잘못된 세션을 정상으로 오진하므로 상속값을 별도로 검사해야 한다.
assert_contains "$out" "PASS: session OMARCHY_PATH" "세션 변수가 있으면 PASS"
assert_contains "$out" "PASS: /usr/bin omarchy-* symlinks resolve" "심링크가 있으면 PASS"
assert_contains "$out" "PASS: exposed: omarchy-theme-set" "업스트림 핵심 명령 노출을 확인한다"
assert_contains "$out" "PASS: exposed: omarchy-shell" "compat 핵심 명령 노출을 확인한다"
assert_contains "$out" "PASS: uwsm-app owned by uwsm package" "quiet ownership query is locale-independent"

ln -s ../share/cachy-omarchy/upstream/bin/omarchy-gone "$root/usr/bin/omarchy-gone"
out_broken=$(run_doctor); broken_code=$?
assert_contains "$out_broken" "FAIL: /usr/bin omarchy-* symlinks broken" "dangling 심링크는 FAIL"
[[ $broken_code -ne 0 ]] && broken_nonzero=0 || broken_nonzero=1
assert_eq "$broken_nonzero" "0" "dangling 심링크는 nonzero exit"
rm -f "$root/usr/bin/omarchy-gone"

empty_root=$COO_TEST_SANDBOX/empty-exposure
empty_prefix=$empty_root/usr/share/cachy-omarchy
mkdir -p "$empty_root/usr/bin" "$empty_prefix/upstream/shell" "$empty_prefix/upstream/default/omarchy"
printf '// fixture shell\n' >"$empty_prefix/upstream/shell/shell.qml"
printf '{}\n' >"$empty_prefix/upstream/default/omarchy/omarchy-menu.jsonc"
out_empty=$(PATH="$fake_bin:/usr/bin:/bin" WAYLAND_DISPLAY="${TEST_DOCTOR_WAYLAND_DISPLAY:-}" \
  OMARCHY_PATH="$empty_prefix/upstream" TEST_DOCTOR_UWSM_APP="$fake_bin/uwsm-app" \
  COO_PACMAN_LOG="$pacman_log" COO_PREFIX_ROOT="$empty_prefix" COO_COMPAT_BIN="$compat" \
  COO_HYPR_DIR="$hypr" COO_CONFIG_DIR="$config" COO_OMARCHY_CONFIG_DIR="$user_config" \
  COO_STATE_DIR="$state" COO_OMARCHY_PATH="$empty_prefix/upstream" COO_OS_RELEASE="$os_release" \
  COO_OMARCHY_STATE_DIR="$omarchy_state" COO_SHA256_BIN=sha256sum "$DOCTOR" 2>&1); empty_code=$?
assert_contains "$out_empty" "FAIL: no omarchy-* commands exposed" "빈 노출은 FAIL"
[[ $empty_code -ne 0 ]] && empty_nonzero=0 || empty_nonzero=1
assert_eq "$empty_nonzero" "0" "빈 노출은 nonzero exit"

out_nosession=$(PATH="$fake_bin:/usr/bin:/bin" \
  WAYLAND_DISPLAY="${TEST_DOCTOR_WAYLAND_DISPLAY:-}" TEST_DOCTOR_UWSM_APP="$fake_bin/uwsm-app" \
  COO_PACMAN_LOG="$pacman_log" COO_PREFIX_ROOT="$prefix" COO_COMPAT_BIN="$compat" \
  COO_HYPR_DIR="$hypr" COO_CONFIG_DIR="$config" \
  COO_OMARCHY_CONFIG_DIR="$user_config" COO_STATE_DIR="$state" \
  COO_OMARCHY_PATH="$prefix/upstream" COO_OS_RELEASE="$os_release" \
  COO_OMARCHY_STATE_DIR="$omarchy_state" COO_SHA256_BIN=sha256sum \
  env -u OMARCHY_PATH "$DOCTOR" 2>&1); nocode=$?
assert_contains "$out_nosession" "FAIL: OMARCHY_PATH not in session environment" \
  "세션 변수가 없으면 FAIL"
assert_contains "$out_nosession" "Hyprland (uwsm-managed)" \
  "무엇을 해야 하는지 알려준다"
[[ $nocode -ne 0 ]] && nz=0 || nz=1
assert_eq "$nz" "0" "세션 변수 부재는 nonzero exit"

# M9: 테마 런타임 점검. 부재는 §66 상 실패가 아니라 WARN, 존재는 PASS.
# (run_doctor pins COO_OMARCHY_STATE_DIR to this sandbox path.)
assert_contains "$out" "WARN: no theme set" "테마 부재는 명시적 WARN (실패 아님)"

mkdir -p "$omarchy_state/current"
printf 'tokyo-night\n' > "$omarchy_state/current/theme.name"
out=$(run_doctor); code=$?
assert_contains "$out" "PASS: theme: tokyo-night" "테마 존재는 PASS"

# 구형 conf 주입: 테마가 있는데 관리 블록에 theme source 줄이 없으면 WARN.
cp "$hypr/hyprland.conf" "$hypr/hyprland.conf.bak"
printf '# >>> cachy-omarchy >>>\nsource = %s/bindings.conf\n# <<< cachy-omarchy <<<\n' \
  "$config/hypr" >> "$hypr/hyprland.conf"
out=$(run_doctor); code=$?
assert_contains "$out" "WARN: theme hyprland.lua not sourced" "구형 주입은 명시적 WARN"
printf 'source = %s/.local/state/omarchy/current/theme/hyprland.lua\n' "$COO_TEST_SANDBOX" \
  >> "$hypr/hyprland.conf"
out=$(run_doctor); code=$?
assert_contains "$out" "PASS: theme hyprland.lua sourced" "source 줄 있으면 PASS"
# A commented stale source is not active Hyprland configuration.
sed -i 's|^source = \(.*current/theme/hyprland.lua\)|# source = \1|' "$hypr/hyprland.conf"
out=$(run_doctor); code=$?
assert_contains "$out" "WARN: theme hyprland.lua not sourced" "주석 source 줄은 PASS 가 아니다"
mv "$hypr/hyprland.conf.bak" "$hypr/hyprland.conf"

out=$(run_doctor); code=$?
assert_contains "$out" "PASS: jq" "test-local jq 존재는 PASS"

# M10: clipboard history 는 upstream 의 HOME 고정 경로(Clipboard.qml:20)에서만
# 읽는다. 경로·항목 수만 보고하고 내용은 출력하지 않으며 절대 수정하지 않는다.
clip_history="$COO_TEST_SANDBOX/.local/state/omarchy/clipboard-history.json"
out=$(run_doctor); code=$?
assert_contains "$out" "WARN: clipboard history absent" "history 부재는 명시적 WARN (실패 아님)"

mkdir -p "$(dirname "$clip_history")"
printf '[{"type":"text","text":"alpha"},{"type":"text","text":"beta"}]\n' >"$clip_history"
hist_before=$(sha256sum "$clip_history" | awk '{print $1}')
out=$(run_doctor); code=$?
assert_contains "$out" "PASS: clipboard history: 2 entries" "유효 history 는 항목 수만 보고"
assert_eq "$(sha256sum "$clip_history" | awk '{print $1}')" "$hist_before" "doctor 는 history 를 수정하지 않는다"
if grep -q 'alpha\|beta' <<<"$out"; then x=1; else x=0; fi
assert_eq "$x" "0" "doctor 는 history 내용을 출력하지 않는다"

printf 'not json\n' >"$clip_history"
out=$(run_doctor); code=$?
assert_contains "$out" "WARN: clipboard history unreadable" "깨진 history 는 WARN (수리 시도 없음)"

# M10 회귀: XDG_STATE_HOME 을 HOME 과 의도적으로 다르게 둬도 doctor 는 upstream
# Clipboard.qml:20 의 HOME 고정 경로를 읽어야 한다 — XDG 경로로 우회하면 안 된다.
xdg_elsewhere=$COO_TEST_SANDBOX/xdg-elsewhere
mkdir -p "$xdg_elsewhere/omarchy"
printf '[{"type":"text","text":"gamma"}]\n' >"$clip_history"
printf '[]\n' >"$xdg_elsewhere/omarchy/clipboard-history.json"
out=$(XDG_STATE_HOME="$xdg_elsewhere" run_doctor); code=$?
assert_contains "$out" "PASS: clipboard history: 1 entries" "XDG_STATE_HOME 분기: HOME 고정 경로를 읽는다"
assert_contains "$out" "$clip_history" "XDG_STATE_HOME 분기: 보고 경로가 HOME 기반"
rm -f "$clip_history" "$xdg_elsewhere/omarchy/clipboard-history.json"

out=$(TEST_DOCTOR_PROCESS=1 TEST_DOCTOR_WAYLAND_DISPLAY=fixture-wayland run_doctor); code=$?
assert_eq "$code" 0 "live IPC ping success passes"
assert_contains "$out" "PASS: IPC ping" "doctor performs bounded read-only IPC ping"
out=$(TEST_DOCTOR_PROCESS=1 TEST_DOCTOR_WAYLAND_DISPLAY=fixture-wayland TEST_DOCTOR_PING_FAIL=1 run_doctor); code=$?
assert_eq "$code" 1 "live IPC ping failure fails"
assert_contains "$out" "FAIL: IPC ping" "failed IPC ping is explicit"
out=$(TEST_DOCTOR_PROCESS=1 TEST_DOCTOR_WAYLAND_DISPLAY=fixture-wayland COO_IPC_TIMEOUT=0 run_doctor); code=$?
assert_eq "$code" 1 "zero IPC timeout is rejected before ping"
assert_contains "$out" "FAIL: IPC timeout" "zero IPC timeout is explicit"
for invalid_timeout in '' -1 not-a-number 11; do
  out=$(COO_IPC_TIMEOUT="$invalid_timeout" run_doctor); code=$?
  assert_eq "$code" 1 "invalid IPC timeout is rejected: ${invalid_timeout:-empty}"
  assert_contains "$out" "FAIL: IPC timeout" "invalid timeout is explicit: ${invalid_timeout:-empty}"
done
out=$(TEST_DOCTOR_OFFICIAL_PRESENT=omarchy run_doctor); code=$?
assert_eq "$code" 1 "official omarchy presence fails"
assert_contains "$out" "FAIL: official package present: omarchy" "official omarchy presence is explicit"
out=$(TEST_DOCTOR_OFFICIAL_PRESENT=omarchy-settings run_doctor); code=$?
assert_eq "$code" 1 "official omarchy-settings presence fails"
assert_contains "$out" "FAIL: official package present: omarchy-settings" "official omarchy-settings presence is explicit"

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
cp "$state/validated-build.manifest" "$state/installed-build.manifest"
out=$(run_doctor); code=$?
assert_eq "$code" 0 "valid installed manifest passes"
assert_contains "$out" "PASS: installed artifact/manifest" "installed manifest is reported separately"
printf 'broken installed pointer\n' >"$state/installed-build.manifest"
out=$(run_doctor); code=$?
assert_eq "$code" 1 "malformed installed manifest fails"
assert_contains "$out" "FAIL: installed artifact/manifest mismatch" "installed mismatch is explicit"
rm -f "$state/installed-build.manifest"
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
out=$(run_doctor_with_sha missing-sha256); code=$?
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
