#!/usr/bin/env bash
# PostToolUse hook: after Edit/Write/MultiEdit, run `bash -n` on the changed
# file if it is a bash script -- by extension or, for the extension-less
# commands under bin/ and overlay/bin/, by shebang. NON-BLOCKING: always exits
# 0; output (only on real findings) is fed back to Claude as feedback.
set -uo pipefail

input=$(cat)
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -n $file_path ]] || exit 0
[[ -f $file_path ]] || exit 0

is_bash=0
case "$file_path" in
  *.sh) is_bash=1 ;;
  *) head -n1 -- "$file_path" 2>/dev/null | grep -qE '^#!.*\bbash\b' && is_bash=1 ;;
esac
(( is_bash )) || exit 0
out=$(bash -n "$file_path" 2>&1)
if [[ -n $out ]]; then
  printf 'bash -n(%s):\n%s\n' "$file_path" "$out" >&2
fi

exit 0
