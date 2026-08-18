#!/usr/bin/env bash
# init 은 테마가 없을 때만 Tokyo Night 를 시드한다 (M9 설계 문서 D4,
# upstream install/user/theme.sh 와 동일 시맨틱). 기존 테마는 절대 덮어쓰지
# 않는다 (SPEC 6.6).
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/lib/runtime.sh"

# Capture each required package archive exactly once.  The test must exercise
# installed payloads, not the checkout, and a missing build artifact is a
# failed build-before-test prerequisite rather than a passing skip.
shell_artifact=$(coo_pkg_artifact) || {
  printf 'error: required shell package artifact is absent\n' >&2
  exit 1
}
overlay_artifact=$(coo_overlay_artifact) || {
  printf 'error: required overlay package artifact is absent\n' >&2
  exit 1
}
shell_dest="$COO_TEST_SANDBOX/shell-pkg"
overlay_dest="$COO_TEST_SANDBOX/overlay-pkg"
mkdir -p "$shell_dest" "$overlay_dest"
bsdtar -xf "$shell_artifact" -C "$shell_dest" || {
  printf 'error: could not extract captured shell package artifact: %s\n' "$shell_artifact" >&2
  exit 1
}
bsdtar -xf "$overlay_artifact" -C "$overlay_dest" || {
  printf 'error: could not extract captured overlay package artifact: %s\n' "$overlay_artifact" >&2
  exit 1
}
INIT="$overlay_dest/usr/bin/cachy-omarchy-init"
up="$shell_dest/usr/share/cachy-omarchy/upstream"
assert_file_exists "$INIT" "추출된 overlay init 존재"
assert_contains "$INIT" "$COO_TEST_SANDBOX" "init 은 추출된 overlay payload 에서 실행한다"
assert_file_exists "$overlay_dest/usr/bin/cachy-omarchy-bindings" "추출된 overlay bindings 존재"
assert_file_exists "$up/bin/omarchy-theme-set" "추출된 shell theme helper 존재"

# pgrep 스텁: 이 테스트는 반드시 headless 경로로 가야 한다. 개발 호스트에
# 셸이 떠 있으면 init 의 시드가 비헤드리스 경로를 타고 post 훅 중
# omarchy-restart-hyprctl 이 실세션에 hyprctl reload 를 보낸다 — 안전 규칙
# 위배. pgrep 을 항상 실패시켜 headless 를 강제한다.
stub="$COO_TEST_SANDBOX/stub-bin"
mkdir -p "$stub"
printf '#!/usr/bin/env bash\nexit 1\n' > "$stub/pgrep"
chmod +x "$stub/pgrep"

home=$COO_TEST_SANDBOX/inithome
mkdir -p "$home/.config/cachy-omarchy/hypr" "$home/.config/hypr"
printf '// stub\n' > "$home/.config/hypr/hyprland.lua"

run_init() {
  env -u OMARCHY_PATH \
    HOME="$home" COO_PREFIX_ROOT="$shell_dest/usr/share/cachy-omarchy" \
    COO_CONFIG_DIR="$home/.config/cachy-omarchy" \
    COO_STATE_DIR="$home/.local/state/omarchy" \
    COO_HYPR_DIR="$home/.config/hypr" \
    PATH="$stub:$up/bin:$PATH" "$@"
}

# 1) 부재 시 시드
run_init "$INIT" >/dev/null 2>&1
assert_eq "$(cat "$home/.local/state/omarchy/current/theme.name" 2>/dev/null)" \
  "tokyo-night" "테마 부재 시 Tokyo Night 시드"
assert_file_exists "$home/.local/state/omarchy/current/theme/colors.toml" \
  "시드된 colors.toml"

# 2) 기존 테마 보존 (SPEC 6.6)
home2=$COO_TEST_SANDBOX/inithome2
mkdir -p "$home2/.config/cachy-omarchy/hypr" "$home2/.config/hypr" \
         "$home2/.local/state/omarchy/current"
printf 'nord\n' > "$home2/.local/state/omarchy/current/theme.name"
printf '// stub\n' > "$home2/.config/hypr/hyprland.lua"
home=$home2 run_init "$INIT" >/dev/null 2>&1
assert_eq "$(cat "$home2/.local/state/omarchy/current/theme.name")" "nord" \
  "기존 테마는 덮어쓰지 않는다"

# 3) --dry-run 은 아무것도 쓰지 않는다
home3=$COO_TEST_SANDBOX/inithome3
mkdir -p "$home3/.config/cachy-omarchy/hypr" "$home3/.config/hypr"
printf '// stub\n' > "$home3/.config/hypr/hyprland.lua"
home=$home3 run_init "$INIT" --dry-run >/dev/null 2>&1
[[ -e $home3/.local/state/omarchy/current/theme.name ]] && x=1 || x=0
assert_eq "$x" "0" "--dry-run 은 시드하지 않는다"

# 4) 빈 theme.name 은 부재 취급해 재시드한다 (upstream 의 [[ ! -s ]] 와 동일,
#    M9 설계 문서 D4 — ! -f 가 아니다)
home4=$COO_TEST_SANDBOX/inithome4
mkdir -p "$home4/.config/cachy-omarchy/hypr" "$home4/.config/hypr" \
         "$home4/.local/state/omarchy/current"
