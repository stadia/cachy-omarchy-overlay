#!/usr/bin/env bash
# Runs the repository host without installing anything into the real HOME.
# SPEC 31.4: must support an isolated config directory.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$REPO_ROOT/lib/common.sh"
source "$REPO_ROOT/lib/env.sh"

QS=$(coo_quickshell_bin) || die "quickshell is not installed (pacman -S quickshell)"

COO_CONFIG_ROOT=${COO_CONFIG_ROOT:-$REPO_ROOT/.coo-dev/config}
export COO_CONFIG_ROOT
mkdir -p "$COO_CONFIG_ROOT"

# Seed defaults on first run only; never overwrite an existing dev config.
for f in config.jsonc; do
  [[ -f $COO_CONFIG_ROOT/$f ]] || cp "$REPO_ROOT/config/$f" "$COO_CONFIG_ROOT/$f"
done

log "coo-shell (dev): configRoot=$COO_CONFIG_ROOT"
exec "$QS" -p "$REPO_ROOT/shell" "$@"
