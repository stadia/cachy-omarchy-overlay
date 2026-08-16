#!/usr/bin/env bash
# M4 Task 2: cachy-omarchy-keybindings 정적 계약 + 데이터 수집 적응 (hermetic).
# 라이브 컴포지터에서 메뉴를 열지 않는다 (열림/Escape 는 Task 3).
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

K="$REPO_ROOT/overlay/bin/cachy-omarchy-keybindings"
SHIM="$REPO_ROOT/overlay/compat/bin/omarchy-shell"
STAGE="$REPO_ROOT/packages/cachy-omarchy-shell/stage-upstream.sh"
PATCHES="$REPO_ROOT/packages/cachy-omarchy-shell/patches/README.md"

assert_file_exists "$K" "keybindings 명령 존재"
[[ -x $K ]] && x=0 || x=1
assert_eq "$x" "0" "keybindings 명령 실행 가능"
[[ -x $K ]] || exit 1

# --- 사용법/인자 계약 -------------------------------------------------------
out=$("$K" --help 2>&1); code=$?
assert_eq "$code" "0" "--help exit 0"
assert_contains "$out" "SUPER+K" "--help 가 SUPER+K 를 설명한다"
assert_contains "$out" "omarchy-menu-keybindings" "--help 가 업스트림 원본을 밝힌다"

out=$("$K" --nonsense 2>&1); code=$?
assert_eq "$code" "1" "알 수 없는 인자 → exit 1"

# --- IPC 재발명 없음 (소스 needle) ------------------------------------------
src=$(cat "$K")
assert_contains "$src" "omarchy-menu-select" "선택 UI 는 업스트림 omarchy-menu-select"
[[ $src == *"qs ipc"* ]] && q=1 || q=0
assert_eq "$q" "0" "keybindings 스크립트는 qs ipc 를 직접 부르지 않는다"
assert_contains "$src" "modmask" "hyprctl binds + Lua 캐시 데이터 수집을 감싼다"

# --- 스테이징: 업스트림 bin 헬퍼 두 개만 -----------------------------------
usrc=${COO_OMARCHY_GIT:-$REPO_ROOT/build/omarchy}
stage="$COO_TEST_SANDBOX/stage"
bash "$STAGE" "$usrc" "$stage" "$REPO_ROOT/overlay/defaults"
root="$stage/usr/share/cachy-omarchy/upstream"
assert_file_exists "$root/bin/omarchy-menu-select" "스테이징: omarchy-menu-select"
assert_file_exists "$root/bin/omarchy-cmd-present" "스테이징: omarchy-cmd-present"
[[ -e $root/bin/omarchy-menu-keybindings ]] && s=1 || s=0
assert_eq "$s" "0" "스테이징: 업스트림 omarchy-menu-keybindings 는 넣지 않는다"
[[ -e $root/bin/omarchy-theme-set ]] && s=1 || s=0
assert_eq "$s" "0" "스테이징: 나머지 업스트림 bin 은 넣지 않는다"

# --- 미기동 실패 ------------------------------------------------------------
out=$(COO_OMARCHY_PATH="$root" COO_COMPAT_BIN="$REPO_ROOT/overlay/compat/bin" "$K" 2>&1); code=$?
assert_eq "$code" "1" "셸 미기동 → exit 1"
assert_contains "$out" "--run" "미기동 안내가 기동 방법을 알려준다"

# 스테이징 헬퍼가 없는 트리는 조용히 넘어가지 않는다.
fake="$COO_TEST_SANDBOX/faketree"
mkdir -p "$fake/shell"
: > "$fake/shell/shell.qml"
out=$(COO_OMARCHY_PATH="$fake" COO_COMPAT_BIN="$REPO_ROOT/overlay/compat/bin" "$K" 2>&1); code=$?
assert_eq "$code" "1" "헬퍼 없는 트리 → exit 1"
assert_contains "$out" "omarchy-menu-select" "오류가 무엇이 없는지 말해준다"

# --- 데이터 수집 적응 (hermetic: hyprctl stub + fixture lua) -----------------
[[ ${HOME:-} == "${COO_TEST_SANDBOX:?}" ]] || {
  printf 'FAIL: HOME 이 샌드박스가 아니다 — 사용자 상태를 건드릴 수 있어 중단한다\n' >&2
  exit 1
}
command -v lua >/dev/null || { echo "skip: lua 없음"; exit "$ASSERT_FAILURES"; }

