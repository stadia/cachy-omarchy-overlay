#!/usr/bin/env bash
# v0.12.0 Track D Task 2: gum 프레젠테이션 레이어와 logo.txt 스테이징을 고정한다.
# 메뉴의 audio restart, passwordless sudo, custom DNS 행은 이 런처를 거치므로
# 얇은 런처만이 아니라 프레젠테이션 헬퍼 전체가 함께 있어야 한다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

src=${COO_OMARCHY_GIT:-$REPO_ROOT/build/omarchy}
[[ -d $src ]] || { echo "skip: 업스트림 클론 없음"; exit 0; }

stage=$COO_TEST_SANDBOX/pkg
bash "$REPO_ROOT/packages/cachy-omarchy-shell/stage-upstream.sh" "$src" "$stage" \
  "$REPO_ROOT/overlay/defaults"
root="$stage/usr/share/cachy-omarchy/upstream"
bin="$root/bin"

helpers=(
  omarchy-restart-gum
  omarchy-show-logo
  omarchy-show-done
  omarchy-launch-floating-terminal-with-presentation
)
for h in "${helpers[@]}"; do
  assert_file_exists "$bin/$h" "프레젠테이션 헬퍼 스테이징: $h"
  [[ -x $bin/$h ]] && x=0 || x=1
  assert_eq "$x" "0" "실행 가능: $h"
  if cmp -s "$src/bin/$h" "$bin/$h"; then x=0; else x=1; fi
  assert_eq "$x" "0" "verbatim: $h 는 업스트림과 바이트 동일"

  link="$stage/usr/bin/$h"
  assert_file_exists "$link" "/usr/bin 노출: $h"
  target=$(readlink -f "$link")
  real=$(readlink -f "$bin/$h")
  [[ $target == "$real" ]] && x=0 || x=1
  assert_eq "$x" "0" "심링크가 스테이징된 실체를 가리킨다: $h"
done

assert_file_exists "$root/logo.txt" "프레젠테이션 logo.txt 스테이징"
if cmp -s "$src/logo.txt" "$root/logo.txt"; then x=0; else x=1; fi
assert_eq "$x" "0" "verbatim: logo.txt 는 업스트림과 바이트 동일"

# show-logo 가 런타임 정본인 $OMARCHY_PATH/logo.txt 를 읽고, 그 자리에
# 바로 위에서 검증한 데이터 파일을 설치한다.
show_logo=$(<"$bin/omarchy-show-logo")
assert_contains "$show_logo" '$OMARCHY_PATH/logo.txt' \
  "omarchy-show-logo 가 설치된 logo.txt 경로를 읽는다"

exit "$ASSERT_FAILURES"
