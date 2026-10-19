#!/usr/bin/env bash
# Latest stable upstream release tag. Source only; shared by check-upstream and
# update-upstream so both resolve a tag identically.

# coo_latest_upstream_tag <git_bin> <repository>
# Sets COO_LATEST_VERSION and COO_LATEST_COMMIT. Only stable vMAJOR.MINOR.PATCH
# tags count. Annotated tags need the peeled ^{} record to name the commit
# rather than the tag object (so no --refs); lightweight tags use the direct
# ref. Prints the reason and returns 1 on failure.
coo_latest_upstream_tag() {
  local git_bin=$1 repository=$2 refs tag_ref peeled direct
  refs=$("$git_bin" ls-remote --tags "$repository") || {
    printf 'error: unable to query upstream tags\n' >&2; return 1
  }
  COO_LATEST_VERSION=$(awk '$2 ~ /^refs\/tags\/v[0-9]+\.[0-9]+\.[0-9]+$/ { sub("refs/tags/v", "", $2); print $2 }' <<<"$refs" | sort -V | tail -n1)
  [[ -n $COO_LATEST_VERSION ]] || { printf 'error: no stable semver tags found\n' >&2; return 1; }
  tag_ref="refs/tags/v$COO_LATEST_VERSION"
  peeled=$(awk -v tag="${tag_ref}^{}" '$2 == tag { print $1; exit }' <<<"$refs")
  direct=$(awk -v tag="$tag_ref" '$2 == tag { print $1; exit }' <<<"$refs")
  COO_LATEST_COMMIT=${peeled:-$direct}
  [[ $COO_LATEST_COMMIT =~ ^[0-9a-fA-F]{40}$ ]] || {
    printf 'error: invalid commit for v%s\n' "$COO_LATEST_VERSION" >&2; return 1
  }
}