mkdir -p "$HOME/.config/hypr"
cat >"$HOME/.config/hypr/hyprland.lua" <<'LUA'
local mainMod = "SUPER"
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd("ghostty"))
hl.bind(mainMod .. " + C", hl.dsp.window.close())
hl.bind(mainMod .. " + D", hl.dsp.exec_cmd("discord"), { description = "Discord" })
LUA

stubbin="$COO_TEST_SANDBOX/stubbin"
mkdir -p "$stubbin"
cat >"$stubbin/hyprctl" <<'STUB'
#!/usr/bin/env bash
# plain `hyprctl binds` 포맷 stub — 탭 들여쓰기가 awk 파서 계약이다.
case ${1:-} in
  binds)
    printf 'bind\n\tmodmask: 64\n\tsubmap: \n\tkey: T\n\tkeycode: 0\n\tcatchall: false\n\tdescription: \n\tdispatcher: __lua\n\targ: 1\n\n'
    printf 'bind\n\tmodmask: 64\n\tsubmap: \n\tkey: C\n\tkeycode: 0\n\tcatchall: false\n\tdescription: \n\tdispatcher: __lua\n\targ: 2\n\n'
    printf 'bind\n\tmodmask: 64\n\tsubmap: \n\tkey: D\n\tkeycode: 0\n\tcatchall: false\n\tdescription: \n\tdispatcher: __lua\n\targ: 3\n\n'
    printf 'bind\n\tmodmask: 64\n\tsubmap: \n\tkey: B\n\tkeycode: 0\n\tcatchall: false\n\tdescription: Browser\n\tdispatcher: exec\n\targ: firefox\n\n'
    ;;
  devices)
    printf 'Keyboards:\n\t\tactive keymap: stub\n'
    ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$stubbin/hyprctl"

cachehome="$COO_TEST_SANDBOX/cache"
out=$(PATH="$stubbin:$PATH" XDG_CACHE_HOME="$cachehome" \
  COO_OMARCHY_PATH="$root" COO_COMPAT_BIN="$REPO_ROOT/overlay/compat/bin" \
  "$K" --print 2>&1); code=$?
assert_eq "$code" "0" "--print 는 셸 없이 목록을 만든다 (exit 0)"
assert_contains "$out" "SUPER + T" "description-less lua bind 가 목록에 산다"
assert_contains "$out" "ghostty" "exec_cmd 인자가 표시된다"
assert_contains "$out" "window.close()" "lua dispatcher 는 hl.dsp. 를 벗긴 설명을 얻는다"
assert_contains "$out" "Discord" "description 이 있는 bind 는 그것을 쓴다"
assert_contains "$out" "Browser" "plain conf exec bind 도 그대로 통과한다"
rows=$(grep -c '→' <<<"$out")
[[ $rows -gt 2 ]] && d=0 || d=1
assert_eq "$d" "0" "업스트림 drop 이 없다 (행 수 $rows > 2)"
ls "$cachehome"/omarchy/keybindings-*.records >/dev/null 2>&1 && c=0 || c=1
assert_eq "$c" "0" "레코드 캐시 파일이 생긴다"
assert_contains "$(cat "$cachehome"/omarchy/keybindings-*.records)" "firefox" "캐시 레코드는 dispatch 메타(exec 인자)를 담는다"

# --- compat omarchy-shell shim ----------------------------------------------
assert_file_exists "$SHIM" "compat omarchy-shell 존재"
[[ -x $SHIM ]] && x=0 || x=1
assert_eq "$x" "0" "compat omarchy-shell 실행 가능"
shimsrc=$(cat "$SHIM")
assert_contains "$shimsrc" '--ipc' "shim 은 cachy-omarchy-shell --ipc 에 위임한다"
assert_contains "$shimsrc" 'COO_SHELL_BIN' "shim 은 COO_SHELL_BIN 을 존중한다"
assert_contains "$shimsrc" '{}' "shim 은 3인자 summon/toggle 에 빈 payload 를 채운다"
assert_contains "$shimsrc" '-q' "shim 은 -q 조용 모드를 안다"

# --- 패치 수 0 유지 ----------------------------------------------------------
assert_file_exists "$PATCHES" "patches README 존재"
psrc=$(cat "$PATCHES")
assert_contains "$psrc" "none" "패치 수 0 유지"

exit "$ASSERT_FAILURES"
