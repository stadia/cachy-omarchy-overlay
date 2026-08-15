#!/usr/bin/env bash
# Boots a nested headless Hyprland against fixture configs containing the
# managed block, and asserts the overlay file was actually loaded.
#
# SAFETY: every Hyprland invocation here runs under `env -u
# HYPRLAND_INSTANCE_SIGNATURE`, so anything the fixture runs talks to the
# nested instance and never to the user's live session. The only `hyprctl` in
# this file lives inside the conf fixture's own exec-once, executed by the
# nested compositor against itself. Never lift it out into the test shell.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/lib/common.sh"
source "$REPO_ROOT/lib/env.sh"

if ! command -v Hyprland >/dev/null 2>&1; then
  echo "skip: Hyprland not installed"
  exit 0
fi

run_case() {
  local format=$1
  local work="$COO_TEST_SANDBOX/hypr-$format"
  mkdir -p "$work"
  local marker="$work/loaded.marker"
  local overlay root

  if [[ $format == conf ]]; then
    overlay="$work/overlay.conf"
    root="$work/root.conf"
    printf 'exec-once = printf loaded > %s ; hyprctl dispatch exit\n' "$marker" > "$overlay"
    printf 'monitor = HEADLESS-1, 1920x1080@60, 0x0, 1\n' > "$root"
  else
    overlay="$work/overlay.lua"
    root="$work/root.lua"
    # The pure-Lua write proves the file was executed without relying on any
    # hl.* name being correct. Hyprland 0.56.2 has no hl.exec_once; the exit is
    # driven by hl.on + hl.dispatch, which never spawns a shell at all.
    {
      printf 'local f = io.open("%s", "w")\n' "$marker"
      printf 'if f then f:write("loaded") f:close() end\n'
      printf 'hl.on("hyprland.start", function() hl.dispatch(hl.dsp.exit()) end)\n'
    } > "$overlay"
    printf 'hl.monitor({ output = "HEADLESS-1", mode = "1920x1080@60", position = "0x0", scale = 1 })\n' > "$root"
  fi

  {
    coo_hypr_marker_begin "$format"
    coo_hypr_overlay_snippet "$format" "$overlay"
    coo_hypr_marker_end "$format"
  } >> "$root"

  # Gate 1: Hyprland's own parser must accept the managed block. This is what
  # catches a marker written in the wrong comment syntax for the format.
  local verify
  verify=$(env -u HYPRLAND_INSTANCE_SIGNATURE \
             timeout 25s Hyprland --verify-config -c "$root" 2>&1)
  assert_contains "$verify" "config ok" "$format managed block parses (--verify-config)"

  # For .lua, --verify-config already executes the config, and with it the
  # overlay. Clear the marker so the boot below proves itself.
  rm -f "$marker"

  # Gate 2: a real compositor boot actually executes the overlay.
  env -u HYPRLAND_INSTANCE_SIGNATURE \
      WLR_BACKENDS=headless WLR_RENDERER=pixman \
      timeout 25s Hyprland -c "$root" > "$work/hyprland.log" 2>&1

  assert_file_exists "$marker" "$format overlay was loaded by Hyprland"
  if [[ ! -f $marker ]]; then
    # Hyprland silences stdout early and writes the rest to its per-instance
    # log, so --verify-config output is the far more useful diagnostic here.
    printf '      --- Hyprland --verify-config ---\n'
    printf '%s\n' "$verify" | tail -5 | sed 's/^/      /'
    printf '      --- hyprland.log tail ---\n'
    tail -20 "$work/hyprland.log" | sed 's/^/      /'
  fi
}

