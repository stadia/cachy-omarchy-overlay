#!/usr/bin/env bash
# M9 테마 체인 helper 의 스테이징/미스테이징을 검증한다.
# 목록의 근거: M9 설계 문서 "helper 분류" (Tier A/B/C).
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

src=${COO_OMARCHY_GIT:-$REPO_ROOT/build/omarchy}
[[ -d $src ]] || { echo "skip: 업스트림 클론 없음"; exit 0; }

stage=$COO_TEST_SANDBOX/pkg
bash "$REPO_ROOT/packages/cachy-omarchy-shell/stage-upstream.sh" "$src" "$stage" \
  "$REPO_ROOT/overlay/defaults"
bin="$stage/usr/share/cachy-omarchy/upstream/bin"

# Tier A — 코어 체인 + 배경 묶음 + 메뉴 UI 프론트
for h in omarchy-theme-set omarchy-theme-set-templates omarchy-theme-color \
         omarchy-theme-list omarchy-theme-current omarchy-theme-osc \
         omarchy-theme-colors-from-alacritty omarchy-hook \
         omarchy-restart-terminal omarchy-restart-hyprctl \
         omarchy-restart-btop omarchy-restart-opencode omarchy-restart-helix \
         omarchy-menu-images \
         omarchy-theme-switcher omarchy-theme-bg-set omarchy-theme-bg-next \
         omarchy-theme-bg-current omarchy-theme-bg-switcher \
         omarchy-theme-bg-cache ; do
  assert_file_exists "$bin/$h" "Tier A 스테이징: $h"
  [[ -x $bin/$h ]] && x=0 || x=1
  assert_eq "$x" "0" "실행 가능: $h"
done

# Tier B — post-theme 훅. 사용자 홈만 건드리고 대상 앱이 없으면 조용히 종료.
# browser(/etc 정책 쓰기)와 keyboard(특정 하드웨어)만 제외한다 (설계 문서 D3).
for h in omarchy-theme-set-foot omarchy-theme-set-tmux \
         omarchy-theme-set-gnome omarchy-theme-set-pi \
         omarchy-theme-set-claude omarchy-theme-set-vscode \
         omarchy-theme-set-obsidian \
         omarchy-toggle-enabled ; do
  assert_file_exists "$bin/$h" "Tier B 스테이징: $h"
done

# Tier C — 넣지 않는다 (네트워크/전체 OS 가정/하드웨어 전용, 설계 문서 D3).
# 이 단언은 $OMARCHY_PATH/bin (스테이징된 upstream bin) 에만 건다 — 트리
# 전체를 대상으로 하면 Task 3 의 compat no-op shim 2개(browser/keyboard)에
# 걸려 거짓 실패한다. shim 은 stage-overlay.sh 가 compat/bin 에 놓는 우리
# 자산이므로 이 스테이징 산출물에는 애초에 나타나지 않는다 (R02 ①).
for h in omarchy-theme-install omarchy-theme-update omarchy-theme-remove \
         omarchy-theme-bg-install omarchy-plymouth-set-by-theme \
         omarchy-theme-set-browser omarchy-theme-set-keyboard \
         omarchy-theme-set-keyboard-asus-rog omarchy-theme-set-keyboard-f16 \
         omarchy-dev-theme-preview omarchy-dev-benchmark-theme-switcher ; do
  [[ -e $bin/$h ]] && x=1 || x=0
  assert_eq "$x" "0" "Tier C 미스테이징 (upstream/bin): $h"
done

exit "$ASSERT_FAILURES"
