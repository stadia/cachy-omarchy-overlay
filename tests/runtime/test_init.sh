#!/usr/bin/env bash
# cachy-omarchy-init 의 최초 실행·멱등·보존. 전부 샌드박스 HOME 에서 돈다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

# 사용자 실제 HOME 을 건드릴 수 없게 구조적으로 막는다.
[[ ${HOME:-} == "${COO_TEST_SANDBOX:?}" ]] \
  || { echo "FAIL: HOME 이 샌드박스가 아니다 — 중단"; exit 1; }

I="$REPO_ROOT/overlay/bin/cachy-omarchy-init"
assert_file_exists "$I" "init 존재"
[[ -x $I ]] && x=0 || x=1
assert_eq "$x" "0" "init 실행 가능"
[[ -x $I ]] || exit 1

export COO_PREFIX_ROOT="$REPO_ROOT/overlay"        # defaults/ 와 hypr/ 가 여기 있다
export COO_SRC_HYPR="$REPO_ROOT/overlay/hypr"
export COO_HYPR_DIR="$COO_TEST_SANDBOX/hypr"
mkdir -p "$COO_HYPR_DIR"
: > "$COO_HYPR_DIR/hyprland.conf"

# --dry-run 은 아무것도 쓰지 않는다.
out=$("$I" --dry-run 2>&1); code=$?
assert_eq "$code" "0" "--dry-run exit 0"
[[ -e "$HOME/.config/cachy-omarchy" ]] && wrote=1 || wrote=0
assert_eq "$wrote" "0" "--dry-run 은 아무것도 만들지 않는다"

# 최초 실행.
out=$("$I" 2>&1); code=$?
assert_eq "$code" "0" "최초 실행 exit 0"
assert_file_exists "$HOME/.config/cachy-omarchy/shell.json" "사용자 설정 배치"
assert_file_exists "$HOME/.local/state/omarchy/toggles/bar-off" "bar-off 토글 생성"
assert_file_exists "$HOME/.config/cachy-omarchy/hypr/bindings.conf" "바인딩 배치"

# 사용자가 고친 파일을 두 번째 실행이 덮어쓰지 않는다.
printf '{"version":1,"USER_EDIT":true}\n' > "$HOME/.config/cachy-omarchy/shell.json"
out=$("$I" 2>&1); code=$?
assert_eq "$code" "0" "두 번째 실행 exit 0"
assert_contains "$(cat "$HOME/.config/cachy-omarchy/shell.json")" "USER_EDIT" \
  "사용자 수정 보존 (멱등)"

# 사용자가 지운 bar-off 를 되살리지 않는다 — 사용자 의사를 존중한다.
rm -f "$HOME/.local/state/omarchy/toggles/bar-off"
"$I" >/dev/null 2>&1
[[ -e "$HOME/.local/state/omarchy/toggles/bar-off" ]] && back=1 || back=0
assert_eq "$back" "0" "사용자가 지운 bar-off 를 되살리지 않는다"

exit "$ASSERT_FAILURES"
