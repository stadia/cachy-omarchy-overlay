#!/usr/bin/env bash
# M10 Task 2 — clipboard helper 계약을 fake wl-*/wtype/launch 명령으로 검증한다.
# 실제 Wayland clipboard watcher 나 wtype 을 사용자 세션에 붙이지 않는다.
# 근거: M10 플랜 Task 2, 설계 문서 D3(개인정보 경계)·D4(명시 선택 후에만 type).
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

src=${COO_OMARCHY_GIT:-$REPO_ROOT/build/omarchy}
[[ -d $src ]] || { echo "skip: 업스트림 클론 없음"; exit 0; }
command -v jq >/dev/null || { echo "skip: jq 없음"; exit 0; }

bin_src="$src/bin"
capture="$src/shell/plugins/clipboard/capture.sh"
fake="$COO_TEST_SANDBOX/fakebin"
mkdir -p "$fake"
log="$COO_TEST_SANDBOX/calls.log"
stdin_log="$COO_TEST_SANDBOX/calls.stdin"

cat >"$fake/wl-copy" <<EOF
#!/usr/bin/env bash
echo "wl-copy \$*" >>"$log"
cat >"$stdin_log" 2>/dev/null || true
EOF
cat >"$fake/wtype" <<EOF
#!/usr/bin/env bash
echo "wtype \$*" >>"$log"
EOF
cat >"$fake/wl-paste" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  --list-types) printf '%s\n' ${FAKE_WL_PASTE_TYPES:-text/plain} ;;
  --type) printf '%s' "${FAKE_WL_PASTE_PAYLOAD:-payload}" ;;
