#!/usr/bin/env bash
# PreToolUse hook: forbid Edit/Write/MultiEdit to the user's LIVE Hyprland
# config. This is the project's #1 safety rule (~/.config/hypr/** is never
# edited directly -- only the project overlay at ~/.config/cachy-omarchy-overlay/
# and sandbox fixtures under tests/). Enforced mechanically so no session,
# human-driven or subagent, can brick the user's desktop config by accident.
#
# Fails OPEN: any parse error or missing file_path -> exit 0 (allow). Only an
# unambiguous match under $HOME/.config/hypr/ is blocked via exit 2 (stderr is
# surfaced to the caller).
set -uo pipefail

input=$(cat)
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -n $file_path ]] || exit 0

# Resolve to an absolute path before matching, so relative paths can't dodge it.
case "$file_path" in
  /*) abs=$file_path ;;
  *)  abs=$PWD/$file_path ;;
esac

case "$abs" in
  "$HOME"/.config/hypr/*)
    printf '차단: 사용자 Hyprland 설정(%s)은 직접 편집할 수 없습니다.\n' "$abs" >&2
    printf '      프로젝트 오버레이(~/.config/cachy-omarchy-overlay/hypr/) 또는 테스트 픽스처(tests/fixtures/hypr/)를 사용하세요.\n' >&2
    exit 2
    ;;
esac

exit 0