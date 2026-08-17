#!/usr/bin/env bash
# M10 utility plugin helper closure 스테이징과 P01(default-enabled) 회귀를 검증한다.
# 목록의 근거: M10 설계 문서 §3 (Tier A) — clipboard open 전이 closure,
# input-mute 의 keyboard-mute no-op closure, OSD audio core.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

src=${COO_OMARCHY_GIT:-$REPO_ROOT/build/omarchy}
[[ -d $src ]] || { echo "skip: 업스트림 클론 없음"; exit 0; }

stage=$COO_TEST_SANDBOX/pkg
bash "$REPO_ROOT/packages/cachy-omarchy-shell/stage-upstream.sh" "$src" "$stage" \
  "$REPO_ROOT/overlay/defaults"
bin="$stage/usr/share/cachy-omarchy/upstream/bin"

# Tier A — M10 verbatim stage (14개). 전부 upstream 과 바이트 동일해야 한다.
tier_a=(
  omarchy-menu-clipboard
  omarchy-clipboard-open
  omarchy-clipboard-paste-text
  omarchy-clipboard-paste-file
  omarchy-launch-browser
  omarchy-launch-editor
  omarchy-launch-tui
  omarchy-hyprland-focus-app
  omarchy-menu-emoji
  omarchy-menu-emoji-insert
  omarchy-osd
  omarchy-audio-output-volume
  omarchy-audio-input-mute
  omarchy-brightness-keyboard-mute
)
for h in "${tier_a[@]}"; do
  assert_file_exists "$bin/$h" "M10 Tier A 스테이징: $h"
  [[ -x $bin/$h ]] && x=0 || x=1
  assert_eq "$x" "0" "실행 가능: $h"
  if cmp -s "$src/bin/$h" "$bin/$h"; then x=0; else x=1; fi
  assert_eq "$x" "0" "verbatim: $h 는 업스트림과 바이트 동일"
done

# 기존 stage 의존 (M8/M9) — 중복 추가 없이 이미 있어야 한다.
for h in omarchy-menu-images omarchy-reminder omarchy-notification-send \
         omarchy-audio-output-sink omarchy-cmd-present ; do
  assert_file_exists "$bin/$h" "기존 stage 의존: $h"
done

# M10 Tier C — 넣지 않는다 (audio-tuning 정책 표면, display brightness 체인, power).
for h in omarchy-audio-output-switch omarchy-audio-tuning \
         omarchy-brightness-display omarchy-brightness-display-ddc \
         omarchy-hw-display omarchy-system-logout ; do
  [[ -e $bin/$h ]] && x=1 || x=0
  assert_eq "$x" "0" "M10 Tier C 미스테이징: $h"
done

# P01 회귀 — five first-party plugin 이 upstream 규칙대로 default-enabled 인 채로
# 유지되는지 단언한다. shell.json 에 disabledPlugins 가 생기거나 plugins 목록이
# 바뀌면 M10 의 전제(이미 기본 로드)가 깨진다.
shell_json="$REPO_ROOT/overlay/defaults/shell.json"
if grep -q '"disabledPlugins"' "$shell_json"; then x=1; else x=0; fi
assert_eq "$x" "0" "P01: shell.json 에 disabledPlugins 없음"
plugins=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["plugins"])' "$shell_json")
assert_eq "$plugins" "[]" "P01: shell.json plugins 는 [] (first-party non-bar 기본 활성)"

for p in clipboard emojis image-picker reminders osd; do
  m="$stage/usr/share/cachy-omarchy/upstream/shell/plugins/$p/manifest.json"
  assert_file_exists "$m" "P01: manifest 존재 — omarchy.$p"
  if [[ -f $m ]]; then
    keep=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("keepLoaded"))' "$m")
    assert_eq "$keep" "True" "P01: keepLoaded — omarchy.$p"
  fi
done

exit "$ASSERT_FAILURES"
