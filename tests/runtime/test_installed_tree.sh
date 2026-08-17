#!/usr/bin/env bash
# 두 패키지를 추출해 "설치된 것처럼" 배치하고, 공개 명령이 그 트리만으로
# 동작하는지 검증한다. 실제 설치(sudo/pacman -U)는 하지 않는다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/lib/runtime.sh"

[[ ${HOME:-} == "${COO_TEST_SANDBOX:?}" ]] \
  || { echo "FAIL: HOME 이 샌드박스가 아니다 — 중단"; exit 1; }

coo_pkg_artifact >/dev/null 2>&1 || { echo "skip: 셸 아티팩트 없음"; exit 0; }
coo_overlay_artifact >/dev/null 2>&1 || { echo "skip: 오버레이 아티팩트 없음"; exit 0; }

root="$COO_TEST_SANDBOX/root"
# 순서가 중요하다: coo_extract_overlay 는 dest 를 rm -rf 로 비우고 시작하므로
# 반드시 먼저 부른다. coo_extract_pkg 는 비우지 않으므로 그 위에 겹친다.
coo_extract_overlay "$root"    # /usr/bin, /usr/lib, /usr/share
coo_extract_pkg "$root"        # /usr/share/cachy-omarchy/upstream 을 겹쳐 놓는다

BIN="$root/usr/bin"
export COO_PREFIX_ROOT="$root/usr/share/cachy-omarchy"
export COO_COMPAT_BIN="$root/usr/lib/cachy-omarchy/compat/bin"

# 1) 셸 래퍼가 추출 트리에서 업스트림을 찾는다.
assert_eq "$("$BIN/cachy-omarchy-shell" --path)" \
  "$COO_PREFIX_ROOT/upstream" "--path 가 설치 트리를 가리킨다"
assert_file_exists "$COO_PREFIX_ROOT/upstream/shell/shell.qml" "업스트림 셸 트리 존재"

# 2) 두 패키지의 shell.json 이 같은 파일이다 (한 정본).
assert_eq "$(jq -S . "$COO_PREFIX_ROOT/upstream/config/omarchy/shell.json")" \
          "$(jq -S . "$COO_PREFIX_ROOT/defaults/shell.json")" \
          "defaults 와 스테이징된 기본값이 동일"

# 3) init 가 설치 트리만으로 동작한다.
export COO_HYPR_DIR="$COO_TEST_SANDBOX/hypr"
mkdir -p "$COO_HYPR_DIR"; : > "$COO_HYPR_DIR/hyprland.conf"
out=$(PATH="$BIN:$PATH" "$BIN/cachy-omarchy-init" 2>&1); code=$?
assert_eq "$code" "0" "설치 트리에서 init exit 0"
assert_file_exists "$HOME/.config/cachy-omarchy/hypr/bindings.conf" "init 가 바인딩 배치"
[[ -e "$HOME/.local/state/omarchy/toggles/bar-off" ]] && made=1 || made=0
assert_eq "$made" "0" "설치 트리의 init 도 bar-off 를 만들지 않는다"

# 4) compat shim 은 /usr/bin 이 아니라 통제된 경로에 있다.
[[ -x "$COO_COMPAT_BIN/omarchy-shell" ]] && ok=0 || ok=1
assert_eq "$ok" "0" "compat omarchy-shell 이 통제 경로에 있다"
[[ -e "$BIN/omarchy-shell" ]] && leak=1 || leak=0
assert_eq "$leak" "0" "/usr/bin 으로 새지 않았다"

# 5) 공식 omarchy 는 여전히 미설치.
pacman -Q omarchy >/dev/null 2>&1 && inst=1 || inst=0
assert_eq "$inst" "0" "공식 omarchy 미설치 (SPEC 61)"

exit "$ASSERT_FAILURES"
