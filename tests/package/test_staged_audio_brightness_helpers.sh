#!/usr/bin/env bash
# Former M10 Tier C audio/brightness closures + touchpad/touchscreen guards.
# Verbatim stage only — hw-laptop / monitor-internal stay out (need wrappers).
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

staged=(
  omarchy-audio-output-switch
  omarchy-audio-output-set-default
  omarchy-audio-tuning
  omarchy-hw-match
  omarchy-restart-audio
  omarchy-brightness-display
  omarchy-brightness-display-ddc
  omarchy-brightness-display-apple
  omarchy-hw-display
  omarchy-hyprland-monitor-focused
  omarchy-hyprland-monitor-focused-apple
  omarchy-hw-touchpad
  omarchy-hw-touchscreen
  omarchy-toggle-touchpad
  omarchy-toggle-touchscreen
  omarchy-toggle-input-device
)
for h in "${staged[@]}"; do
  assert_file_exists "$bin/$h" "audio/brightness/input 스테이징: $h"
  [[ -x $bin/$h ]] && x=0 || x=1
  assert_eq "$x" "0" "실행 가능: $h"
  if cmp -s "$src/bin/$h" "$bin/$h"; then x=0; else x=1; fi
  assert_eq "$x" "0" "verbatim: $h 는 업스트림과 바이트 동일"
done

# audio-tuning on 이 $OMARCHY_PATH 에서 읽는 템플릿. 패키지는 사용자
# ~/.config/pipewire 나 systemd --user 유닛을 만들지 않는다.
assert_file_exists "$root/default/audio/filter-chain-host.conf" \
  "default/audio/filter-chain-host.conf 스테이징"
assert_file_exists "$root/default/audio/tunings/dell-xps-2026/tuning.conf" \
  "default/audio/tunings 스테이징"
assert_file_exists "$root/default/systemd/user/omarchy-speaker-tuning.service" \
  "speaker-tuning unit 템플릿 스테이징"
if cmp -s "$src/default/systemd/user/omarchy-speaker-tuning.service" \
         "$root/default/systemd/user/omarchy-speaker-tuning.service"; then
  x=0
else
  x=1
fi
assert_eq "$x" "0" "verbatim: speaker-tuning unit 템플릿"

# 기존 의존 — 중복 추가 없이 이미 있어야 한다.
for h in omarchy-osd omarchy-audio-output-sink omarchy-cmd-present; do
  assert_file_exists "$bin/$h" "기존 stage 의존: $h"
done

# 0.8.0 하이프랜드 토글 묶음 + hw 가드 회수 — verbatim 스테이징.
# omarchy-hyprland-toggle 의 on() 이 $OMARCHY_PATH/default/hypr/toggles/$FLAG.lua
# 를 복사하므로 토글 데이터도 같이 올라간다.
hyprland_toggles=(
  omarchy-hyprland-window-gaps-toggle
  omarchy-hyprland-window-single-square-aspect-toggle
  omarchy-hyprland-workspace-layout-toggle
  omarchy-hyprland-monitor-internal
  omarchy-hyprland-monitor-internal-mirror
  omarchy-hyprland-toggle
  omarchy-hyprland-toggle-enabled
  omarchy-hyprland-toggle-disabled
  omarchy-hyprland-monitor-laptop
  omarchy-hyprland-monitor-external-active
  omarchy-hw-laptop
  omarchy-hw-webcam
  omarchy-hw-dell-xps-haptic-touchpad
)
for h in "${hyprland_toggles[@]}"; do
  assert_file_exists "$bin/$h" "0.8.0 토글/hw 스테이징: $h"
  [[ -x $bin/$h ]] && x=0 || x=1
  assert_eq "$x" "0" "실행 가능: $h"
  if cmp -s "$src/bin/$h" "$bin/$h"; then x=0; else x=1; fi
  assert_eq "$x" "0" "verbatim: $h 는 업스트림과 바이트 동일"
done

# 토글 데이터 — 정적 lua 스니펫 3개. omarchy-hyprland-toggle:18 FLAG_SOURCE.
for f in flags.lua single-window-aspect-ratio.lua window-no-gaps.lua; do
  assert_file_exists "$root/default/hypr/toggles/$f" "토글 데이터 스테이징: $f"
  if cmp -s "$src/default/hypr/toggles/$f" "$root/default/hypr/toggles/$f"; then x=0; else x=1; fi
  assert_eq "$x" "0" "verbatim: toggles/$f 는 업스트림과 바이트 동일"
done

# 래퍼/적응이 필요하거나 전체 OS 가정인 것은 올리지 않는다.
for h in omarchy-system-factory-reset omarchy-system-factory-reset-finish; do
  [[ -e $bin/$h ]] && x=1 || x=0
  assert_eq "$x" "0" "미스테이징: $h"
done

# crash-watch 등 다른 user unit 템플릿은 올리지 않는다.
[[ -e $root/default/systemd/user/omarchy-crash-watch.service ]] && x=1 || x=0
assert_eq "$x" "0" "미스테이징: omarchy-crash-watch.service"

exit "$ASSERT_FAILURES"
