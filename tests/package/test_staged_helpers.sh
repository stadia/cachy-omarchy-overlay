#!/usr/bin/env bash
# 바 위젯이 부르는 업스트림 helper 가 스테이징되는지 검증한다.
# 목록의 근거: M8 평가 문서 "helper 처리 방침" (Tier A/B).
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

src=${COO_OMARCHY_GIT:-$REPO_ROOT/build/omarchy}
[[ -d $src ]] || { echo "skip: 업스트림 클론 없음"; exit 0; }

stage=$COO_TEST_SANDBOX/pkg
bash "$REPO_ROOT/packages/cachy-omarchy-shell/stage-upstream.sh" "$src" "$stage" \
  "$REPO_ROOT/overlay/defaults"

bin="$stage/usr/share/cachy-omarchy/upstream/bin"

# Tier A — 의존 명령이 CachyOS 기본 설치에 있는 것들
for h in omarchy-menu-select omarchy-cmd-present \
         omarchy-audio-output-sink omarchy-network-status \
         omarchy-network-band omarchy-monitor-state \
         omarchy-hyprland-monitor-scaling ; do
  assert_file_exists "$bin/$h" "Tier A 스테이징: $h"
  [[ -x $bin/$h ]] && x=0 || x=1
  assert_eq "$x" "0" "실행 가능: $h"
done

# verbatim 이어야 한다 — 적응 카피는 overlay/bin 으로 가고 compat PATH 가 이긴다.
# 여기서 조용히 갈라지면 업스트림 리베이스가 그 사실을 숨긴다.
for h in omarchy-audio-output-sink omarchy-monitor-state ; do
  if cmp -s "$src/bin/$h" "$bin/$h"; then x=0; else x=1; fi
  assert_eq "$x" "0" "verbatim: $h 는 업스트림과 바이트 동일"
done

# Tier B — 기능 단위 묶음. reminders 는 omarchy-shell(우리 compat shim)과
# systemd 유저 타이머만 쓰고, agents 수집기는 해당 CLI 가 없으면 조용히 빈다.
for h in omarchy-reminder omarchy-notification-send \
         omarchy-agent-usage-update omarchy-agent-usage-claude \
         omarchy-agent-usage-codex omarchy-agent-usage-fireworks ; do
  assert_file_exists "$bin/$h" "Tier B 스테이징: $h"
  [[ -x $bin/$h ]] && x=0 || x=1
  assert_eq "$x" "0" "실행 가능: $h"
done

# 바 monitor 위젯이 부르는 밝기 체인 — 채택 후 업스트림과 바이트 동일.
for h in omarchy-brightness-display omarchy-brightness-display-ddc \
         omarchy-hw-display ; do
  assert_file_exists "$bin/$h" "밝기 체인 스테이징: $h"
  if cmp -s "$src/bin/$h" "$bin/$h"; then x=0; else x=1; fi
  assert_eq "$x" "0" "verbatim: $h 는 업스트림과 바이트 동일"
done

exit "$ASSERT_FAILURES"
