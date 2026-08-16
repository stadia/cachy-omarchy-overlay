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

# 회귀: FORCE_ARGS 확장이 빈 배열일 때 인자를 하나도 넘기지 않는지 검증한다.
# "${arr[@]-}" 는 빈 배열에서도 빈 문자열 인자 하나를 넘긴다 — 부작용에
# 의존하지 않도록, cachy-omarchy-bindings 형제 탐색을 피해서 init 스크립트만
# 별도 디렉터리에 두고 PATH 맨 앞에 인자를 검사하는 stub 을 세운다.
STUB_DIR="$COO_TEST_SANDBOX/stubbin-noargs"
mkdir -p "$STUB_DIR"
cat > "$STUB_DIR/cachy-omarchy-bindings" <<'STUB'
#!/usr/bin/env bash
if (( $# != 0 )); then
  printf 'stub: unexpected args: %s\n' "$*" >&2
  exit 1
fi
exit 0
STUB
chmod +x "$STUB_DIR/cachy-omarchy-bindings"

STUB_FORCE_DIR="$COO_TEST_SANDBOX/stubbin-force"
mkdir -p "$STUB_FORCE_DIR"
cat > "$STUB_FORCE_DIR/cachy-omarchy-bindings" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == "--force" ]]; then
  exit 0
fi
printf 'stub: expected exactly --force, got: %s\n' "$*" >&2
exit 1
STUB
chmod +x "$STUB_FORCE_DIR/cachy-omarchy-bindings"

# init 스크립트만 복사해서 형제 cachy-omarchy-bindings 를 못 찾게 만든다 —
# 그래야 PATH 의 stub 으로 강제 폴백한다.
ISOLATED_INIT="$COO_TEST_SANDBOX/isolated-init/cachy-omarchy-init"
mkdir -p "$(dirname "$ISOLATED_INIT")"
cp "$I" "$ISOLATED_INIT"
chmod +x "$ISOLATED_INIT"

REG_HYPR="$COO_TEST_SANDBOX/regress-hypr"
mkdir -p "$REG_HYPR"
: > "$REG_HYPR/hyprland.conf"

REG_CONFIG="$COO_TEST_SANDBOX/regress-config-noargs"
REG_STATE="$COO_TEST_SANDBOX/regress-state-noargs"
out=$(PATH="$STUB_DIR:$PATH" COO_CONFIG_DIR="$REG_CONFIG" COO_STATE_DIR="$REG_STATE" \
      COO_HYPR_DIR="$REG_HYPR" "$ISOLATED_INIT" 2>&1); code=$?
assert_eq "$code" "0" "인자 없는 실행이 stub 에 빈 인자를 넘기지 않는다 (regression)"

REG_CONFIG2="$COO_TEST_SANDBOX/regress-config-force"
REG_STATE2="$COO_TEST_SANDBOX/regress-state-force"
out=$(PATH="$STUB_FORCE_DIR:$PATH" COO_CONFIG_DIR="$REG_CONFIG2" COO_STATE_DIR="$REG_STATE2" \
      COO_HYPR_DIR="$REG_HYPR" "$ISOLATED_INIT" --force 2>&1); code=$?
assert_eq "$code" "0" "--force 는 stub 에 정확히 --force 하나만 넘긴다"

exit "$ASSERT_FAILURES"
