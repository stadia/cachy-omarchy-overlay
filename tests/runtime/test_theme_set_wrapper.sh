#!/usr/bin/env bash
# cachy-omarchy-theme-set 래퍼가 OMARCHY_PATH 를 export 하고 업스트림
# omarchy-theme-set 으로 exec 하는지, 그리고 실제 headless 테마 적용이
# 샌드박스 HOME 에서 끝까지 도는지 검증한다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/lib/runtime.sh"

WRAPPER="$REPO_ROOT/overlay/bin/cachy-omarchy-theme-set"
assert_file_exists "$WRAPPER" "래퍼 존재"
[[ -x $WRAPPER ]] && x=0 || x=1
assert_eq "$x" "0" "실행 가능"

# 래퍼는 업스트림 스크립트를 exec 하고 OMARCHY_PATH 를 세운다.
src=$(<"$WRAPPER")
assert_contains "$src" "OMARCHY_PATH" "OMARCHY_PATH 해석"
assert_contains "$src" "omarchy-theme-set" "업스트림 스크립트 exec"

# 끝단 실측: 빌드 아티팩트의 업스트림 트리로 headless 테마 적용.
if artifact=$(coo_pkg_artifact); then
  dest="$COO_TEST_SANDBOX/pkg"
  coo_extract_pkg "$dest"
  up="$dest/usr/share/cachy-omarchy/upstream"
  home="$COO_TEST_SANDBOX/home"
  mkdir -p "$home"

  HOME="$home" COO_OMARCHY_PATH="$up" OMARCHY_THEME_HEADLESS=1 \
    "$WRAPPER" "Tokyo Night" >/dev/null 2>&1
  rc=$?
  assert_eq "$rc" "0" "headless theme-set exit 0"
  assert_file_exists "$home/.local/state/omarchy/current/theme/colors.toml" \
    "colors.toml 배치"
  assert_file_exists "$home/.local/state/omarchy/current/theme/shell.toml" \
    "shell.toml 생성 (templates 경유)"
  assert_eq "$(cat "$home/.local/state/omarchy/current/theme.name")" \
    "tokyo-night" "theme.name 기록"
  [[ -L $home/.local/state/omarchy/current/background ]] && l=0 || l=1
  assert_eq "$l" "0" "background symlink (headless 도 놓는다)"

  # 사용자 오버레이 우선순위: ~/.config/omarchy/themes/<name>/ 이 공식을 덮는다.
  mkdir -p "$home/.config/omarchy/themes/tokyo-night"
  printf 'user-override-marker\n' > \
    "$home/.config/omarchy/themes/tokyo-night/marker.txt"
  HOME="$home" COO_OMARCHY_PATH="$up" OMARCHY_THEME_HEADLESS=1 \
    "$WRAPPER" "Tokyo Night" >/dev/null 2>&1
  assert_file_exists "$home/.local/state/omarchy/current/theme/marker.txt" \
    "사용자 오버레이가 공식 테마 위에 합쳐진다"
else
  echo "note: 아티팩트 없음 — 끝단 검증 생략 (bin/build-packages 선행 필요)"
fi

exit "$ASSERT_FAILURES"
