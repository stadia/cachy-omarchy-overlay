#!/usr/bin/env bash
# uwsm 이 설치되면 실제 uwsm-app 이 PATH 에 나타난다. 그때도 이 compat
# 디렉터리가 셸 프로세스 PATH 맨 앞에 붙어 있으므로(SPEC 45), shim 이 계속
# 먼저 잡힌다. shim 은 두 갈래를 정확히 구분해야 한다:
#   A) 실제 uwsm-app 이 PATH 어딘가에 있으면 -> 원래 인자(`--` 포함) 그대로
#      위임한다 (스코프 격리를 실제 도구에게 넘긴다).
#   B) 없으면 -> 오늘까지의 동작: `--` 를 벗기고 나머지를 exec.
# 각 단언은 "잘못된 구현"(옛 shim 이거나, 무조건 위임하는 구현)을 실제로
# 떨어뜨리도록 짰다 — 단순히 "뭔가 실행됐다"만 보는 테스트는 아무것도
# 증명하지 못한다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

SHIM="$REPO_ROOT/overlay/compat/bin/uwsm-app"
assert_file_exists "$SHIM" "uwsm-app shim 존재"
[[ -x $SHIM ]] && x=0 || x=1
assert_eq "$x" "0" "uwsm-app shim 실행 가능"
[[ -x $SHIM ]] || exit 1

WORK="$COO_TEST_SANDBOX/uwsm-shim-test"
mkdir -p "$WORK"

# 셸 스크립트를 exec 하려면 shim/target 이 의존하는 interpreter 를 찾을 수
# 있는 넓은 PATH 가 필요하다. 실제 검증 대상인 "uwsm-app 후보 유무"만
# 별도로 앞에 붙이거나 뺀다.
BASE_PATH=$PATH

target_marker="$WORK/target.marker"
target="$WORK/target.sh"
cat >"$target" <<EOF
#!/usr/bin/env bash
printf 'target-ran\n' > '$target_marker'
EOF
chmod +x "$target"

# ---------------------------------------------------------------------------
# A) 실제 uwsm-app 이 PATH 어딘가에(shim 보다 뒤라도) 있으면 위임한다.
# ---------------------------------------------------------------------------
real_dir="$WORK/real-bin"
mkdir -p "$real_dir"
real_marker="$WORK/real.marker"
cat >"$real_dir/uwsm-app" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > '$real_marker'
EOF
chmod +x "$real_dir/uwsm-app"

rm -f "$real_marker" "$target_marker"
out=$(PATH="$real_dir:$BASE_PATH" timeout 5 "$SHIM" -- "$target" 2>&1)
code=$?
assert_eq "$code" "0" "위임: shim exit 0"
assert_file_exists "$real_marker" "위임: 가짜 real uwsm-app 이 실행됐다"
assert_eq "$(cat "$real_marker" 2>/dev/null)" "-- $target" \
  "위임: -- 가 원형 그대로 real uwsm-app 에 전달됐다"
[[ -f $target_marker ]] && leaked=1 || leaked=0
assert_eq "$leaked" "0" \
  "위임: shim 이 target 을 직접 exec 하면 안 된다 (오늘 코드는 여기서 떨어진다)"

# 위 네 단언은 고쳐지기 전 shim(항상 -- 벗기고 exec)에 대해 돌리면 실패한다:
# real_marker 는 절대 안 만들어지고 target_marker 만 만들어진다. 즉 이
# 테스트는 위임 자체를 증명하지, "shim 이 뭔가는 실행했다"만 증명하지 않는다.

# ---------------------------------------------------------------------------
# B) 실제 uwsm-app 이 전혀 없으면 -> 오늘까지의 fallback (`--` 벗기고 exec).
#    같은 자리에 shim 이 스스로 다시 걸려도(자기 자신을 발견해도) 재귀하지
#    않고 fallback 으로 빠지는지도 이 경로가 증명한다.
# ---------------------------------------------------------------------------
narrow_dir="$WORK/narrow-bin"
mkdir -p "$narrow_dir"
for b in bash env timeout cat printf readlink; do
  p=$(command -v "$b" 2>/dev/null) || continue
  ln -sf "$p" "$narrow_dir/$b"
done

fallback_marker="$WORK/fallback.marker"
rm -f "$fallback_marker" "$target_marker"
out=$(PATH="$narrow_dir" timeout 5 "$SHIM" -- "$target" 2>&1)
code=$?
assert_eq "$code" "0" "fallback: real uwsm-app 없을 때 shim exit 0 (무한 재귀 없음)"
assert_file_exists "$target_marker" "fallback: -- 벗기고 target 을 직접 exec 했다"

# 위 두 단언은 "항상 위임을 시도하고 실패하면 그냥 죽는" 잘못된 구현에
# 대해 돌리면 실패한다 (real uwsm-app 이 없으므로 exec 대상이 없어 nonzero
# 로 죽거나, 자기 자신을 "실제 구현"으로 오인해 무한 재귀한다 — 5초
# timeout 이 그 경우를 exit 124 로 잡아낸다).

exit "$ASSERT_FAILURES"
