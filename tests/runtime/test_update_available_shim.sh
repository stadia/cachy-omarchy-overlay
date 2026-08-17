#!/usr/bin/env bash
# update-available shim 의 종료코드 계약을 검증한다.
# SystemUpdate.qml:41 은 exitCode === 0 을 "업데이트 있음"으로 읽는다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

SHIM="$REPO_ROOT/overlay/compat/bin/omarchy-update-available"
assert_file_exists "$SHIM" "shim 존재"
[[ -f $SHIM ]] || exit 1
[[ -x $SHIM ]] && x=0 || x=1
assert_eq "$x" "0" "실행 가능"

# 우리 패키지명을 조회한다 — 업스트림의 omarchy/omarchy-dev 가 아니다.
src=$(<"$SHIM")
assert_contains "$src" "cachy-omarchy-shell" "우리 셸 패키지를 본다"
assert_contains "$src" "cachy-omarchy-overlay" "우리 오버레이 패키지를 본다"
case "$src" in
  *"pacman -Qq omarchy"*) y=1 ;;
  *) y=0 ;;
esac
assert_eq "$y" "0" "업스트림 omarchy 패키지명을 쓰지 않는다"

stub=$COO_TEST_SANDBOX/stub
mkdir -p "$stub"

# 무관한 업데이트만 있음 → exit 1
cat > "$stub/checkupdates" <<'STUB'
#!/usr/bin/env bash
echo "linux 6.1.0-1 -> 6.2.0-1"
STUB
chmod +x "$stub/checkupdates"
out=$(PATH="$stub:$PATH" "$SHIM"); rc=$?
assert_eq "$rc" "1" "관련 업데이트 없으면 exit 1"
assert_contains "$out" "up to date" "최신 메시지"

# 업데이트 있음 → exit 0 + 해당 줄 출력
cat > "$stub/checkupdates" <<'STUB'
#!/usr/bin/env bash
echo "linux 6.1.0-1 -> 6.2.0-1"
echo "cachy-omarchy-overlay 0.1.2-1 -> 0.2.0-1"
STUB
chmod +x "$stub/checkupdates"
out=$(PATH="$stub:$PATH" "$SHIM"); rc=$?
assert_eq "$rc" "0" "우리 패키지 업데이트가 있으면 exit 0"
assert_contains "$out" "cachy-omarchy-overlay" "해당 줄을 출력"
case "$out" in *linux*) z=1 ;; *) z=0 ;; esac
assert_eq "$z" "0" "무관한 패키지는 출력하지 않는다"

# 접두사만 겹치는 이름에 걸리면 안 된다 — 필드 전체가 일치해야 한다.
cat > "$stub/checkupdates" <<'STUB'
#!/usr/bin/env bash
echo "cachy-omarchy-overlay-git 0.1.2-1 -> 0.2.0-1"
STUB
chmod +x "$stub/checkupdates"
PATH="$stub:$PATH" "$SHIM" >/dev/null 2>&1; rc=$?
assert_eq "$rc" "1" "접두사만 겹치는 패키지는 우리 것이 아니다"

# checkupdates 자체가 없어도 죽지 않는다 (pacman-contrib 미설치 환경).
# bash 는 남겨 둔다 — 셔뱅의 env 가 그것마저 못 찾으면 127 이 나서 "shim 이
# 조용히 실패했다" 가 아니라 "테스트가 셔뱅을 못 띄웠다" 를 재는 셈이 된다.
empty=$COO_TEST_SANDBOX/empty; mkdir -p "$empty"
ln -sf "$(command -v bash)" "$empty/bash"
PATH="$empty" "$SHIM" >/dev/null 2>&1; rc=$?
assert_eq "$rc" "1" "checkupdates 없으면 조용히 exit 1"

# checkupdates 가 있어도 실패하면(서버 오류 등) 위젯을 거짓 양성으로 켜지 않는다.
cat > "$stub/checkupdates" <<'STUB'
#!/usr/bin/env bash
echo "error: failed to sync" >&2
exit 1
STUB
chmod +x "$stub/checkupdates"
PATH="$stub:$PATH" "$SHIM" >/dev/null 2>&1; rc=$?
assert_eq "$rc" "1" "checkupdates 실패는 '업데이트 있음'이 아니다"

exit "$ASSERT_FAILURES"