: > "$home4/.local/state/omarchy/current/theme.name"
printf '// stub\n' > "$home4/.config/hypr/hyprland.lua"
home=$home4 run_init "$INIT" >/dev/null 2>&1
assert_eq "$(cat "$home4/.local/state/omarchy/current/theme.name")" \
  "tokyo-night" "빈 theme.name 은 부재 취급 (upstream ! -s 시맨틱)"

# 5) 명령 해석과 환경 주입 계약 (spec §7.1). 가짜 omarchy-theme-set 이 받은
#    환경을 기록하게 해서 init 이 무엇을 넘기는지 직접 본다.
home5=$COO_TEST_SANDBOX/inithome5
mkdir -p "$home5/.config/cachy-omarchy/hypr" "$home5/.config/hypr"
printf '// stub\n' > "$home5/.config/hypr/hyprland.lua"
probe_bin=$COO_TEST_SANDBOX/probe-bin
probe_log=$COO_TEST_SANDBOX/theme-set.env
mkdir -p "$probe_bin"
cat > "$probe_bin/omarchy-theme-set" <<PROBE
#!/usr/bin/env bash
{
  printf 'OMARCHY_PATH=%s\n' "\${OMARCHY_PATH:-<unset>}"
  printf 'HEADLESS=%s\n' "\${OMARCHY_THEME_HEADLESS:-<unset>}"
  printf 'ARG=%s\n' "\$1"
} > "$probe_log"
mkdir -p "\$HOME/.local/state/omarchy/current"
printf 'tokyo-night\n' > "\$HOME/.local/state/omarchy/current/theme.name"
PROBE
chmod +x "$probe_bin/omarchy-theme-set"

env -u OMARCHY_PATH \
  HOME="$home5" COO_PREFIX_ROOT="$shell_dest/usr/share/cachy-omarchy" \
  COO_CONFIG_DIR="$home5/.config/cachy-omarchy" \
  COO_STATE_DIR="$home5/.local/state/omarchy" \
  COO_HYPR_DIR="$home5/.config/hypr" \
  PATH="$probe_bin:$stub:$PATH" "$INIT" >/dev/null 2>&1

assert_contains "$(cat "$probe_log" 2>/dev/null)" \
  "OMARCHY_PATH=$shell_dest/usr/share/cachy-omarchy/upstream" \
  "init 이 OMARCHY_PATH 를 명시적으로 주입한다"
assert_contains "$(cat "$probe_log" 2>/dev/null)" "HEADLESS=1" \
  "셸이 없으면 OMARCHY_THEME_HEADLESS=1 로 부른다"
assert_contains "$(cat "$probe_log" 2>/dev/null)" "ARG=Tokyo Night" \
  "시드 테마 이름을 그대로 넘긴다"

# 6) 명령이 없으면 하드 실패가 아니라 exact note 를 남기고 계속한다.
# /usr/bin 에 호스트의 omarchy-theme-set 심링크가 있을 수 있으므로, 실제 init
# 스크립트는 테스트 로컬 심링크로 실행하고 필요한 유틸리티와 형제 bindings 만
# 제공한다. 이 PATH 에는 omarchy-theme-set 을 의도적으로 만들지 않는다.
home6=$COO_TEST_SANDBOX/inithome6
mkdir -p "$home6/.config/cachy-omarchy/hypr" "$home6/.config/hypr"
printf '// stub\n' > "$home6/.config/hypr/hyprland.lua"
missing_theme_env=$COO_TEST_SANDBOX/missing-theme-env
mkdir -p "$missing_theme_env"
ln -s "$INIT" "$missing_theme_env/cachy-omarchy-init"
ln -s /usr/bin/bash "$missing_theme_env/bash"
ln -s /usr/bin/dirname "$missing_theme_env/dirname"
cat > "$missing_theme_env/cachy-omarchy-bindings" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$missing_theme_env/cachy-omarchy-bindings"
assert_eq "$(PATH="$missing_theme_env" "$missing_theme_env/bash" -c 'command -v omarchy-theme-set || true')" "" \
  "격리 PATH 에 omarchy-theme-set 이 없다"
out=$(env -u OMARCHY_PATH \
  HOME="$home6" COO_PREFIX_ROOT="$shell_dest/usr/share/cachy-omarchy" \
  COO_CONFIG_DIR="$home6/.config/cachy-omarchy" \
  COO_STATE_DIR="$home6/.local/state/omarchy" \
  COO_HYPR_DIR="$home6/.config/hypr" \
  PATH="$missing_theme_env" "$missing_theme_env/cachy-omarchy-init" 2>&1); code=$?
assert_eq "$code" "0" "omarchy-theme-set 부재는 하드 실패가 아니다"
assert_eq "$out" "note: omarchy-theme-set 없음 — 테마 시드를 건너뛴다" \
  "부재 exact note 를 남긴다"

exit "$ASSERT_FAILURES"
