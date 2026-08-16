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
assert_contains "$src" "printf 'v12" "적응 캐시 스키마는 v12 이다"
[[ $src == *"printf 'v11"* ]] && v=1 || v=0
assert_eq "$v" "0" "upstream v11 캐시는 재사용하지 않는다"

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

# A fake shell makes pre-flight and compat tests independent from real qs.
fake_shell="$COO_TEST_SANDBOX/fake-cachy-omarchy-shell"
fake_log="$COO_TEST_SANDBOX/fake-shell.args"
cat >"$fake_shell" <<'FAKE'
#!/usr/bin/env bash
: "${COO_FAKE_SHELL_LOG:?}"
printf '%s\n' "$@" >"$COO_FAKE_SHELL_LOG"
printf '%s\n' "${COO_FAKE_SHELL_MESSAGE:-fake shell failure}" >&2
exit "${COO_FAKE_SHELL_STATUS:-1}"
FAKE
chmod +x "$fake_shell"

# --- 미기동 실패: COO_SHELL_BIN 주입으로 실제 qs 를 절대 부르지 않는다 ------
: >"$fake_log"
out=$(COO_OMARCHY_PATH="$root" COO_COMPAT_BIN="$REPO_ROOT/overlay/compat/bin" \
  COO_SHELL_BIN="$fake_shell" COO_FAKE_SHELL_LOG="$fake_log" \
  COO_FAKE_SHELL_MESSAGE='error: 셸이 실행 중이 아니다' "$K" 2>&1); code=$?
assert_eq "$code" "1" "셸 미기동 → exit 1"
assert_contains "$out" "--run" "미기동 안내가 기동 방법을 알려준다"
assert_eq "$(cat "$fake_log")" $'--ipc\nshell\nping' "COO_SHELL_BIN pre-flight 주입이 qs 대신 호출된다"

# 스테이징 헬퍼가 없는 트리는 조용히 넘어가지 않는다.
fake="$COO_TEST_SANDBOX/faketree"
mkdir -p "$fake/shell"
: >"$fake/shell/shell.qml"
out=$(COO_OMARCHY_PATH="$fake" COO_COMPAT_BIN="$REPO_ROOT/overlay/compat/bin" \
  COO_SHELL_BIN="$fake_shell" COO_FAKE_SHELL_LOG="$fake_log" "$K" 2>&1); code=$?
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
hl.bind(mainMod .. " + X", hl.dsp.exec_cmd("foo --label=a,b"))
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
    printf 'bind\n\tmodmask: 64\n\tsubmap: \n\tkey: X\n\tkeycode: 0\n\tcatchall: false\n\tdescription: \n\tdispatcher: __lua\n\targ: 4\n\n'
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
# A v11-named upstream cache with stale content must not be selected by the
# adapted v12 key. Its hash uses exactly the pre-adaptation key material.
old_cache_name=$( {
  printf 'v11\n'
  PATH="$stubbin:$PATH" hyprctl devices 2>/dev/null | grep -F 'active keymap:'
  PATH="$stubbin:$PATH" hyprctl binds 2>/dev/null
} | sha256sum | awk '{ print $1 }')
mkdir -p "$cachehome/omarchy"
printf 'STALE V11 RECORD\texec\tstale-command\n' >"$cachehome/omarchy/keybindings-$old_cache_name.records"

out=$(PATH="$stubbin:$PATH" XDG_CACHE_HOME="$cachehome" \
  COO_OMARCHY_PATH="$root" COO_COMPAT_BIN="$REPO_ROOT/overlay/compat/bin" \
  "$K" --print 2>&1); code=$?
assert_eq "$code" "0" "--print 는 셸 없이 목록을 만든다 (exit 0)"
[[ $out == *"STALE V11 RECORD"* ]] && stale=1 || stale=0
assert_eq "$stale" "0" "v11 캐시 레코드는 선택되지 않는다"
assert_contains "$out" "SUPER + T" "description-less lua bind 가 목록에 산다"
assert_contains "$out" "ghostty" "exec_cmd 인자가 표시된다"
assert_contains "$out" "window.close()" "lua dispatcher 는 hl.dsp. 를 벗긴 설명을 얻는다"
assert_contains "$out" "Discord" "description 이 있는 bind 는 그것을 쓴다"
assert_contains "$out" "Browser" "plain conf exec bind 도 그대로 통과한다"
assert_contains "$out" "foo --label=a,b" "쉼표가 있는 exec_cmd 전체가 표시된다"
rows=$(grep -c '→' <<<"$out")
[[ $rows -gt 2 ]] && d=0 || d=1
assert_eq "$d" "0" "업스트림 drop 이 없다 (행 수 $rows > 2)"
ls "$cachehome"/omarchy/keybindings-*.records >/dev/null 2>&1 && c=0 || c=1
assert_eq "$c" "0" "레코드 캐시 파일이 생긴다"
cache_records=$(cat "$cachehome"/omarchy/keybindings-*.records)
assert_contains "$cache_records" "firefox" "캐시 레코드는 dispatch 메타(exec 인자)를 담는다"
assert_contains "$cache_records" $'exec\tfoo --label=a,b' "쉼표가 있는 dispatcher/arg 메타가 보존된다"

# --- compat omarchy-shell shim: 실행 인자/오류 모드를 실제로 검증 ------------
assert_file_exists "$SHIM" "compat omarchy-shell 존재"
[[ -x $SHIM ]] && x=0 || x=1
assert_eq "$x" "0" "compat omarchy-shell 실행 가능"

: >"$fake_log"
out=$(COO_SHELL_BIN="$fake_shell" COO_FAKE_SHELL_LOG="$fake_log" "$SHIM" shell summon omarchy.menu 2>&1); code=$?
assert_eq "$code" "1" "shim 일반 3인자 실패는 전파한다"
assert_contains "$out" "fake shell failure" "shim 일반 실패는 출력도 전파한다"
assert_eq "$(cat "$fake_log")" $'--ipc\nshell\nsummon\nomarchy.menu\n{}' "shim 3인자 summon 은 {} 를 정확히 한 번 붙인다"

: >"$fake_log"
out=$(COO_SHELL_BIN="$fake_shell" COO_FAKE_SHELL_LOG="$fake_log" "$SHIM" shell summon omarchy.menu '{"mode":"select"}' 2>&1); code=$?
assert_eq "$code" "1" "shim payload summon 실패는 전파한다"
assert_eq "$(cat "$fake_log")" $'--ipc\nshell\nsummon\nomarchy.menu\n{"mode":"select"}' "shim payload summon 은 {} 를 추가하지 않는다"

: >"$fake_log"
out=$(COO_SHELL_BIN="$fake_shell" COO_FAKE_SHELL_LOG="$fake_log" "$SHIM" -q shell toggle omarchy.menu 2>&1); code=$?
assert_eq "$code" "0" "shim -q 는 실패해도 exit 0"
assert_eq "$out" "" "shim -q 는 failing helper 출력을 숨긴다"
assert_eq "$(cat "$fake_log")" $'--ipc\nshell\ntoggle\nomarchy.menu\n{}' "shim -q toggle 도 {} 를 한 번 붙인다"

# --- 패치 수 0 유지 ----------------------------------------------------------
assert_file_exists "$PATCHES" "patches README 존재"
psrc=$(cat "$PATCHES")
assert_contains "$psrc" "none" "패치 수 0 유지"

exit "$ASSERT_FAILURES"
