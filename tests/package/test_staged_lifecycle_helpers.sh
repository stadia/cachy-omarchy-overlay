#!/usr/bin/env bash
# v0.11.0 Session Lifecycle Parity: idle → screensaver → lock → wake 체인이
# 부르는 헬퍼의 스테이징을 고정한다.
# omarchy-cmd-missing 은 예외 표에 행조차 없던 미스테이징이었고, 이것이
# 없으면 omarchy-launch-screensaver 의 `if omarchy-cmd-missing ttfx` 가드가
# 127 로 끝난다 — bash if 에서 비영 종료는 거짓이므로 가드를 통과해 버리고,
# ttfx 가 실제로 없을 때 그 뒤 경로가 실패한다. 가드가 먼저 와야 fail-safe 다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

src=${COO_OMARCHY_GIT:-$REPO_ROOT/build/omarchy}
[[ -d $src ]] || { echo "skip: 업스트림 클론 없음"; exit 0; }

stage=$COO_TEST_SANDBOX/pkg
bash "$REPO_ROOT/packages/cachy-omarchy-shell/stage-upstream.sh" "$src" "$stage" \
  "$REPO_ROOT/overlay/defaults"
bin="$stage/usr/share/cachy-omarchy/upstream/bin"

# Task 1: 가드 + 프로브 3종. 전부 verbatim, 새 외부 의존 0.
probes=(
  omarchy-cmd-missing
  omarchy-hw-laptop-closed
  omarchy-hw-external-monitors
  omarchy-hw-clamshell
)
for h in "${probes[@]}"; do
  assert_file_exists "$bin/$h" "lifecycle 프로브 스테이징: $h"
  [[ -x $bin/$h ]] && x=0 || x=1
  assert_eq "$x" "0" "실행 가능: $h"
  if cmp -s "$src/bin/$h" "$bin/$h"; then x=0; else x=1; fi
  assert_eq "$x" "0" "verbatim: $h 는 업스트림과 바이트 동일"
done

# Task 2: 키보드 백라이트. brightnessctl 은 이미 optdepends(OPT) 이고
# omarchy-osd 는 이미 스테이징돼 있다 — 새 의존 선언이 필요 없다.
for h in omarchy-brightness-keyboard; do
  assert_file_exists "$bin/$h" "lifecycle 스테이징: $h"
  if cmp -s "$src/bin/$h" "$bin/$h"; then x=0; else x=1; fi
  assert_eq "$x" "0" "verbatim: $h 는 업스트림과 바이트 동일"
done

exit "$ASSERT_FAILURES"
