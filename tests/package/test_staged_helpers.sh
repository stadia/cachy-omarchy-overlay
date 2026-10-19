#!/usr/bin/env bash
# What stage-upstream.sh puts in (and keeps out of) the shell package, checked
# against the pinned upstream source. The expectations live in
# tests/data/staged-helpers.tsv; the few checks that are not a row in that
# table follow the loop.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

src=${COO_OMARCHY_GIT:-$REPO_ROOT/build/omarchy}
[[ -d $src ]] || { echo "skip: 업스트림 클론 없음"; exit 0; }

stage=$COO_TEST_SANDBOX/pkg
bash "$REPO_ROOT/packages/cachy-omarchy-shell/stage-upstream.sh" "$src" "$stage" \
  "$REPO_ROOT/overlay/defaults"
root="$stage/usr/share/cachy-omarchy/upstream"
bin="$root/bin"

identical() { cmp -s "$1" "$2" && echo 0 || echo 1; }

while IFS=$'\t' read -r kind path _; do
  [[ -z $kind || $kind == \#* ]] && continue
  case $kind in
    exists|exec|verbatim|linked|absent)
      f=$bin/$path ;;
    data|absent-data)
      f=$root/$path ;;
    *) printf 'FAIL: unknown kind in staged-helpers.tsv: %s\n' "$kind"; ASSERT_FAILURES=$((ASSERT_FAILURES + 1)); continue ;;
  esac
  case $kind in
    absent|absent-data)
      [[ -e $f ]] && x=1 || x=0
      assert_eq "$x" "0" "not staged: $path"
      continue ;;
  esac
  assert_file_exists "$f" "staged: $path"
  case $kind in
    exec|verbatim|linked)
      [[ -x $f ]] && x=0 || x=1
      assert_eq "$x" "0" "executable: $path" ;;
  esac
  case $kind in
    verbatim|linked) assert_eq "$(identical "$src/bin/$path" "$f")" "0" "verbatim: $path" ;;
    data)            assert_eq "$(identical "$src/$path" "$f")" "0" "verbatim: $path" ;;
  esac
  if [[ $kind == linked ]]; then
    link=$stage/usr/bin/$path
    assert_file_exists "$link" "/usr/bin exposure: $path"
    [[ $(readlink -f "$link") == "$(readlink -f "$f")" ]] && x=0 || x=1
    assert_eq "$x" "0" "symlink points at the staged file: $path"
  fi
done <"$REPO_ROOT/tests/data/staged-helpers.tsv"

# Themes and their templates evolve as a pair: both come from the same pin and
# are copied untouched.
assert_file_exists "$root/themes/tokyo-night/colors.toml" "tokyo-night colors.toml"
assert_file_exists "$root/default/themed/shell.toml.tpl" "shell.toml.tpl"
for d in themes default/themed; do
  diff -r "$src/$d" "$root/$d" >/dev/null && x=0 || x=1
  assert_eq "$x" "0" "$d is identical to the pin"
done

# The wrapper scripts rely on these seams and declarations.
assert_contains "$(<"$REPO_ROOT/overlay/hypr/bindings.lua")" "toggles/hypr" \
  "the bindings seam reads the toggles clamshell writes"
assert_contains "$(<"$bin/omarchy-show-logo")" '$OMARCHY_PATH/logo.txt' \
  "omarchy-show-logo reads the staged logo.txt"
pkgbuild=$(<"$REPO_ROOT/packages/cachy-omarchy-shell/PKGBUILD")
deps=$(sed -n '/^depends=(/,/)/p' "$REPO_ROOT/packages/cachy-omarchy-shell/PKGBUILD")
assert_contains "$deps" "socat" "socat is in depends"
assert_contains "$pkgbuild" "imagemagick:" "imagemagick is an optdepend"
assert_contains "$pkgbuild" "ttfx:" "ttfx is an optdepend"
grep -qP "^\s*'?ttfx'?\s*$" <<<"$pkgbuild" && x=1 || x=0
assert_eq "$x" "0" "ttfx is not in depends (AUR only; pacman -U cannot resolve it)"

# The five first-party plugins stay default-enabled and kept loaded.
shell_json="$REPO_ROOT/overlay/defaults/shell.json"
grep -q '"disabledPlugins"' "$shell_json" && x=1 || x=0
assert_eq "$x" "0" "shell.json has no disabledPlugins"
assert_eq "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["plugins"])' "$shell_json")" "[]" \
  "shell.json plugins is []"
for p in clipboard emojis image-picker reminders osd; do
  m=$root/shell/plugins/$p/manifest.json
  assert_file_exists "$m" "manifest exists: omarchy.$p"
  if [[ -f $m ]]; then
    assert_eq "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("keepLoaded"))' "$m")" "True" \
      "keepLoaded: omarchy.$p"
  fi
done

exit "$ASSERT_FAILURES"
