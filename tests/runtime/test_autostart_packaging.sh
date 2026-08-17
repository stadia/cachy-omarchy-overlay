#!/usr/bin/env bash
# 셸 기동은 Hyprland autostart(bindings.lua)로 패키징되고, systemd 유닛은 더 이상
# 패키지에 없다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

B="$REPO_ROOT/overlay/hypr/bindings.lua"
assert_file_exists "$B" "bindings.lua 소스 존재"
lua=$(cat "$B")
assert_contains "$lua" 'hyprland.start' "autostart 1회 트리거 패키징됨"
assert_contains "$lua" 'cachy-omarchy-shell --run' "래퍼 기동 명령 패키징됨"

# 유닛 파일은 저장소에 더 이상 존재하지 않는다. (assert.sh 에 pass/fail 헬퍼가
# 없으므로 수동 패턴: ok 출력 또는 ASSERT_FAILURES 증가.)
U="$REPO_ROOT/overlay/systemd/cachy-omarchy-shell.service"
if [[ ! -e $U ]]; then
  printf 'ok:   systemd unit removed from repo\n'
else
  printf 'FAIL: systemd unit still in repo: %s\n' "$U"
  ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
fi

source "$REPO_ROOT/lib/runtime.sh"
if coo_overlay_artifact >/dev/null 2>&1; then
  dest="$COO_TEST_SANDBOX/ov"
  coo_extract_overlay "$dest"
  # 유닛은 패키지에 없다.
  if [[ ! -e $dest/usr/lib/systemd/user/cachy-omarchy-shell.service ]]; then
    printf 'ok:   unit absent from package\n'
  else
    printf 'FAIL: unit still packaged\n'
    ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
  fi
  n=$(bsdtar -tf "$(coo_overlay_artifact)" | grep -c 'cachy-omarchy-shell.service' || true)
  assert_eq "$n" "0" "패키지 아카이브에 유닛 잔류 없음"
  # autostart bindings 은 패키지에 있다.
  assert_file_exists "$dest/usr/share/cachy-omarchy/hypr/bindings.lua" "autostart bindings 패키징됨"
  assert_contains "$(cat "$dest/usr/share/cachy-omarchy/hypr/bindings.lua")" 'hyprland.start' \
    "패키징된 bindings 에 autostart 있음"
  m=$(bsdtar -tf "$(coo_overlay_artifact)" | grep -c '^usr/lib/systemd/system/' || true)
  assert_eq "$m" "0" "system 유닛 미소유"
else
  echo "note: 오버레이 아티팩트 없음 — 패키징 검증 생략"
fi

exit "$ASSERT_FAILURES"