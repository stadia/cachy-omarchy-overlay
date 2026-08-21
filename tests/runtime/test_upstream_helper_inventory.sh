#!/usr/bin/env bash
# v0.9: tests/data/upstream-helpers.txt 가 핀된 업스트림 bin/ 과 일치하는지.
#
# 이 파일은 스캐너의 ground truth 다 — 도달한 omarchy-* 이름이 진짜
# 업스트림 헬퍼인지 판정하는 유일한 사실 근거. 설치 트리로는 판정할 수
# 없다(거기엔 우리가 스테이징한 것만 있다). 그래서 체크인해 두는데,
# 체크인한 사실은 핀이 움직이는 순간 낡는다. 이 테스트가 그 순간을 잡는다.
#
# 클론(build/omarchy, gitignore)이 없거나 핀과 다른 커밋에 있으면 조용히
# 통과하지 않고 note 를 찍고 스킵한다 — 이 저장소에서 가장 위험한 실패
# 모드가 "조용히 통과" 다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

inventory="$REPO_ROOT/tests/data/upstream-helpers.txt"
clone="$REPO_ROOT/build/omarchy"

assert_file_exists "$inventory" "인벤토리 파일이 존재한다"
assert_eq "$([[ -s $inventory ]] && echo nonempty)" "nonempty" "인벤토리가 비어 있지 않다"

pinned=$(sed -n "s/^_commit='\([0-9a-f]\{40\}\)'.*/\1/p" \
  "$REPO_ROOT/packages/cachy-omarchy-shell/PKGBUILD" | head -1)
assert_eq "${#pinned}" "40" "PKGBUILD 에서 40자 _commit 을 읽었다"

recorded=$(sed -n 's/^# commit: \([0-9a-f]\{40\}\)$/\1/p' "$inventory" | head -1)
assert_eq "$recorded" "$pinned" \
  "인벤토리 헤더의 커밋이 PKGBUILD 의 _commit 과 같다"

if [[ ! -d $clone/.git ]]; then
  printf 'note: build/omarchy 클론이 없다 — 인벤토리 내용 대조는 스킵한다\n'
  printf 'note: 핀이 움직였다면 클론을 준비하고 다시 돌려야 한다\n'
  exit $((ASSERT_FAILURES > 0))
fi

if ! git -C "$clone" cat-file -e "$pinned^{commit}" 2>/dev/null; then
  printf 'note: 클론에 핀 커밋 %s 이 없다 — 대조를 스킵한다(fetch 필요)\n' "$pinned"
  exit $((ASSERT_FAILURES > 0))
fi

actual=$(git -C "$clone" ls-tree --name-only "$pinned" bin/ | sed 's|^bin/||' | LC_ALL=C sort)
recorded_names=$(grep -v '^#' "$inventory" | grep -v '^[[:space:]]*$')

assert_eq "$(printf '%s\n' "$recorded_names" | wc -l)" \
  "$(printf '%s\n' "$actual" | wc -l)" \
  "인벤토리 항목 수가 핀된 bin/ 과 같다"
assert_eq "$(printf '%s\n' "$recorded_names" | md5sum | cut -d' ' -f1)" \
  "$(printf '%s\n' "$actual" | md5sum | cut -d' ' -f1)" \
  "인벤토리 내용이 핀된 bin/ 과 정확히 같다"

if [[ "$recorded_names" != "$actual" ]]; then
  printf '차이(-인벤토리 +핀):\n'
  diff <(printf '%s\n' "$recorded_names") <(printf '%s\n' "$actual") | head -20
fi

exit $((ASSERT_FAILURES > 0))