esac
EOF
cat >"$fake/omarchy-launch-browser" <<EOF
#!/usr/bin/env bash
echo "launch-browser \$*" >>"$log"
EOF
cat >"$fake/omarchy-launch-editor" <<EOF
#!/usr/bin/env bash
echo "launch-editor \$*" >>"$log"
EOF
chmod +x "$fake"/*

reset_log() { : >"$log"; rm -f "$stdin_log"; }
reset_log

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
# upstream Clipboard.qml:20 계약 — history 는 항상 HOME 고정 경로다.
history_dir="$HOME/.local/state/omarchy"
mkdir -p "$history_dir"

# --- capture.sh: text ---
out=$(printf 'hello world' | PATH="$fake:$PATH" bash "$capture" text)
assert_contains "$out" '"type":"text"' "capture text: JSON type=text"
assert_contains "$out" 'hello world' "capture text: 본문 포함"

# --- capture.sh: sensitive selection 은 저장하지 않는다 (D3) ---
reset_log
out=$(printf 'secret' | CLIPBOARD_STATE=sensitive PATH="$fake:$PATH" bash "$capture" text)
assert_eq "$out" "" "capture sensitive: 출력 없음"
n=$(find "$state_dir/clipboard-images" -type f 2>/dev/null | wc -l)
assert_eq "$n" "0" "capture sensitive: image 파일 없음"

# --- capture.sh: KDE password-manager hint 차단 ---
out=$(printf 'secret' | FAKE_WL_PASTE_TYPES='x-kde-passwordManagerHint' \
  PATH="$fake:$PATH" bash "$capture")
assert_eq "$out" "" "capture KDE hint: 출력 없음"

# --- capture.sh: image snapshot 은 sha256 이름으로 state dir 에만 ---
out=$(FAKE_WL_PASTE_TYPES='image/png' FAKE_WL_PASTE_PAYLOAD='PNGBYTES' \
  PATH="$fake:$PATH" bash "$capture")
assert_contains "$out" '"type":"image"' "capture image: JSON type=image"
n=$(find "$state_dir/clipboard-images" -type f -name '*.png' 2>/dev/null | wc -l)
assert_eq "$n" "1" "capture image: state dir 에 sha256 png 1개"

# --- paste-text: history 준비 ---
cat >"$history_dir/clipboard-history.json" <<'EOF'
[{"type":"text","text":"hello"},{"type":"image","mime":"image/png","path":"/nonexistent"}]
EOF

# --- paste-text --copy-only: wl-copy 만, wtype 없음 (D4) ---
reset_log
PATH="$fake:$PATH" bash "$bin_src/omarchy-clipboard-paste-text" \
  --copy-only --history-index 0
grep -q '^wl-copy' "$log" && x=0 || x=1
assert_eq "$x" "0" "paste-text copy-only: wl-copy 호출"
grep -q '^wtype' "$log" && x=1 || x=0
assert_eq "$x" "0" "paste-text copy-only: wtype 미호출"
assert_eq "$(cat "$stdin_log")" "hello" "paste-text copy-only: 본문이 wl-copy stdin 으로"

# --- paste-text 선택 paste: wtype 정확히 1회 (shift-insert) ---
reset_log
PATH="$fake:$PATH" bash "$bin_src/omarchy-clipboard-paste-text" --history-index 0
n=$(grep -c '^wtype' "$log" || true)
assert_eq "$n" "1" "paste-text paste: wtype 1회"
grep -q '^wtype -M shift -k Insert -m shift' "$log" && x=0 || x=1
assert_eq "$x" "0" "paste-text paste: shift-insert 조합"

# --- paste-text: 잘못된 history index 는 non-zero, side effect 없음 ---
reset_log
PATH="$fake:$PATH" bash "$bin_src/omarchy-clipboard-paste-text" \
  --copy-only --history-index abc && x=0 || x=$?
[[ $x -ne 0 ]] && x=0 || x=1
assert_eq "$x" "0" "paste-text malformed index: non-zero"
[[ -s $log ]] && x=1 || x=0
assert_eq "$x" "0" "paste-text malformed index: wl-copy/wtype 미호출"

# --- paste-file: --copy-only vs missing file ---
reset_log
payload="$COO_TEST_SANDBOX/img.png"
printf 'PNGBYTES' >"$payload"
PATH="$fake:$PATH" bash "$bin_src/omarchy-clipboard-paste-file" \
  --copy-only image/png "$payload"
grep -q '^wl-copy --type image/png' "$log" && x=0 || x=1
assert_eq "$x" "0" "paste-file copy-only: wl-copy --type"
grep -q '^wtype' "$log" && x=1 || x=0
assert_eq "$x" "0" "paste-file copy-only: wtype 미호출"

assert_exit 1 "paste-file missing file: exit 1" \
  env PATH="$fake:$PATH" bash "$bin_src/omarchy-clipboard-paste-file" \
  image/png "$COO_TEST_SANDBOX/nope.png"

# --- clipboard-open: URL entry 는 launch-browser closure 로 ---
reset_log
cat >"$history_dir/clipboard-history.json" <<'EOF'
[{"type":"text","text":"see https://example.com/page now"}]
EOF
PATH="$fake:$PATH" bash "$bin_src/omarchy-clipboard-open" --history-index 0
grep -q '^launch-browser https://example.com/page$' "$log" && x=0 || x=1
assert_eq "$x" "0" "clipboard-open URL: omarchy-launch-browser 로 exec"

# --- clipboard-open: 비-URL text 는 launch-editor + sandbox 임시 파일 ---
reset_log
cat >"$history_dir/clipboard-history.json" <<'EOF'
[{"type":"text","text":"just some words"}]
EOF
PATH="$fake:$PATH" bash "$bin_src/omarchy-clipboard-open" --history-index 0
grep -q '^launch-editor ' "$log" && x=0 || x=1
assert_eq "$x" "0" "clipboard-open text: omarchy-launch-editor 로 exec"
f=$(find "$state_dir/clipboard-open" -name 'clipboard.*.txt' 2>/dev/null | head -1)
[[ -n $f && $(cat "$f") == "just some words" ]] && x=0 || x=1
assert_eq "$x" "0" "clipboard-open text: 내용이 sandbox 임시 파일에"

# --- clipboard-open: image entry, tensaku-edit 부재 시 명시적 non-zero ---
reset_log
img="$state_dir/clipboard-images/$(printf 'x' | sha256sum | awk '{print $1}').png"
printf 'PNGBYTES' >"$img"
cat >"$history_dir/clipboard-history.json" <<EOF
[{"type":"image","mime":"image/png","path":"$img"}]
EOF
PATH="$fake:$PATH" bash "$bin_src/omarchy-clipboard-open" --history-index 0 \
  >/dev/null 2>&1 && x=0 || x=$?
[[ $x -ne 0 ]] && x=0 || x=1
assert_eq "$x" "0" "clipboard-open image: tensaku-edit 부재 시 non-zero (조용한 실패 아님)"

# --- clipboard-open: 잘못된 index ---
assert_exit 1 "clipboard-open malformed index: exit 1" \
  env PATH="$fake:$PATH" bash "$bin_src/omarchy-clipboard-open" --history-index abc

exit "$ASSERT_FAILURES"
