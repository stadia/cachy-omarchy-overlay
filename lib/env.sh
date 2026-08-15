#!/usr/bin/env bash
# Environment and Hyprland-config detection. Sourced, never executed.
# Requires lib/common.sh to have been sourced first.

coo_config_home() { printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}"; }
coo_data_home()   { printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}"; }
coo_state_home()  { printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}"; }

coo_config_root() { printf '%s/%s\n' "$(coo_config_home)" "$COO_NAME"; }
coo_data_root()   { printf '%s/%s\n' "$(coo_data_home)" "$COO_NAME"; }
coo_state_root()  { printf '%s/%s\n' "$(coo_state_home)" "$COO_NAME"; }

# Hyprland 0.56 loads exactly one root config. A Lua config takes precedence
# over the classic conf when both are present, so detection must match.
coo_detect_hypr_config() {
  local dir; dir="$(coo_config_home)/hypr"
  local candidate
  for candidate in "$dir/hyprland.lua" "$dir/hyprland.conf"; do
    if [[ -f $candidate ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

coo_hypr_config_format() {
  case $1 in
    *.lua) printf 'lua\n' ;;
    *)     printf 'conf\n' ;;
  esac
}

# The managed-block markers, per config format.
#
# COO_MARKER_BEGIN/END in lib/common.sh lead with '#', which is a comment in
# Hyprland's classic .conf but the length operator in Lua: a '#' marker on any
# line but the first aborts the whole root config with
# "unexpected symbol near '#'" (verified with Hyprland 0.56.2 --verify-config).
# Only the comment lead-in changes; the marker payload stays byte-identical in
# both formats so the installer's idempotency scan remains a single rule.
_coo_hypr_marker() {
  local marker=$1 format=$2
  case $format in
    lua) printf -- '--%s\n' "${marker#\#}" ;;
    *)   printf '%s\n' "$marker" ;;
  esac
}

coo_hypr_marker_begin() { _coo_hypr_marker "$COO_MARKER_BEGIN" "$1"; }
coo_hypr_marker_end()   { _coo_hypr_marker "$COO_MARKER_END" "$1"; }

# The body of the managed block. Callers wrap it in COO_MARKER_BEGIN/END.
#
# dofile is used for Lua rather than require because it takes a filesystem path
# directly and does not depend on package.path, which Hyprland controls.
# Verified against Hyprland 0.56.2: the Lua config VM is stock Lua 5.5 with
# dofile/loadfile/require present, and package.path is rooted at the directory
# of the root config only -- an out-of-tree overlay is not reachable via
# require. See docs/HYPRLAND_INTEGRATION.md.
#
# The dofile is wrapped in pcall to match what Hyprland already does for a
# `source =` pointing at a missing file: measured on 0.56.2, that logs
# "source= globbing error: found no match" and the rest of the config loads
# normally. A bare dofile would instead abort the remaining chunk with a Lua
# traceback, so deleting our directory would take down the user's monitors and
# keybindings. SPEC.md 5.1: the user's config is authoritative, we are a guest.
#
# The failure is deliberately NOT silent -- it writes a line tagged with
# COO_NAME to stderr, which lands in Hyprland's session log. doctor.sh keys off
# that tag. The `do ... end` block keeps our two locals out of the user's chunk.
coo_hypr_overlay_snippet() {
  local format=$1 path=$2
  case $format in
    conf) printf 'source = %s\n' "$path" ;;
    lua)
      printf '%s\n' \
        'do' \
        "  local ok, err = pcall(dofile, \"$path\")" \
        "  if not ok then io.stderr:write(\"[$COO_NAME] overlay failed to load: \" .. tostring(err) .. \"\\n\") end" \
        'end'
      ;;
    *)    die "unknown Hyprland config format: $format" ;;
  esac
}

coo_is_arch_family() {
  [[ -r /etc/os-release ]] || return 1
  local id id_like
  id=$(. /etc/os-release && printf '%s' "${ID:-}")
  id_like=$(. /etc/os-release && printf '%s' "${ID_LIKE:-}")
  [[ $id == arch || $id == cachyos || $id_like == *arch* ]]
}
