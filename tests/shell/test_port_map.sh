#!/usr/bin/env bash
# Verifies docs/QUATTRO_PORT_MAP.md classifies every dependency actually
# present in the pinned upstream Menu.qml. Fails when upstream is re-pinned
# and a new dependency appears unclassified.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

MAP="$REPO_ROOT/docs/QUATTRO_PORT_MAP.md"
MENU="$REPO_ROOT/vendor/omarchy/shell/plugins/menu/Menu.qml"
COMMONS_QMLDIR="$REPO_ROOT/vendor/omarchy/shell/Commons/qmldir"
UI_QMLDIR="$REPO_ROOT/vendor/omarchy/shell/Ui/qmldir"

# The map itself is committed, so its absence is always a hard failure.
assert_file_exists "$MAP" "port map exists"
[[ -f $MAP ]] || exit 1

# vendor/omarchy/ is git-ignored by design, so a fresh clone has no upstream
# tree to cross-check against. Skip rather than fail, the same way the
# quickshell and Wayland-session tests skip when their host is absent.
if [[ ! -f $MENU ]]; then
  printf 'SKIP: %s\n' "missing $MENU"
  printf 'SKIP: %s\n' "vendor/omarchy/ is git-ignored; re-create it with the sparse-checkout commands in UPSTREAM.md, then re-run"
  exit 0
fi

map_body=$(cat "$MAP")

# 1. Every import line in Menu.qml must be classified.
while IFS= read -r imp; do
  name=${imp#import }
  name=${name%% *}
  assert_contains "$map_body" "\`$name\`" "import $name is in the map"
done < <(grep -E '^import ' "$MENU")

# 2. Every qs.Commons singleton actually referenced by Menu.qml.
while IFS= read -r s; do
  grep -qE "\b$s\." "$MENU" || continue
  assert_contains "$map_body" "\`$s\`" "singleton $s is in the map"
done < <(awk '$1=="singleton"{print $2}' "$COMMONS_QMLDIR")

# 3. Every qs.Ui component actually instantiated by Menu.qml.
while IFS= read -r c; do
  [[ -z $c ]] && continue
  grep -qE "^[[:space:]]*$c[[:space:]]*\{" "$MENU" || continue
  assert_contains "$map_body" "\`$c\`" "Ui component $c is in the map"
done < <(awk 'NF==3 && $3 ~ /\.qml$/ {print $1}' "$UI_QMLDIR")

# 4. Shell-injected properties must be classified.
for p in omarchyPath shell manifest; do
  assert_contains "$map_body" "\`$p\`" "injected property $p is in the map"
done

# 5. Every classified row uses exactly one of the four verdicts.
bad=$(grep -E '^\| `[^`]+` \|' "$MAP" | grep -vcE '\| (KEEP|PORT|REWRITE|DROP) \|$' || true)
assert_eq "$bad" "0" "every map row ends in a valid verdict"

# 6. The map must record the exact commit it was derived from.
assert_contains "$map_body" "b724f7615630d7a7aca76dce070d469f43a3bfec" "map records upstream SHA"

exit "$ASSERT_FAILURES"
