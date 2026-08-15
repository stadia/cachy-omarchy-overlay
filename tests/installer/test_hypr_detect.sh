#!/usr/bin/env bash
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/lib/common.sh"
source "$REPO_ROOT/lib/env.sh"

cfg="$XDG_CONFIG_HOME/hypr"
mkdir -p "$cfg"

# No config at all.
out=$(coo_detect_hypr_config); code=$?
assert_eq "$code" "1" "no config -> exit 1"
assert_eq "$out" "" "no config -> empty output"

# conf only.
: > "$cfg/hyprland.conf"
assert_eq "$(coo_detect_hypr_config)" "$cfg/hyprland.conf" "detects hyprland.conf"
assert_eq "$(coo_hypr_config_format "$cfg/hyprland.conf")" "conf" "conf format"

# lua wins when both exist, matching Hyprland's own precedence.
: > "$cfg/hyprland.lua"
assert_eq "$(coo_detect_hypr_config)" "$cfg/hyprland.lua" "lua takes precedence"
assert_eq "$(coo_hypr_config_format "$cfg/hyprland.lua")" "lua" "lua format"

# Snippets.
conf_snip=$(coo_hypr_overlay_snippet conf "/home/u/.config/cachy-omarchy-overlay/hypr/overlay.conf")
assert_eq "$conf_snip" \
  'source = /home/u/.config/cachy-omarchy-overlay/hypr/overlay.conf' \
  "conf snippet"

# The Lua snippet's contract is the whole block, not just "contains dofile":
# a bare dofile of a missing file aborts the user's entire config, so the
# guard, the scoping `do ... end`, and the diagnosable tagged stderr line are
# all part of what this function promises. Assert the exact text.
lua_snip=$(coo_hypr_overlay_snippet lua "/home/u/.config/cachy-omarchy-overlay/hypr/overlay.lua")
expected_lua_snip=$(printf '%s\n' \
  'do' \
  '  local ok, err = pcall(dofile, "/home/u/.config/cachy-omarchy-overlay/hypr/overlay.lua")' \
  '  if not ok then io.stderr:write("[cachy-omarchy-overlay] overlay failed to load: " .. tostring(err) .. "\n") end' \
  'end')
assert_eq "$lua_snip" "$expected_lua_snip" "lua snippet is a guarded, diagnosable dofile"

# The pieces the above depends on, called out so a failure says which promise broke.
assert_contains "$lua_snip" 'pcall(dofile, ' "lua snippet guards dofile with pcall"
assert_contains "$lua_snip" '/home/u/.config/cachy-omarchy-overlay/hypr/overlay.lua' "lua snippet path"
assert_contains "$lua_snip" "[$COO_NAME] overlay failed to load" "lua snippet failure is diagnosable"

# Markers are comment syntax, and Lua's comment is '--', not '#'. A '#' marker
# anywhere but line 1 of a .lua config is "unexpected symbol near '#'" and
# takes the user's whole Hyprland config down with it.
assert_eq "$(coo_hypr_marker_begin conf)" "$COO_MARKER_BEGIN" "conf begin marker is verbatim"
assert_eq "$(coo_hypr_marker_end conf)" "$COO_MARKER_END" "conf end marker is verbatim"
assert_eq "$(coo_hypr_marker_begin lua)" '-- >>> cachy-omarchy-overlay >>>' "lua begin marker is a Lua comment"
assert_eq "$(coo_hypr_marker_end lua)" '-- <<< cachy-omarchy-overlay <<<' "lua end marker is a Lua comment"

# The payload must stay identical across formats so one scan finds both.
assert_eq "$(coo_hypr_marker_begin lua)" "--${COO_MARKER_BEGIN#\#}" "lua marker keeps the shared payload"

# An unknown format must be fatal, not silently treated as conf. Markers are
# written BEFORE the body, so a fallback would put a '#' line into a Lua config
# and only then die on the body -- a half-written block that breaks the config.
# Subshells, not assert_exit: `die` calls `exit`, which from a plain function
# call would terminate this test script instead of being observed.
( coo_hypr_marker_begin bogus ) >/dev/null 2>&1
assert_eq "$?" "1" "unknown format is fatal for the begin marker"
( coo_hypr_marker_end bogus ) >/dev/null 2>&1
assert_eq "$?" "1" "unknown format is fatal for the end marker"
( coo_hypr_overlay_snippet bogus /tmp/x ) >/dev/null 2>&1
assert_eq "$?" "1" "unknown format is fatal for the snippet"
# And nothing may be emitted before dying -- a partial write is the whole risk.
assert_eq "$( ( coo_hypr_marker_begin bogus ) 2>/dev/null )" "" "fatal format emits nothing"

# A quote or backslash in the path is a SYNTAX error in the emitted Lua block,
# which pcall cannot catch -- it guards the load, not the parse. Unescaped, this
# would abort the user's whole config, which is worse than `source =` degrades.
weird='/home/u/we"ird\path/overlay.lua'
weird_snip=$(coo_hypr_overlay_snippet lua "$weird")
assert_contains "$weird_snip" 'pcall(dofile, "/home/u/we\"ird\\path/overlay.lua")' \
  "lua snippet escapes quotes and backslashes in the path"

# And prove it is really valid Lua, not just escaped-looking, when luac is here.
if have_cmd luac; then
  weird_probe="$COO_TEST_SANDBOX/weird.lua"
  { coo_hypr_marker_begin lua; printf '%s\n' "$weird_snip"; coo_hypr_marker_end lua; } > "$weird_probe"
  assert_exit 0 "emitted block with a quoted/backslashed path is valid Lua" \
    luac -p "$weird_probe"
else
  echo "note: luac not installed, skipping the Lua syntax check"
fi

exit "$ASSERT_FAILURES"
