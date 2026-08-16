#!/usr/bin/env bash
# Shared validated-build manifest parsing for M6 commands. Source only.

coo_fail() { printf 'error: %s\n' "$1" >&2; return 1; }

# Reads a manifest without sourcing it. On success sets COO_RELEASE,
# COO_VERSION, COO_COMMIT, COO_ARTIFACT_NAMES, and COO_ARTIFACT_SUMS.
coo_read_manifest() {
  local manifest=$1 line key value name sum
  local seen_release=0 seen_version=0 seen_commit=0
  local seen_shell=0 seen_overlay=0 seen_shell_sha256=0 seen_overlay_sha256=0
  COO_RELEASE="" COO_VERSION="" COO_COMMIT=""
  COO_ARTIFACT_NAMES=() COO_ARTIFACT_SUMS=()
  [[ -f $manifest ]] || { coo_fail "validated manifest missing: $manifest"; return 1; }

  while IFS= read -r line || [[ -n $line ]]; do
    case $line in
      RELEASE=*)
        [[ $seen_release -eq 0 ]] || { coo_fail 'duplicate RELEASE in manifest'; return 1; }
        seen_release=1
        COO_RELEASE=${line#RELEASE=}
        ;;
      OMARCHY_VERSION=*)
        [[ $seen_version -eq 0 ]] || { coo_fail 'duplicate OMARCHY_VERSION in manifest'; return 1; }
        seen_version=1
        COO_VERSION=${line#OMARCHY_VERSION=}
        ;;
      OMARCHY_COMMIT=*)
        [[ $seen_commit -eq 0 ]] || { coo_fail 'duplicate OMARCHY_COMMIT in manifest'; return 1; }
        seen_commit=1
        COO_COMMIT=${line#OMARCHY_COMMIT=}
        ;;
      ARTIFACT=*)
        value=${line#ARTIFACT=}
        name=${value%% *}
        sum=${value#* }
        [[ $name != "$value" && $name =~ ^[A-Za-z0-9._+-]+\.pkg\.tar\.zst$ && $sum =~ ^[0-9a-fA-F]{64}$ ]] \
          || { coo_fail 'invalid ARTIFACT in manifest'; return 1; }
        case $name in
          cachy-omarchy-shell-*)
            [[ $seen_shell -eq 0 && $seen_shell_sha256 -eq 0 ]] || { coo_fail 'duplicate shell artifact in manifest'; return 1; }
            seen_shell=1
            seen_shell_sha256=1
            ;;
          cachy-omarchy-overlay-*)
            [[ $seen_overlay -eq 0 && $seen_overlay_sha256 -eq 0 ]] || { coo_fail 'duplicate overlay artifact in manifest'; return 1; }
            seen_overlay=1
            seen_overlay_sha256=1
            ;;
          *) coo_fail 'unknown artifact type in manifest'; return 1 ;;
        esac
        COO_ARTIFACT_NAMES+=("$name")
        COO_ARTIFACT_SUMS+=("$sum")
        ;;
      "") ;;
      *) coo_fail 'unknown manifest field'; return 1 ;;
    esac
  done <"$manifest"

  [[ $seen_release -eq 1 && $seen_version -eq 1 && $seen_commit -eq 1 \
     && $seen_shell -eq 1 && $seen_overlay -eq 1 \
     && $seen_shell_sha256 -eq 1 && $seen_overlay_sha256 -eq 1 ]] \
    || { coo_fail 'manifest is missing required singleton fields'; return 1; }
  [[ $COO_RELEASE =~ ^(validated-builds|packages)/[A-Za-z0-9._+-]+$ ]] \
    || { coo_fail 'unsafe RELEASE in manifest'; return 1; }
  [[ $COO_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && $COO_COMMIT =~ ^[0-9a-fA-F]{40}$ ]] \
    || { coo_fail 'invalid upstream pin in manifest'; return 1; }
  [[ ${#COO_ARTIFACT_NAMES[@]} -eq 2 ]] || { coo_fail 'manifest must contain exactly two artifacts'; return 1; }
  [[ ${COO_ARTIFACT_NAMES[0]} == cachy-omarchy-shell-* && ${COO_ARTIFACT_NAMES[1]} == cachy-omarchy-overlay-* ]] \
    || { coo_fail 'manifest artifact order/type is invalid'; return 1; }
}

# Validates the immutable release named by manifest against its recorded sums.
# $1=state dir, $2=manifest path, $3=sha256 command.
coo_validate_manifest() {
  local state_dir=$1 manifest=$2 sha256_bin=$3 i actual release_dir
  coo_read_manifest "$manifest" || return 1
  release_dir=$state_dir/$COO_RELEASE
  [[ -d $release_dir/artifacts ]] || { coo_fail 'manifest release is incomplete'; return 1; }
  for i in "${!COO_ARTIFACT_NAMES[@]}"; do
    [[ -f $release_dir/artifacts/${COO_ARTIFACT_NAMES[$i]} ]] \
      || { coo_fail "manifest artifact missing: ${COO_ARTIFACT_NAMES[$i]}"; return 1; }
    actual=$($sha256_bin "$release_dir/artifacts/${COO_ARTIFACT_NAMES[$i]}" | awk '{print $1}') \
      || { coo_fail 'checksum command failed'; return 1; }
    [[ $actual == "${COO_ARTIFACT_SUMS[$i]}" ]] \
      || { coo_fail "checksum mismatch: ${COO_ARTIFACT_NAMES[$i]}"; return 1; }
  done
  COO_RELEASE_DIR=$release_dir
}

# Also requires the manifest pin and names to match this checkout exactly.
# $1=repo root, $2=state dir, $3=manifest, $4=sha256 command.
coo_validate_current_manifest() {
  local repo_root=$1 state_dir=$2 manifest=$3 sha256_bin=$4 lock shell_pkg overlay_pkg shell_rel overlay_ver overlay_rel
  coo_validate_manifest "$state_dir" "$manifest" "$sha256_bin" || return 1
  lock=$repo_root/upstream.lock
  shell_pkg=$repo_root/packages/cachy-omarchy-shell/PKGBUILD
  overlay_pkg=$repo_root/packages/cachy-omarchy-overlay/PKGBUILD
  [[ -f $lock && -f $shell_pkg && -f $overlay_pkg ]] || { coo_fail 'repository metadata missing'; return 1; }
  # shellcheck disable=SC1090
  source "$lock"
  shell_rel=$(grep -m1 '^pkgrel=' "$shell_pkg" | cut -d= -f2- | tr -d "'\"")
  overlay_ver=$(grep -m1 '^pkgver=' "$overlay_pkg" | cut -d= -f2- | tr -d "'\"")
  overlay_rel=$(grep -m1 '^pkgrel=' "$overlay_pkg" | cut -d= -f2- | tr -d "'\"")
  [[ $COO_VERSION == "$OMARCHY_VERSION" && $COO_COMMIT == "$OMARCHY_COMMIT" ]] \
    || { coo_fail 'manifest does not match current upstream lock'; return 1; }
  [[ ${COO_ARTIFACT_NAMES[0]} == "cachy-omarchy-shell-${OMARCHY_VERSION}-${shell_rel}-any.pkg.tar.zst" \
     && ${COO_ARTIFACT_NAMES[1]} == "cachy-omarchy-overlay-${overlay_ver}-${overlay_rel}-any.pkg.tar.zst" ]] \
    || { coo_fail 'manifest does not match current package versions'; return 1; }
}

# Creates an immutable archive of an already-validated release. The current
# manifest must have been validated immediately before calling this function.
# $1=state dir, $2=manifest source, $3=install command, $4=sha256 command.
coo_archive_validated_release() {
  local state_dir=$1 source_manifest=$2 install_bin=$3 sha256_bin=$4 mv_bin=${5:-mv} stamp stage rel manifest i sum
  stamp=$(date +%s%N) || return 1
  mkdir -p "$state_dir/packages" || return 1
  stage=$(mktemp -d "$state_dir/packages/.candidate-XXXXXX") || return 1
  rel="packages/previous-$stamp"
  mkdir -p "$stage/artifacts" || { rm -rf "$stage"; return 1; }
  for i in "${!COO_ARTIFACT_NAMES[@]}"; do
    "$install_bin" -m 644 "$COO_RELEASE_DIR/artifacts/${COO_ARTIFACT_NAMES[$i]}" "$stage/artifacts/${COO_ARTIFACT_NAMES[$i]}" \
      || { rm -rf "$stage"; return 1; }
  done
  manifest=$stage/validated-build.manifest
  {
    printf 'RELEASE=%s\n' "$rel"
    printf 'OMARCHY_VERSION=%s\n' "$COO_VERSION"
    printf 'OMARCHY_COMMIT=%s\n' "$COO_COMMIT"
    for i in "${!COO_ARTIFACT_NAMES[@]}"; do
      sum=$($sha256_bin "$stage/artifacts/${COO_ARTIFACT_NAMES[$i]}" | awk '{print $1}') || exit 1
      [[ $sum =~ ^[0-9a-fA-F]{64}$ ]] || exit 1
      printf 'ARTIFACT=%s %s\n' "${COO_ARTIFACT_NAMES[$i]}" "$sum"
    done
  } >"$manifest" || { rm -rf "$stage"; return 1; }
  "$mv_bin" "$stage" "$state_dir/$rel" || { rm -rf "$stage"; return 1; }
  printf '%s\n' "$state_dir/$rel/validated-build.manifest"
}
