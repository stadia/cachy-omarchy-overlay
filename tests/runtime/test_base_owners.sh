#!/usr/bin/env bash
# closure_check.base_command_owners() 와 bin/list-upstream-helpers 를 가짜
# pactree/pacman 과 임시 저장소로 고정한다. 둘 다 호스트에 무엇이 깔려 있는지
# 에 기대지 않는다 — 진짜 도출은 test_dependency_closure.sh 가 돈다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

fake=$COO_TEST_SANDBOX/fake-pac
mkdir -p "$fake"
cat >"$fake/pactree" <<'EOF'
#!/usr/bin/env bash
[[ ${FAKE_PACTREE_FAIL:-0} == 1 ]] && { echo 'pactree: boom' >&2; exit 1; }
# base closure only; the seed must be `base`, never base-devel
[[ $* == "-l -s base" ]] || { echo "unexpected pactree args: $*" >&2; exit 2; }
printf '%s\n' base coreutils 'bash>=5'
EOF
cat >"$fake/pacman" <<'EOF'
#!/usr/bin/env bash
[[ ${FAKE_PACMAN_FAIL:-0} == 1 ]] && { echo 'pacman: boom' >&2; exit 1; }
[[ $1 == -Ql ]] || exit 2
cat <<'LIST'
coreutils /usr/bin/
coreutils /usr/bin/ls
coreutils /usr/bin/cat
coreutils /usr/share/man/ls.1
bash /usr/bin/bash
bash /usr/bin/sub/nested
LIST
EOF
chmod +x "$fake"/*

owners() {
  env PATH="$fake:/usr/bin:/bin" "$@" python3 -I -c "
import sys
sys.path.insert(0, '$REPO_ROOT/tests/runtime')
import closure_check
print(sorted(closure_check.base_command_owners().items()))
" 2>&1
}

out=$(owners) && code=0 || code=$?
assert_eq "$code" "0" "base owners derive with working tools"
assert_contains "$out" "('bash', 'bash')" "a base binary maps to its package"
assert_contains "$out" "('ls', 'coreutils')" "coreutils binaries map to coreutils"
case $out in *nested*|*man*) bad=1 ;; *) bad=0 ;; esac
assert_eq "$bad" "0" "only /usr/bin entries count"

out=$(owners FAKE_PACTREE_FAIL=1) && code=0 || code=$?
assert_eq "$((code != 0))" "1" "a failing pactree aborts"
assert_contains "$out" "pactree" "the abort names pactree"
assert_contains "$out" "boom" "the abort carries pactree's stderr"
out=$(owners FAKE_PACMAN_FAIL=1) && code=0 || code=$?
assert_eq "$((code != 0))" "1" "a failing pacman aborts"
assert_contains "$out" "boom" "the abort carries pacman's stderr"

# --- list-upstream-helpers reads the lock's commit, not the clone's HEAD ---
root=$COO_TEST_SANDBOX/lh
mkdir -p "$root/bin" "$root/clone/bin"
cp "$REPO_ROOT/bin/list-upstream-helpers" "$root/bin/"
ident=(-c user.email=f@example.invalid -c user.name=f -c commit.gpgsign=false)
git init -q "$root/clone"
: >"$root/clone/bin/omarchy-pinned"
git -C "$root/clone" add -A
git -C "$root/clone" "${ident[@]}" commit -q -m pinned
pinned=$(git -C "$root/clone" rev-parse HEAD)
: >"$root/clone/bin/omarchy-later"
git -C "$root/clone" add -A
git -C "$root/clone" "${ident[@]}" commit -q -m later
printf 'OMARCHY_VERSION=1.2.3\nOMARCHY_COMMIT=%s\n' "$pinned" >"$root/upstream.lock"
out=$(COO_REPO_ROOT="$root" COO_OMARCHY_GIT="$root/clone" "$root/bin/list-upstream-helpers" 2>&1) && code=0 || code=$?
assert_eq "$code" "0" "list-upstream-helpers succeeds"
assert_eq "$out" "omarchy-pinned" "the list is the pinned commit's bin/, not the clone's HEAD"

exit "$ASSERT_FAILURES"
