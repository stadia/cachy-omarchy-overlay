#!/usr/bin/env bash
# /usr/bin 노출 불변식 (SPEC §45). 노출 집합은 두 패키지가 하나의 omarchy-*
# 네임스페이스를 나눠 쓰므로 패키지별로 따로 검증한다 — 합쳐서 비교하면
# 반드시 어긋난다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/lib/runtime.sh"

coo_pkg_artifact >/dev/null 2>&1 || { echo "skip: 셸 아티팩트 없음"; exit 0; }

# --- shell 패키지: 스테이징 배열 ⇔ /usr/bin 심링크 -------------------------
shell_dest="$COO_TEST_SANDBOX/shell-pkg"
coo_extract_pkg "$shell_dest"

expected=$(awk '/^helpers=\(/,/^\)/' \
  "$REPO_ROOT/packages/cachy-omarchy-shell/stage-upstream.sh" \
  | grep -oE '\bomarchy-[a-z0-9-]+' | sort -u)
[[ -n $expected ]] && parsed=0 || parsed=1
assert_eq "$parsed" "0" "stage-upstream.sh 의 helpers 배열을 파싱했다"

actual=$(cd "$shell_dest/usr/bin" 2>/dev/null && ls omarchy-* 2>/dev/null | sort)
assert_eq "$actual" "$expected" "shell: /usr/bin 심링크 집합 = 스테이징 배열"

# 모든 항목이 상대 심링크이며 업스트림 계층만 향하고, 타깃이 실재한다.
bad_kind=0; bad_layer=0; dangling=0
for link in "$shell_dest/usr/bin"/omarchy-*; do
  [[ -e $link || -L $link ]] || continue
  [[ -L $link ]] || { bad_kind=$((bad_kind + 1)); continue; }
  target=$(readlink "$link")
  case "$target" in
    ../share/cachy-omarchy/upstream/bin/*) ;;
    *) bad_layer=$((bad_layer + 1)) ;;
  esac
  [[ -e $link ]] || dangling=$((dangling + 1))
done
assert_eq "$bad_kind" "0" "shell: /usr/bin 항목이 전부 심링크다 (실체 복사 금지)"
assert_eq "$bad_layer" "0" "shell: 타깃이 ../share/cachy-omarchy/upstream/bin/ 만 향한다"
assert_eq "$dangling" "0" "shell: dangling 심링크 없음"

# 패키지 메타데이터는 노출과 한 몸이다. uwsm 이 없으면 uwsm-app 이 없고,
# conflicts 가 없으면 공식 omarchy 와 파일 충돌이 런타임에 터진다.
shell_pkgbuild="$REPO_ROOT/packages/cachy-omarchy-shell/PKGBUILD"
assert_contains "$(cat "$shell_pkgbuild")" "'uwsm'" \
  "shell PKGBUILD depends 에 uwsm"
assert_contains "$(cat "$shell_pkgbuild")" "conflicts=('omarchy')" \
  "shell PKGBUILD 가 omarchy 와 충돌 선언"
grep -q '^provides=' "$shell_pkgbuild" && has_provides=1 || has_provides=0
assert_eq "$has_provides" "0" "shell PKGBUILD 는 provides 를 선언하지 않는다"

exit "$ASSERT_FAILURES"
