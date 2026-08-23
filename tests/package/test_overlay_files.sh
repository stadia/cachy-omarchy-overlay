#!/usr/bin/env bash
# 오버레이 패키지가 정확히 의도한 경로만 소유하는지 검증한다 (SPEC 7.2, 9.3).
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/lib/runtime.sh"

coo_overlay_artifact >/dev/null 2>&1 || { echo "skip: 오버레이 아티팩트 없음 — 먼저 makepkg"; exit 0; }

dest="$COO_TEST_SANDBOX/overlay-pkg"
coo_extract_overlay "$dest"
assert_eq "$?" "0" "오버레이 추출 성공"

for p in \
  usr/bin/cachy-omarchy-shell \
  usr/bin/cachy-omarchy-launcher \
  usr/bin/cachy-omarchy-keybindings \
  usr/bin/cachy-omarchy-bindings \
  usr/bin/cachy-omarchy-init \
  usr/bin/cachy-omarchy-doctor \
  usr/bin/cachy-omarchy-reload \
  usr/lib/cachy-omarchy/compat/bin/omarchy-shell \
  usr/lib/cachy-omarchy/compat/bin/omarchy-update-available \
  usr/lib/cachy-omarchy/compat/bin/omarchy-theme-set-browser \
  usr/lib/cachy-omarchy/compat/bin/omarchy-theme-set-keyboard \
  usr/bin/omarchy-shell \
  usr/bin/omarchy-update-available \
  usr/bin/omarchy-theme-set-browser \
  usr/bin/omarchy-theme-set-keyboard \
  usr/share/cachy-omarchy/defaults/shell.json \
  usr/share/cachy-omarchy/hypr/bindings.conf \
  usr/share/cachy-omarchy/hypr/bindings.lua \
  usr/share/uwsm/env-hyprland.d/10-cachy-omarchy ; do
  assert_file_exists "$dest/$p" "소유: $p"
done

# 공개 명령은 실행 가능해야 한다.
for b in shell launcher keybindings bindings init doctor reload; do
  [[ -x "$dest/usr/bin/cachy-omarchy-$b" ]] && x=0 || x=1
  assert_eq "$x" "0" "실행 가능: cachy-omarchy-$b"
done

# uwsm 드롭인은 sh 로 소싱된다 (/usr/lib/uwsm/prepare-env.sh 의 source_dir).
# 값이 어긋나면 세션 전체가 잘못된 트리를 가리키므로 정확히 단언한다.
dropin="$dest/usr/share/uwsm/env-hyprland.d/10-cachy-omarchy"
grep -qxF 'export OMARCHY_PATH=/usr/share/cachy-omarchy/upstream' "$dropin" && ok=0 || ok=1
assert_eq "$ok" "0" "uwsm 드롭인의 OMARCHY_PATH export 가 정확한 한 줄로 존재한다"
n=$(grep -c '^export ' "$dropin" || true)
assert_eq "$n" "1" "드롭인에 export 는 이 한 줄뿐이다"

exit "$ASSERT_FAILURES"
