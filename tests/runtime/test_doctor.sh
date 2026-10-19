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
unset COO_IPC_TIMEOUT \
  COO_FAKE_PROCESS COO_FAKE_PING_FAIL COO_FAKE_OFFICIAL_PRESENT COO_TEST_WAYLAND_DISPLAY \
  TEST_DOCTOR_PROCESS TEST_DOCTOR_PING_FAIL TEST_DOCTOR_OFFICIAL_PRESENT \
  TEST_DOCTOR_WAYLAND_DISPLAY \
  COO_TEST_DOCTOR_PAM_LOCK_FILE
mkdir -p "$prefix/upstream/shell" "$prefix/upstream/default/omarchy" "$compat" \
  "$root/usr/bin" "$root/usr/lib/systemd/user" "$hypr" "$config" "$user_config" "$state" "$fake_bin"
printf '// fixture shell\n' >"$prefix/upstream/shell/shell.qml"
printf '{}\n' >"$prefix/upstream/default/omarchy/omarchy-menu.jsonc"
printf -- '-- no conflicting bindings\n' >"$hypr/hyprland.lua"
os_release=$COO_TEST_SANDBOX/os-release
printf 'ID=cachyos\n' >"$os_release"
# The lock plugin refuses to lock without this PAM service, so the fixture
# needs one to be healthy. Never point this at the real /etc/pam.d.
pam_lock=$COO_TEST_SANDBOX/pam/omarchy-lock-password
mkdir -p "$(dirname "$pam_lock")"
printf '#%%PAM-1.0\n' >"$pam_lock"
omarchy_state=$COO_TEST_SANDBOX/.local/state/omarchy
for cmd in cachy-omarchy-bindings cachy-omarchy-keybindings; do
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
for cmd in hyprctl quickshell; do printf '#!/usr/bin/env bash\nexit 0\n' >"$fake_bin/$cmd"; done
chmod +x "$fake_bin/pgrep" "$fake_bin/qs" "$fake_bin/pacman" "$fake_bin/hyprctl" "$fake_bin/quickshell"
printf '#!/usr/bin/env bash\nexit 0\n' >"$compat/omarchy-shell"
chmod +x "$compat/omarchy-shell"
mkdir -p "$prefix/upstream/bin"
printf '#!/usr/bin/env bash\nexit 0\n' >"$prefix/upstream/bin/omarchy-theme-set"
chmod +x "$prefix/upstream/bin/omarchy-theme-set"
ln -s ../share/cachy-omarchy/upstream/bin/omarchy-theme-set "$root/usr/bin/omarchy-theme-set"
# SUPER+SPACE 대상. /usr/bin 의 omarchy-* 는 전부 심링크여야 한다.
printf '#!/usr/bin/env bash\nexit 0\n' >"$prefix/upstream/bin/omarchy-menu"
chmod +x "$prefix/upstream/bin/omarchy-menu"
ln -s ../share/cachy-omarchy/upstream/bin/omarchy-menu "$root/usr/bin/omarchy-menu"
ln -s ../lib/cachy-omarchy/compat/bin/omarchy-shell "$root/usr/bin/omarchy-shell"

