#!/usr/bin/env bash
# M10 Task 4 — image-picker 체인 회귀: M9 가 stage 한 omarchy-menu-images 가
# fake omarchy-shell 에 올바른 summon/preload 요청을 보내는지 검증한다.
# 새 image-picker helper 를 추가하지 않는다는 M10 결정의 회귀 방어다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

src=${COO_OMARCHY_GIT:-$REPO_ROOT/build/omarchy}
[[ -d $src ]] || { echo "skip: 업스트림 클론 없음"; exit 0; }

menu_images="$src/bin/omarchy-menu-images"
fake="$COO_TEST_SANDBOX/fakebin"
mkdir -p "$fake"
log="$COO_TEST_SANDBOX/calls.log"
rows_dump="$COO_TEST_SANDBOX/rows.decoded"

# open 의 positional 인자: $4=rows_b64 $6=selection_file $7=done_file (스크립트
# 인자 기준). FAKE_SELECT=1 이면 selection 을 쓰고, 항상 done_file 을 만든다.
cat >"$fake/omarchy-shell" <<EOF
#!/usr/bin/env bash
echo "omarchy-shell \$*" >>"$log"
if [[ \${1:-} == image-selector && \${2:-} == open ]]; then
  printf '%s' "\$4" | base64 -d >"$rows_dump" 2>/dev/null || true
  [[ \${FAKE_SELECT:-0} == 1 ]] && printf '%s' "\${FAKE_SELECTION:-}" >"\$6"
  : >"\$7"
  echo ok
fi
exit 0
EOF
chmod +x "$fake/omarchy-shell"

imgdir="$COO_TEST_SANDBOX/images"
emptydir="$COO_TEST_SANDBOX/empty"
mkdir -p "$imgdir" "$emptydir"
printf 'PNGA' >"$imgdir/alpha.png"
printf 'PNGB' >"$imgdir/beta.png"

# --- 선택 성공: rows 에 두 이미지, stdout 으로 선택 경로 ---
: >"$log"; rm -f "$rows_dump"
out=$(FAKE_SELECT=1 FAKE_SELECTION="$imgdir/beta.png" \
  PATH="$fake:$PATH" bash "$menu_images" --lazy-thumbnails "$imgdir"); code=$?
assert_eq "$code" "0" "menu-images: 선택 성공 exit 0"
grep -q '^omarchy-shell image-selector open ' "$log" && x=0 || x=1
assert_eq "$x" "0" "menu-images: image-selector open 호출"
assert_contains "$(cat "$rows_dump")" "alpha.png" "rows: alpha.png 포함"
assert_contains "$(cat "$rows_dump")" "beta.png" "rows: beta.png 포함"
assert_eq "$out" "$imgdir/beta.png" "menu-images: 선택 경로 출력"

# --- 취소: selection 없이 done 만 — 출력 없이 exit 0 ---
: >"$log"; rm -f "$rows_dump"
out=$(FAKE_SELECT=0 PATH="$fake:$PATH" bash "$menu_images" --lazy-thumbnails "$imgdir"); code=$?
assert_eq "$code" "0" "menu-images: 취소 exit 0"
assert_eq "$out" "" "menu-images: 취소 시 출력 없음"

# --- 빈 디렉터리: open 은 호출되지만 rows 는 비어 있다 ---
: >"$log"; rm -f "$rows_dump"
out=$(FAKE_SELECT=0 PATH="$fake:$PATH" bash "$menu_images" --lazy-thumbnails "$emptydir"); code=$?
assert_eq "$code" "0" "menu-images: 빈 디렉터리 exit 0"
grep -q '^omarchy-shell image-selector open ' "$log" && x=0 || x=1
assert_eq "$x" "0" "menu-images: 빈 디렉터리도 open 호출"
[[ ! -s $rows_dump ]] && x=0 || x=1
assert_eq "$x" "0" "menu-images: 빈 디렉터리 rows 비어 있음"

# --- preload: open 없이 preload 만 ---
: >"$log"
PATH="$fake:$PATH" bash "$menu_images" --lazy-thumbnails --preload "$imgdir"; code=$?
assert_eq "$code" "0" "menu-images: preload exit 0"
grep -q '^omarchy-shell image-selector preload ' "$log" && x=0 || x=1
assert_eq "$x" "0" "menu-images: preload 호출"
grep -q '^omarchy-shell image-selector open ' "$log" && x=1 || x=0
assert_eq "$x" "0" "menu-images: preload 시 open 미호출"

# --- 인자 없음: usage + exit 1 ---
assert_exit 1 "menu-images: 인자 없음 exit 1" \
  env PATH="$fake:$PATH" bash "$menu_images"

exit "$ASSERT_FAILURES"
