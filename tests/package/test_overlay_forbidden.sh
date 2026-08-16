#!/usr/bin/env bash
# 오버레이 패키지의 금지 경로·금지 의존 감사 (SPEC 21, 27, 44).
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/lib/runtime.sh"

artifact=$(coo_overlay_artifact) || { echo "skip: 오버레이 아티팩트 없음"; exit 0; }
listing=$(bsdtar -tf "$artifact")

# 시스템 정체성·부트·로그인 관련은 하나도 소유하지 않는다.
for bad in "etc/" "boot/" "efi/" "usr/lib/systemd/system/" "usr/share/uwsm/"; do
  n=$(printf '%s\n' "$listing" | grep -c "^$bad" || true)
  assert_eq "$n" "0" "금지 경로 미소유: $bad"
done

# compat shim 은 /usr/bin 에 두지 않는다 (SPEC 44).
n=$(printf '%s\n' "$listing" | grep -c "^usr/bin/omarchy-" || true)
assert_eq "$n" "0" "/usr/bin 에 omarchy-* 가짜 명령 없음"
n=$(printf '%s\n' "$listing" | grep -c "^usr/bin/uwsm" || true)
assert_eq "$n" "0" "/usr/bin 에 uwsm shim 없음"

# 사용자 홈을 패키지가 소유하지 않는다 (SPEC 6.6).
n=$(printf '%s\n' "$listing" | grep -cE "^home/|^root/" || true)
assert_eq "$n" "0" "사용자 홈 미소유"

# 공식 omarchy 패키지에 의존하지 않는다 (SPEC 21).
P="$REPO_ROOT/packages/cachy-omarchy-overlay/PKGBUILD"
deps=$(grep -E "^depends=" "$P")
for bad in omarchy-settings limine snapper sddm plymouth; do
  printf '%s' "$deps" | grep -q "$bad" && has=1 || has=0
  assert_eq "$has" "0" "depends 에 $bad 없음"
done
# 'omarchy' 단독 의존도 금지. cachy-omarchy-shell 은 허용.
printf '%s' "$deps" | grep -qE "(^|[ '\"])omarchy([ '\"]|$)" && has=1 || has=0
assert_eq "$has" "0" "depends 에 공식 omarchy 없음"
assert_contains "$deps" "cachy-omarchy-shell" "depends 에 cachy-omarchy-shell 있음"

exit "$ASSERT_FAILURES"
