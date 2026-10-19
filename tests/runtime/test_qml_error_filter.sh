#!/usr/bin/env bash
# The Qt >= 6.12 startup-burst exclusion must stay as narrow as documented.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/tests/lib/qml_errors.sh"

log=$COO_TEST_SANDBOX/qml.log
burst="WARN scene: @Ui/Button.qml[57:-1]: TypeError: Cannot read property 'background' of undefined"
printf '\033[33m  WARN\033[97m scene\033[0m: @Ui/Button.qml[58:-1]: TypeError: Cannot read property '"'"'text'"'"' of undefined\n' > "$log"
printf '%s\n' "$burst" >> "$log"

COO_QT_VERSION=6.12.0
assert_eq "$(coo_count_qml_errors "$log")" "0" "Qt 6.12: the known startup burst is excluded (colored and plain)"

COO_QT_VERSION=6.11.2
assert_eq "$(coo_count_qml_errors "$log")" "2" "Qt 6.11: nothing is excluded"

COO_QT_VERSION=6.12.0
printf 'WARN scene: @Ui/Button.qml[9:3]: ReferenceError: foo is not defined\n' >> "$log"
printf 'WARN scene: @Ui/Button.qml[9:3]: TypeError: Cannot read property '"'"'x'"'"' of null\n' >> "$log"
printf 'WARN scene: @Ui/Button.qml[9:3]: TypeError: undefined is not a function\n' >> "$log"
assert_eq "$(coo_count_qml_errors "$log")" "3" "Qt 6.12: other error shapes still count"

# Near misses: a column other than -1, trailing text, and a property outside the
# measured colour-token set must all keep counting.
COO_QT_VERSION=6.12.0
printf 'WARN scene: @Ui/Button.qml[58:3]: TypeError: Cannot read property '"'"'text'"'"' of undefined\n' > "$log"
assert_eq "$(coo_count_qml_errors "$log")" "1" "Qt 6.12: a real column (not -1) still counts"
printf 'WARN scene: @Ui/Button.qml[58:-1]: TypeError: Cannot read property '"'"'text'"'"' of undefined (extra)\n' > "$log"
assert_eq "$(coo_count_qml_errors "$log")" "1" "Qt 6.12: trailing text still counts"
printf 'WARN scene: @plugins/foo/Panel.qml[8:-1]: TypeError: Cannot read property '"'"'items'"'"' of undefined\n' > "$log"
assert_eq "$(coo_count_qml_errors "$log")" "1" "Qt 6.12: a property outside the colour-token set still counts"
printf 'WARN scene: @Commons/Border.qml[3:-1]: TypeError: Cannot read property '"'"'menu.border-alpha'"'"' of undefined\n' > "$log"
assert_eq "$(coo_count_qml_errors "$log")" "0" "Qt 6.12: a measured dotted token is excluded"

exit "$ASSERT_FAILURES"