# A managed block pointing at an overlay that does not exist must degrade, not
# detonate: the rest of the user's config has to keep loading. The proof is a
# marker written by the root config on the line AFTER the managed block, so it
# can only appear if execution got past our block. This is the same technique
# that catches a marker written in the wrong comment syntax.
run_missing_overlay_case() {
  local format=$1
  local work="$COO_TEST_SANDBOX/hypr-missing-$format"
  mkdir -p "$work"
  local after="$work/after.marker"
  local root overlay
  # Deliberately never created.
  overlay="$work/definitely-absent-overlay.$format"

  if [[ $format == conf ]]; then
    root="$work/root.conf"
    printf 'monitor = HEADLESS-1, 1920x1080@60, 0x0, 1\n' > "$root"
  else
    root="$work/root.lua"
    printf 'hl.monitor({ output = "HEADLESS-1", mode = "1920x1080@60", position = "0x0", scale = 1 })\n' > "$root"
  fi

  {
    coo_hypr_marker_begin "$format"
    coo_hypr_overlay_snippet "$format" "$overlay"
    coo_hypr_marker_end "$format"
  } >> "$root"

  # Everything below here is user config that must survive our broken block.
  if [[ $format == conf ]]; then
    printf 'exec-once = printf after > %s ; hyprctl dispatch exit\n' "$after" >> "$root"
  else
    {
      printf 'local f = io.open("%s", "w")\n' "$after"
      printf 'if f then f:write("after") f:close() end\n'
      printf 'hl.on("hyprland.start", function() hl.dispatch(hl.dsp.exit()) end)\n'
    } >> "$root"
  fi

  env -u HYPRLAND_INSTANCE_SIGNATURE \
      WLR_BACKENDS=headless WLR_RENDERER=pixman \
      timeout 25s Hyprland -c "$root" > "$work/hyprland.log" 2>&1

  assert_file_exists "$after" "$format config keeps loading past a missing overlay"
  if [[ ! -f $after ]]; then
    printf '      --- hyprland.log tail ---\n'
    tail -20 "$work/hyprland.log" | sed 's/^/      /'
  fi
}

# docs/HYPRLAND_INTEGRATION.md 4.2 claims a .conf config yields a usable
# dispatcher, arg and bindd description from `hyprctl binds -j`, whereas a .lua
# config reports dispatcher "__lua" with an opaque arg. The .lua half was
# measured on the live session; this measures the .conf half rather than
# inheriting it, because Milestone 6's whole viewer design rests on it.
#
# hyprctl runs inside the nested instance via exec-once, so it reads that
# instance's own binds. It never addresses the user's session.
run_conf_binds_introspection_case() {
  local work="$COO_TEST_SANDBOX/hypr-binds-conf"
  mkdir -p "$work"
  local out="$work/binds.json"
  local root="$work/root.conf"

  {
    printf 'monitor = HEADLESS-1, 1920x1080@60, 0x0, 1\n'
    printf '$mainMod = SUPER\n'
    printf 'bind = $mainMod, Return, exec, ghostty\n'
    printf 'binde = $mainMod, minus, layoutmsg, splitratio -0.1\n'
    printf 'bindr = $mainMod, SUPER_L, exec, echo released\n'
    printf 'bindd = $mainMod, K, Show keybindings, exec, coo-keybindings\n'
    printf 'exec-once = hyprctl binds -j > %s ; hyprctl dispatch exit\n' "$out"
  } > "$root"

  env -u HYPRLAND_INSTANCE_SIGNATURE \
      timeout 25s Hyprland -c "$root" > "$work/hyprland.log" 2>&1

  assert_file_exists "$out" "conf instance produced hyprctl binds output"
  local j; j=$(cat "$out" 2>/dev/null)

  # A real dispatcher name, not the "__lua" placeholder a Lua config reports.
  assert_contains "$j" '"dispatcher": "exec"' "conf binds report a real dispatcher"
  # The real argument, with $mainMod-style variables already resolved.
  assert_contains "$j" '"arg": "ghostty"' "conf binds report a usable arg"
  # bindd's description survives all the way to hyprctl.
  assert_contains "$j" '"description": "Show keybindings"' "conf bindd description surfaces"
  assert_contains "$j" '"has_description": true' "conf bindd sets has_description"
  # Flags shared with the .lua path.
  assert_contains "$j" '"repeat": true' "binde sets repeat"
  assert_contains "$j" '"release": true' "bindr sets release"
  assert_contains "$j" '"modmask": 64' "SUPER decodes to modmask 64 in conf too"
}

run_case conf
run_case lua
run_missing_overlay_case conf
run_missing_overlay_case lua
run_conf_binds_introspection_case

# The Lua guard must stay diagnosable: doctor.sh keys off this tag. Silence
# would satisfy "config keeps loading" while hiding a broken install.
# No `if` around this: a conditional would let the assertion vanish silently if
# the log ever stopped being produced, turning a real regression into a pass.
missing_lua_log="$COO_TEST_SANDBOX/hypr-missing-lua/hyprland.log"
assert_file_exists "$missing_lua_log" "missing-overlay lua run produced a log"
assert_contains "$(cat "$missing_lua_log" 2>/dev/null)" \
  "[$COO_NAME] overlay failed to load" \
  "lua guard logs a tagged diagnostic when the overlay is missing"

exit "$ASSERT_FAILURES"
