#!/usr/bin/env bash
# Runs every tests/**/test_*.sh in an isolated HOME. Exit 0 = all green.
set -uo pipefail
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export REPO_ROOT

only=${1:-}
failed=0
total=0

while IFS= read -r t; do
  [[ -n $only && $t != *"$only"* ]] && continue
  total=$((total + 1))
  sandbox=$(mktemp -d "${TMPDIR:-/tmp}/coo-test-XXXXXX")
  printf '\n=== %s ===\n' "${t#"$REPO_ROOT"/}"
  if HOME="$sandbox" \
     XDG_CONFIG_HOME="$sandbox/.config" \
     XDG_DATA_HOME="$sandbox/.local/share" \
     XDG_STATE_HOME="$sandbox/.local/state" \
     COO_TEST_SANDBOX="$sandbox" \
     bash "$t"; then
    printf 'PASS %s\n' "${t#"$REPO_ROOT"/}"
  else
    printf 'FAIL %s\n' "${t#"$REPO_ROOT"/}"
    failed=$((failed + 1))
  fi
  rm -rf "$sandbox"
done < <(find "$REPO_ROOT/tests" -name 'test_*.sh' -type f | sort)

printf '\n%d/%d test files passed\n' "$((total - failed))" "$total"
[[ $failed -eq 0 ]]
