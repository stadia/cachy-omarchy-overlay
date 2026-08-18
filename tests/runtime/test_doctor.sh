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
cat >"$fake_bin/pgrep" <<'EOF'
#!/usr/bin/env bash
[[ ${COO_FAKE_PROCESS:-0} == 1 ]]
EOF
cat >"$fake_bin/qs" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$fake_bin/pacman" <<'EOF'
#!/usr/bin/env bash
case ${1:-} in
  -Q)
    printf '%s\n' "${2:-}" >>"${COO_PACMAN_LOG:?}"
    case ${2:-} in
      omarchy|omarchy-settings)
        [[ ${COO_FAKE_OFFICIAL_PRESENT:-} == "$2" ]] && { printf '%s 1.0-1\n' "$2"; exit 0; }
        ;;
    esac
    exit 1
    ;;
  -Qo)
    [[ ${2:-} == "$COO_FAKE_UWSM_APP" ]] || exit 1
    printf '%s is owned by uwsm 0.26.6-1\n' "$2"
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

pacman_log=$COO_TEST_SANDBOX/pacman.log
run_doctor() {
  PATH="$fake_bin:/usr/bin:/bin" WAYLAND_DISPLAY="${COO_TEST_WAYLAND_DISPLAY:-}" \
    OMARCHY_PATH="$prefix/upstream" COO_FAKE_UWSM_APP="$fake_bin/uwsm-app" \
    COO_PACMAN_LOG="$pacman_log" COO_PREFIX_ROOT="$prefix" COO_COMPAT_BIN="$compat" COO_HYPR_DIR="$hypr" \
    COO_CONFIG_DIR="$config" COO_OMARCHY_CONFIG_DIR="$user_config" COO_STATE_DIR="$state" "$DOCTOR" 2>&1
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

# 세션 환경은 uwsm 이 공급한다. doctor 자체의 fallback 경로가 이 사실을 가리면
# 잘못된 세션을 정상으로 오진하므로 상속값을 별도로 검사해야 한다.
assert_contains "$out" "PASS: session OMARCHY_PATH" "세션 변수가 있으면 PASS"
assert_contains "$out" "PASS: /usr/bin omarchy-* symlinks resolve" "심링크가 있으면 PASS"
assert_contains "$out" "PASS: uwsm-app owned by uwsm package" "uwsm-app 소유권을 확인한다"

out_nosession=$(PATH="$fake_bin:/usr/bin:/bin" \
  WAYLAND_DISPLAY="${COO_TEST_WAYLAND_DISPLAY:-}" COO_FAKE_UWSM_APP="$fake_bin/uwsm-app" \
  COO_PACMAN_LOG="$pacman_log" COO_PREFIX_ROOT="$prefix" COO_COMPAT_BIN="$compat" \
  COO_HYPR_DIR="$hypr" COO_CONFIG_DIR="$config" \
  COO_OMARCHY_CONFIG_DIR="$user_config" COO_STATE_DIR="$state" \
  env -u OMARCHY_PATH "$DOCTOR" 2>&1); nocode=$?
assert_contains "$out_nosession" "FAIL: OMARCHY_PATH not in session environment" \
  "세션 변수가 없으면 FAIL"
assert_contains "$out_nosession" "Hyprland (uwsm-managed)" \
  "무엇을 해야 하는지 알려준다"
[[ $nocode -ne 0 ]] && nz=0 || nz=1
assert_eq "$nz" "0" "세션 변수 부재는 nonzero exit"

# M9: 테마 런타임 점검. 부재는 §66 상 실패가 아니라 WARN, 존재는 PASS.
# (run_doctor 는 COO_OMARCHY_STATE_DIR 를 안 세우므로 기본값
#  $XDG_STATE_HOME/omarchy = 샌드박스 경로를 탄다.)
omarchy_state=$COO_TEST_SANDBOX/.local/state/omarchy
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
mv "$hypr/hyprland.conf.bak" "$hypr/hyprland.conf"

# jq 는 M10 에서 hard depends — 없어도 FAIL 은 아니지만 WARN 으로 드러난다.
printf '#!/usr/bin/env bash\nexit 0\n' > "$fake_bin/jq"
chmod +x "$fake_bin/jq"
out=$(run_doctor); code=$?
assert_contains "$out" "PASS: jq" "jq 존재는 PASS"
rm -f "$fake_bin/jq"
if ! command -v jq >/dev/null 2>&1; then
  out=$(run_doctor); code=$?
  assert_contains "$out" "WARN: jq missing" "jq 부재는 WARN (hard depends — 깨진 설치 신호)"
else
  echo "note: 호스트에 jq 있음 — 부재 분기는 미측정"
fi

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

out=$(COO_FAKE_PROCESS=1 COO_TEST_WAYLAND_DISPLAY=fixture-wayland run_doctor); code=$?
assert_eq "$code" 0 "live IPC ping success passes"
assert_contains "$out" "PASS: IPC ping" "doctor performs bounded read-only IPC ping"
out=$(COO_FAKE_PROCESS=1 COO_TEST_WAYLAND_DISPLAY=fixture-wayland COO_FAKE_PING_FAIL=1 run_doctor); code=$?
assert_eq "$code" 1 "live IPC ping failure fails"
assert_contains "$out" "FAIL: IPC ping" "failed IPC ping is explicit"
out=$(COO_FAKE_PROCESS=1 COO_TEST_WAYLAND_DISPLAY=fixture-wayland COO_IPC_TIMEOUT=0 run_doctor); code=$?
assert_eq "$code" 1 "zero IPC timeout is rejected before ping"
assert_contains "$out" "FAIL: IPC timeout" "zero IPC timeout is explicit"
for invalid_timeout in '' -1 not-a-number 11; do
  out=$(COO_IPC_TIMEOUT="$invalid_timeout" run_doctor); code=$?
  assert_eq "$code" 1 "invalid IPC timeout is rejected: ${invalid_timeout:-empty}"
  assert_contains "$out" "FAIL: IPC timeout" "invalid timeout is explicit: ${invalid_timeout:-empty}"
done
out=$(COO_FAKE_OFFICIAL_PRESENT=omarchy run_doctor); code=$?
assert_eq "$code" 1 "official omarchy presence fails"
assert_contains "$out" "FAIL: official package present: omarchy" "official omarchy presence is explicit"
out=$(COO_FAKE_OFFICIAL_PRESENT=omarchy-settings run_doctor); code=$?
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