pacman_log=$COO_TEST_SANDBOX/pacman.log
run_doctor() {
  PATH="$fake_bin:/usr/bin:/bin" WAYLAND_DISPLAY="${TEST_DOCTOR_WAYLAND_DISPLAY:-}" \
    OMARCHY_PATH="$prefix/upstream" \
    COO_PACMAN_LOG="$pacman_log" COO_PREFIX_ROOT="$prefix" COO_COMPAT_BIN="$compat" COO_HYPR_DIR="$hypr" \
    COO_CONFIG_DIR="$config" COO_OMARCHY_CONFIG_DIR="$user_config" \
    COO_OMARCHY_PATH="$prefix/upstream" COO_OS_RELEASE="$os_release" \
    COO_OMARCHY_STATE_DIR="$omarchy_state" \
    COO_PAM_LOCK_FILE="${COO_TEST_DOCTOR_PAM_LOCK_FILE:-$pam_lock}" "$DOCTOR" 2>&1
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
assert_contains "$out" "PASS: lock screen PAM service" "healthy tree reports the lock PAM service"

assert_contains "$(cat "$pacman_log")" "omarchy" "doctor queries official omarchy package"
assert_contains "$(cat "$pacman_log")" "omarchy-settings" "doctor queries official omarchy-settings package"

# Regression for the defect this check exists to catch: without
# /etc/pam.d/omarchy-lock-password the lock plugin returns "missing-pam" and
# omarchy-system-lock discards that answer, so the command exits 0 and locks
# nothing. Doctor is the only place that can say so out loud.
out=$(COO_TEST_DOCTOR_PAM_LOCK_FILE="$COO_TEST_SANDBOX/pam/absent" run_doctor); code=$?
assert_eq "$code" 1 "missing lock PAM service fails closed"
assert_contains "$out" "FAIL: lock screen PAM service missing" "missing lock PAM service is explicit"
assert_contains "$out" "omarchy-apply-lock" "missing lock PAM service names the recovery command"


# Every doctor override except deliberately injected COO_IPC_TIMEOUT is pinned
# by run_doctor. Hostile inherited values must not redirect this fixture.
out_hostile=$(COO_PREFIX_ROOT=/hostile COO_COMPAT_BIN=/hostile COO_HYPR_DIR=/hostile \
  COO_CONFIG_DIR=/hostile COO_OMARCHY_CONFIG_DIR=/hostile \
  COO_OMARCHY_PATH=/hostile COO_OS_RELEASE=/hostile COO_OMARCHY_STATE_DIR=/hostile \
  run_doctor); hostile_code=$?
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
  OMARCHY_PATH="$empty_prefix/upstream" \
  COO_PACMAN_LOG="$pacman_log" COO_PREFIX_ROOT="$empty_prefix" COO_COMPAT_BIN="$compat" \
  COO_HYPR_DIR="$hypr" COO_CONFIG_DIR="$config" COO_OMARCHY_CONFIG_DIR="$user_config" \
  COO_OMARCHY_PATH="$empty_prefix/upstream" COO_OS_RELEASE="$os_release" \
  COO_OMARCHY_STATE_DIR="$omarchy_state" "$DOCTOR" 2>&1); empty_code=$?
assert_contains "$out_empty" "FAIL: no omarchy-* commands exposed" "빈 노출은 FAIL"
[[ $empty_code -ne 0 ]] && empty_nonzero=0 || empty_nonzero=1
assert_eq "$empty_nonzero" "0" "빈 노출은 nonzero exit"

