#!/usr/bin/env bash
# v0.12.0 Track B Task 1: 바 투명 모드 텍스트 대비색 헬퍼 스테이징을 고정한다.
# shell/plugins/bar/Bar.qml:834 가 requestedTransparent 일 때만 부른다 —
# 부재 시 Process 가 조용히 실패해 투명 바 텍스트가 테마 전경색으로 고정된다
# (크래시 아님, 가시적 결손).
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

src=${COO_OMARCHY_GIT:-$REPO_ROOT/build/omarchy}
[[ -d $src ]] || { echo "skip: 업스트림 클론 없음"; exit 0; }

stage=$COO_TEST_SANDBOX/pkg
bash "$REPO_ROOT/packages/cachy-omarchy-shell/stage-upstream.sh" "$src" "$stage" \
  "$REPO_ROOT/overlay/defaults"
bin="$stage/usr/share/cachy-omarchy/upstream/bin"

h=omarchy-bar-text-color
assert_file_exists "$bin/$h" "스테이징: $h"
[[ -x $bin/$h ]] && x=0 || x=1
assert_eq "$x" "0" "실행 가능: $h"
if cmp -s "$src/bin/$h" "$bin/$h"; then x=0; else x=1; fi
assert_eq "$x" "0" "verbatim: $h 는 업스트림과 바이트 동일"

# /usr/bin/omarchy-bar-text-color 심링크가 스테이징된 실체를 가리킨다.
link="$stage/usr/bin/$h"
assert_file_exists "$link" "/usr/bin 노출: $h"
target=$(readlink -f "$link")
real=$(readlink -f "$bin/$h")
[[ $target == "$real" ]] && x=0 || x=1
assert_eq "$x" "0" "심링크가 스테이징된 실체를 가리킨다: $h"

# imagemagick(magick) 이 optdepends 로 선언됐다 — 새 외부 의존.
pkgbuild=$(<"$REPO_ROOT/packages/cachy-omarchy-shell/PKGBUILD")
assert_contains "$pkgbuild" "imagemagick:" "imagemagick 이 optdepends 에 선언됐다"

exit "$ASSERT_FAILURES"
