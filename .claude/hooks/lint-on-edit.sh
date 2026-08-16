#!/usr/bin/env bash
# PostToolUse hook: after Edit/Write/MultiEdit, lint the changed file if it is
# QML or bash. NON-BLOCKING: always exits 0; output (only on real findings) is
# fed back to Claude as feedback. Catches the "boolean IPC flipped but the
# LayerShell surface never rendered" class of silent QML failure (M1 Task 6)
# and obvious bash syntax errors, without disrupting the edit flow.
#
# qmllint resolves Quickshell/QtQuick via the Qt6 QML import dir. If that dir
# is absent (non-Arch/CachyOS host), QML linting is skipped silently.
set -uo pipefail

input=$(cat)
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -n $file_path ]] || exit 0
[[ -f $file_path ]] || exit 0

case "$file_path" in
  *.qml)
    qml_dir=/usr/lib/qt6/qml
    [[ -d $qml_dir && $(command -v qmllint) ]] || exit 0
    out=$(qmllint -I "$qml_dir" "$file_path" 2>&1)
    if [[ -n $out ]]; then
      printf 'qmllint(%s):\n%s\n' "$file_path" "$out" >&2
    fi
    ;;
  *.sh)
    [[ $(command -v bash) ]] || exit 0
    out=$(bash -n "$file_path" 2>&1)
    if [[ -n $out ]]; then
      printf 'bash -n(%s):\n%s\n' "$file_path" "$out" >&2
    fi
    ;;
esac

exit 0