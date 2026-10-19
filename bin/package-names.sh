#!/usr/bin/env bash
# Current package artifact names, derived from upstream.lock and both
# PKGBUILDs. Source only.

# coo_current_artifacts <repo_root>
# Sets COO_SHELL_ARTIFACT and COO_OVERLAY_ARTIFACT (file names, no directory)
# and the lock's OMARCHY_* variables.
coo_current_artifacts() {
  local root=$1 shell_ver shell_pkg overlay_pkg shell_rel overlay_ver overlay_rel
  shell_pkg=$root/packages/cachy-omarchy-shell/PKGBUILD
  overlay_pkg=$root/packages/cachy-omarchy-overlay/PKGBUILD
  if [[ ! -f $root/upstream.lock || ! -f $shell_pkg || ! -f $overlay_pkg ]]; then
    printf 'error: repository package metadata is incomplete\n' >&2
    return 1
  fi
  # shellcheck disable=SC1091
  source "$root/upstream.lock"
  if [[ ! ${OMARCHY_VERSION:-} =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! ${OMARCHY_COMMIT:-} =~ ^[0-9a-fA-F]{40}$ ]]; then
    printf 'error: invalid upstream.lock\n' >&2
    return 1
  fi
  shell_rel=$(grep -m1 '^pkgrel=' "$shell_pkg" | cut -d= -f2- | tr -d "'\"")
  overlay_ver=$(grep -m1 '^pkgver=' "$overlay_pkg" | cut -d= -f2- | tr -d "'\"")
  overlay_rel=$(grep -m1 '^pkgrel=' "$overlay_pkg" | cut -d= -f2- | tr -d "'\"")
  if [[ ! $shell_rel =~ ^[0-9]+$ || ! $overlay_ver =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! $overlay_rel =~ ^[0-9]+$ ]]; then
    printf 'error: invalid PKGBUILD version metadata\n' >&2
    return 1
  fi
  shell_ver=$(grep -m1 '^pkgver=' "$shell_pkg" | cut -d= -f2- | tr -d "'\"")
  if [[ $shell_ver != "$OMARCHY_VERSION" ]]; then
    printf 'error: shell PKGBUILD pkgver %s does not match upstream.lock OMARCHY_VERSION %s\n' "$shell_ver" "$OMARCHY_VERSION" >&2
    return 1
  fi
  COO_SHELL_ARTIFACT=cachy-omarchy-shell-$OMARCHY_VERSION-$shell_rel-any.pkg.tar.zst
  COO_OVERLAY_ARTIFACT=cachy-omarchy-overlay-$overlay_ver-$overlay_rel-any.pkg.tar.zst
}
