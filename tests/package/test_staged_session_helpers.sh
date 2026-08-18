#!/usr/bin/env bash
# 메뉴 style.bar + 세션 lock/logout/reboot/shutdown 스테이징과
# factory-reset 미스테이징을 검증한다.
# 전이 closure: omarchy-bar → omarchy-shell-config + omarchy-plugin-catalog;
# logout/reboot/shutdown → omarchy-hyprland-window-close-all + omarchy-state.
# omarchy-osd / omarchy-cmd-present / omarchy-shell 은 이미 다른 계층.
# omarchy-apply-lock 은 omarchy-system-lock 의 전제다 — 이것이 만드는
# /etc/pam.d/omarchy-lock-password 가 없으면 lock 플러그인이 IPC 에서
# "missing-pam" 으로 물러나고 omarchy-system-lock 은 그 실패를 삼킨다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

src=${COO_OMARCHY_GIT:-$REPO_ROOT/build/omarchy}
[[ -d $src ]] || { echo "skip: 업스트림 클론 없음"; exit 0; }

stage=$COO_TEST_SANDBOX/pkg
bash "$REPO_ROOT/packages/cachy-omarchy-shell/stage-upstream.sh" "$src" "$stage" \
  "$REPO_ROOT/overlay/defaults"
bin="$stage/usr/share/cachy-omarchy/upstream/bin"

staged=(
  omarchy-bar
  omarchy-shell-config
  omarchy-plugin-catalog
  omarchy-system-lock
  omarchy-apply-lock
  omarchy-system-logout
  omarchy-system-reboot
  omarchy-system-shutdown
  omarchy-hyprland-window-close-all
  omarchy-state
)
for h in "${staged[@]}"; do
  assert_file_exists "$bin/$h" "세션/바 스테이징: $h"
  [[ -x $bin/$h ]] && x=0 || x=1
  assert_eq "$x" "0" "실행 가능: $h"
  if cmp -s "$src/bin/$h" "$bin/$h"; then x=0; else x=1; fi
  assert_eq "$x" "0" "verbatim: $h 는 업스트림과 바이트 동일"
done

# factory-reset 은 Omarchy ISO @factory 전제 — PATH 에 올리지 않는다.
# toggle-bar 는 가시성 토글이며 이번 범위가 아니다.
for h in omarchy-system-factory-reset omarchy-system-factory-reset-finish \
         omarchy-toggle-bar; do
  [[ -e $bin/$h ]] && x=1 || x=0
  assert_eq "$x" "0" "미스테이징: $h"
done

# 기존 의존 — 중복 추가 없이 이미 있어야 한다.
for h in omarchy-osd omarchy-cmd-present; do
  assert_file_exists "$bin/$h" "기존 stage 의존: $h"
done

exit "$ASSERT_FAILURES"