out_nosession=$(PATH="$fake_bin:/usr/bin:/bin" \
  WAYLAND_DISPLAY="${TEST_DOCTOR_WAYLAND_DISPLAY:-}" \
  COO_PACMAN_LOG="$pacman_log" COO_PREFIX_ROOT="$prefix" COO_COMPAT_BIN="$compat" \
  COO_HYPR_DIR="$hypr" COO_CONFIG_DIR="$config" \
  COO_OMARCHY_CONFIG_DIR="$user_config" \
  COO_OMARCHY_PATH="$prefix/upstream" COO_OS_RELEASE="$os_release" \
  COO_OMARCHY_STATE_DIR="$omarchy_state" \
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

# hyprland.conf 는 지원하지 않는다: lua 없이 conf 만 있으면 WARN.
mv "$hypr/hyprland.lua" "$hypr/hyprland.lua.bak"
printf 'monitor=,preferred,auto,1\n' >"$hypr/hyprland.conf"
out=$(run_doctor); code=$?
assert_contains "$out" "FAIL: hyprland.conf is not supported (Lua only)" "conf 전용 구성은 FAIL"
assert_eq "$code" "1" "conf 전용 구성은 doctor 가 실패로 끝난다"
assert_contains "$out" "(hyprland.conf unsupported)" "conf 전용이면 충돌 측정 불가 사유를 구분한다"
printf '# >>> cachy-omarchy >>>\nsource = %s/bindings.conf\n# <<< cachy-omarchy <<<\n' "$config/hypr" >>"$hypr/hyprland.conf"
out=$(run_doctor); code=$?
assert_contains "$out" "WARN: stale cachy-omarchy block in hyprland.conf" "남은 conf 블록을 알린다"
mv "$hypr/hyprland.lua.bak" "$hypr/hyprland.lua"
out=$(run_doctor); code=$?
[[ $out == *"hyprland.conf is not supported"* ]] && w=1 || w=0
assert_eq "$w" "0" "lua 가 있으면 conf 비지원 FAIL 을 내지 않는다"
assert_contains "$out" "WARN: stale cachy-omarchy block in hyprland.conf" "lua 와 공존해도 남은 conf 블록을 알린다"
rm -f "$hypr/hyprland.conf"

# lua 의 mainMod .. " + K" 형태도 충돌이다(bindings 와 같은 판정).
cp "$hypr/hyprland.lua" "$hypr/hyprland.lua.bak"
printf 'hl.bind(mainMod .. " + K", hl.dsp.exec_cmd("x"))\n' >>"$hypr/hyprland.lua"
out=$(run_doctor); code=$?
assert_contains "$out" "FAIL: Hyprland binding conflict" "mainMod .. \" + K\" 충돌을 잡는다"
mv "$hypr/hyprland.lua.bak" "$hypr/hyprland.lua"

# 보존된 구형 bindings.lua 에 hyprland.start 가 없으면 셸이 뜨지 않는다.
mkdir -p "$config/hypr"
cp "$hypr/hyprland.lua" "$hypr/hyprland.lua.bak"
printf -- '-- >>> cachy-omarchy >>>\npcall(dofile, "x")\n-- <<< cachy-omarchy <<<\n' >>"$hypr/hyprland.lua"
printf 'hl.bind("SUPER + F1", hl.dsp.exec_cmd("x"))\n' >"$config/hypr/bindings.lua"
out=$(run_doctor); code=$?
assert_contains "$out" "FAIL: shell autostart missing from $config/hypr/bindings.lua" "hyprland.start 없는 구형 bindings.lua 를 잡는다"
printf 'hl.on("hyprland.start", function() end)\n' >>"$config/hypr/bindings.lua"
out=$(run_doctor); code=$?
assert_contains "$out" "PASS: shell autostart declared (bindings.lua)" "hyprland.start 가 있으면 통과한다"
rm -f "$config/hypr/bindings.lua"
mv "$hypr/hyprland.lua.bak" "$hypr/hyprland.lua"

out=$(run_doctor); code=$?

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

# 0.x 개발 도구가 남긴 상태(매니페스트·pending 마커·릴리스 복사본)는 배포된
# doctor 의 관심사가 아니다. 남아 있어도 판정과 출력에 영향이 없어야 한다.
# 0.x 도구가 쓰던 기본 위치($XDG_STATE_HOME/cachy-omarchy, 샌드박스 안)에
# 심는다. 두 번째 실행은 pending 마커를 끊어진 심링크로 바꿔 본다.
legacy_state=${XDG_STATE_HOME:?}/cachy-omarchy
for pending_kind in file dangling-symlink; do
  mkdir -p "$legacy_state/validated-builds/old/artifacts"
  rm -f "$legacy_state/install-pending.manifest"
  if [[ $pending_kind == file ]]; then
    printf 'pending\n' >"$legacy_state/install-pending.manifest"
  else
    ln -s "$legacy_state/missing-target" "$legacy_state/install-pending.manifest"
  fi
  printf 'not a manifest\n' >"$legacy_state/validated-build.manifest"
  printf 'not a manifest\n' >"$legacy_state/installed-build.manifest"
  out=$(run_doctor); code=$?
  assert_eq "$code" 0 "legacy state is ignored ($pending_kind)"
  [[ $out == *manifest* || $out == *"install state"* ]] && mentioned=1 || mentioned=0
  assert_eq "$mentioned" 0 "legacy state is not reported ($pending_kind)"
done
rm -rf "$legacy_state"

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

printf 'hl.bind("SUPER + SPACE", hl.dsp.exec_cmd("something"))\n' >"$hypr/hyprland.lua"
out=$(run_doctor); code=$?
assert_eq "$code" 1 "binding conflict fails without false green"
assert_contains "$out" "FAIL: Hyprland binding conflict" "binding conflict is explicit"

exit "$ASSERT_FAILURES"
