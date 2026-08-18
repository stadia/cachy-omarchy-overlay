#!/usr/bin/env bash
# Runs every tests/**/test_*.sh in an isolated HOME. Exit 0 = all green.
# COO_RUN_LIVE=1 ./tests/test.sh includes live key-injection tests (R05/R06 + M4 keybinding UI); default skips them and runs static+startup checks only.
set -uo pipefail
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export REPO_ROOT
source "$REPO_ROOT/tests/lib/sandbox.sh"

only=${1:-}
failed=0
total=0
test_list=$(mktemp "${TMPDIR:-/tmp}/coo-test-list-XXXXXX") || {
  printf 'error: could not create test discovery list\n' >&2
  exit 1
}
trap 'rm -f "$test_list"' EXIT
if ! find "$REPO_ROOT/tests" -name 'test_*.sh' -type f -print | sort > "$test_list"; then
  printf 'error: test discovery failed\n' >&2
  exit 1
fi

while IFS= read -r t; do
  [[ -n $only && $t != *"$only"* ]] && continue
  total=$((total + 1))
  sandbox=$(mktemp -d "${TMPDIR:-/tmp}/coo-test-XXXXXX")
  printf '\n=== %s ===\n' "${t#"$REPO_ROOT"/}"
  if HOME="$sandbox" \
     XDG_CONFIG_HOME="$sandbox/.config" \
     XDG_DATA_HOME="$sandbox/.local/share" \
     XDG_STATE_HOME="$sandbox/.local/state" \
     XDG_CACHE_HOME="$sandbox/.cache" \
     COO_TEST_SANDBOX="$sandbox" \
     bash "$t"; then
    printf 'PASS %s\n' "${t#"$REPO_ROOT"/}"
  else
    printf 'FAIL %s\n' "${t#"$REPO_ROOT"/}"
    failed=$((failed + 1))
  fi
  # Order matters: kill first, then delete.  A watcher left running inside the
  # sandbox does not exit when its directory disappears, so deleting first
  # would strand it for the life of the session (tests/lib/sandbox.sh).
  coo_reap_sandbox_procs "$sandbox"
  rm -rf "$sandbox"
done < "$test_list"

printf '\n%d/%d test files passed\n' "$((total - failed))" "$total"
if [[ $total -eq 0 ]]; then
  printf 'error: no test files matched%s\n' "${only:+ filter: $only}" >&2
  exit 1
fi
[[ $failed -eq 0 ]]
