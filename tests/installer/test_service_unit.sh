#!/usr/bin/env bash
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/lib/common.sh"
source "$REPO_ROOT/lib/env.sh"
source "$REPO_ROOT/lib/autostart.sh"

unit=$(coo_render_service_unit "%h/.local/bin/coo-shell-daemon")
assert_contains "$unit" "Description=Cachy Omarchy Overlay Shell" "unit description"
assert_contains "$unit" "After=graphical-session.target"          "unit ordering"
assert_contains "$unit" "ExecStart=%h/.local/bin/coo-shell-daemon" "unit ExecStart"
assert_contains "$unit" "Restart=on-failure"                       "unit restart policy"
assert_contains "$unit" "RestartSec=1"                             "unit restart delay"
assert_contains "$unit" "WantedBy=default.target"                  "unit install target"

# Idempotency: first write reports changed, second reports unchanged.
dest="$XDG_CONFIG_HOME/systemd/user"
coo_install_service "$dest" "%h/.local/bin/coo-shell-daemon"; first=$?
assert_eq "$first" "10" "first install reports changed"
assert_file_exists "$dest/coo-shell.service" "unit file written"

coo_install_service "$dest" "%h/.local/bin/coo-shell-daemon"; second=$?
assert_eq "$second" "0" "second install reports unchanged"

count=$(grep -c '^\[Service\]$' "$dest/coo-shell.service")
assert_eq "$count" "1" "unit file has exactly one [Service] section"

# A changed ExecStart must rewrite rather than append.
coo_install_service "$dest" "%h/.local/bin/other"; third=$?
assert_eq "$third" "10" "changed ExecStart reports changed"
count=$(grep -c '^ExecStart=' "$dest/coo-shell.service")
assert_eq "$count" "1" "unit file has exactly one ExecStart"

# The repo template and the renderer must not drift apart.
tmpl_exec=$(grep '^ExecStart=' "$REPO_ROOT/systemd/coo-shell.service")
assert_contains "$tmpl_exec" "coo-shell" "template ExecStart references coo-shell"

exit "$ASSERT_FAILURES"
