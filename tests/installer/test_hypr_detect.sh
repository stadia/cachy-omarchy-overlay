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

lua_snip=$(coo_hypr_overlay_snippet lua "/home/u/.config/cachy-omarchy-overlay/hypr/overlay.lua")
assert_contains "$lua_snip" 'dofile(' "lua snippet uses dofile"
assert_contains "$lua_snip" '/home/u/.config/cachy-omarchy-overlay/hypr/overlay.lua' "lua snippet path"

# Markers are comment syntax, and Lua's comment is '--', not '#'. A '#' marker
# anywhere but line 1 of a .lua config is "unexpected symbol near '#'" and
# takes the user's whole Hyprland config down with it.
assert_eq "$(coo_hypr_marker_begin conf)" "$COO_MARKER_BEGIN" "conf begin marker is verbatim"
assert_eq "$(coo_hypr_marker_end conf)" "$COO_MARKER_END" "conf end marker is verbatim"
assert_eq "$(coo_hypr_marker_begin lua)" '-- >>> cachy-omarchy-overlay >>>' "lua begin marker is a Lua comment"
assert_eq "$(coo_hypr_marker_end lua)" '-- <<< cachy-omarchy-overlay <<<' "lua end marker is a Lua comment"

# The payload must stay identical across formats so one scan finds both.
assert_eq "$(coo_hypr_marker_begin lua)" "--${COO_MARKER_BEGIN#\#}" "lua marker keeps the shared payload"

exit "$ASSERT_FAILURES"
