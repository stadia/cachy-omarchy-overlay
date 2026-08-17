#!/usr/bin/env bash
# M10 Task 2 — emoji helper 계약을 fake omarchy-shell/wl-copy/wtype 으로 검증한다.
# 근거: M10 플랜 Task 2, 설계 문서 D4 (선택 후에만 type, 취소는 side effect 없음).
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

src=${COO_OMARCHY_GIT:-$REPO_ROOT/build/omarchy}
[[ -d $src ]] || { echo "skip: 업스트림 클론 없음"; exit 0; }

bin_src="$src/bin"
fake="$COO_TEST_SANDBOX/fakebin"
mkdir -p "$fake"
log="$COO_TEST_SANDBOX/calls.log"
stdin_log="$COO_TEST_SANDBOX/calls.stdin"

cat >"$fake/omarchy-shell" <<EOF
#!/usr/bin/env bash
echo "omarchy-shell \$*" >>"$log"
EOF
cat >"$fake/wl-copy" <<EOF
#!/usr/bin/env bash
echo "wl-copy \$*" >>"$log"
cat >"$stdin_log" 2>/dev/null || true
EOF
cat >"$fake/wtype" <<EOF
#!/usr/bin/env bash
echo "wtype \$*" >>"$log"
EOF
chmod +x "$fake"/*

: >"$log"

# --- omarchy-menu-emoji: shell toggle omarchy.emojis ---
PATH="$fake:$PATH" bash "$bin_src/omarchy-menu-emoji"
grep -qx 'omarchy-shell shell toggle omarchy.emojis' "$log" && x=0 || x=1
assert_eq "$x" "0" "menu-emoji: shell toggle omarchy.emojis"

# --- omarchy-menu-emoji-insert: 선택 시 copy + type 정확히 1회 ---
: >"$log"; rm -f "$stdin_log"
PATH="$fake:$PATH" bash "$bin_src/omarchy-menu-emoji-insert" "😀"
grep -q '^wl-copy --type text/plain --sensitive --foreground' "$log" && x=0 || x=1
assert_eq "$x" "0" "emoji-insert: wl-copy --sensitive"
assert_eq "$(cat "$stdin_log")" "😀" "emoji-insert: emoji 가 wl-copy stdin 으로"
n=$(grep -c '^wtype' "$log" || true)
assert_eq "$n" "1" "emoji-insert: wtype 1회"
grep -q '^wtype -M shift -k Insert -m shift' "$log" && x=0 || x=1
assert_eq "$x" "0" "emoji-insert: shift-insert 조합"

# --- 인자 없음(취소): clipboard/type side effect 없음 ---
: >"$log"; rm -f "$stdin_log"
PATH="$fake:$PATH" bash "$bin_src/omarchy-menu-emoji-insert" && x=0 || x=$?
[[ -s $log ]] && s=1 || s=0
assert_eq "$s" "0" "emoji-insert 취소: wl-copy/wtype 미호출"
[[ ! -e $stdin_log ]] && s=0 || s=1
assert_eq "$s" "0" "emoji-insert 취소: stdin 기록 없음"

exit "$ASSERT_FAILURES"
