#!/usr/bin/env bash
# 오버레이 패키지의 금지 경로·금지 의존 감사 (SPEC 21, 27, 44).
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/lib/runtime.sh"

artifact=$(coo_overlay_artifact) || { echo "skip: 오버레이 아티팩트 없음"; exit 0; }
listing=$(bsdtar -tf "$artifact")

# 시스템 정체성·부트·로그인 관련은 하나도 소유하지 않는다.
# (env-hyprland.d 드롭인은 Task 3 에서 허용됨 — Hyprland 전용 세션 환경)
for bad in "etc/" "boot/" "efi/" "usr/lib/systemd/system/"; do
  n=$(printf '%s\n' "$listing" | grep -c "^$bad" || true)
  assert_eq "$n" "0" "금지 경로 미소유: $bad"
done
# uwsm 드롭인은 env-hyprland.d/ 아래 Hyprland 세션 환경만 허용한다.
# 파일만 검증 (디렉터리는 install -D 가 생성하는 부산물).
n=$(printf '%s\n' "$listing" | grep "^usr/share/uwsm/" | grep -v "/$" | grep -v "^usr/share/uwsm/env-hyprland.d/" | wc -l)
assert_eq "$n" "0" "금지 경로 미소유: usr/share/uwsm/(env-hyprland.d 제외)"

# compat 적응 카피는 /usr/bin 에 심링크로만 노출된다 (SPEC §45 개정 — 이전
# SPEC 44 는 어떤 노출도 금지했으나, Task 2 가 상대 심링크 노출을 의도적으로
# 도입했다). 노출 개수가 compat/bin 의 omarchy-* 실체 개수와 정확히 같아야
# 하고, uwsm-app 처럼 우리가 소유하지 않는 이름은 여전히 금지된다.
compat_count=$(cd "$REPO_ROOT/overlay/compat/bin" && ls omarchy-* 2>/dev/null | wc -l)
n=$(printf '%s\n' "$listing" | grep -c "^usr/bin/omarchy-" || true)
assert_eq "$n" "$compat_count" "/usr/bin 의 omarchy-* 노출 개수 = compat 실체 개수"
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
