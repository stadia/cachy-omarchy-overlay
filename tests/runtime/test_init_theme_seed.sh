#!/usr/bin/env bash
# init 은 테마가 없을 때만 Tokyo Night 를 시드한다 (M9 설계 문서 D4,
# upstream install/user/theme.sh 와 동일 시맨틱). 기존 테마는 절대 덮어쓰지
# 않는다 (SPEC 6.6).
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/lib/runtime.sh"

INIT="$REPO_ROOT/overlay/bin/cachy-omarchy-init"
assert_file_exists "$INIT" "init 존재"

artifact=$(coo_pkg_artifact) || { echo "note: 아티팩트 없음 — skip"; exit 0; }
dest="$COO_TEST_SANDBOX/pkg"
coo_extract_pkg "$dest"
up="$dest/usr/share/cachy-omarchy/upstream"

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
  HOME="$home" COO_OMARCHY_PATH="$up" COO_PREFIX_ROOT="$dest/usr/share/cachy-omarchy" \
  COO_CONFIG_DIR="$home/.config/cachy-omarchy" \
  COO_STATE_DIR="$home/.local/state/omarchy" \
  COO_HYPR_DIR="$home/.config/hypr" \
  PATH="$stub:$PATH" "$@"
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

exit "$ASSERT_FAILURES"
