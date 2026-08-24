#!/usr/bin/env bash
# Task 3: polkit ←→ lock 취소 경계의 구조 계약을 검증한다.
#
# 라이브 pkexec 를 돌리지 않는다 — 핀 커밋 원본에 유지보수 패치 두 장을
# 적용한 뒤 QML 소스가 계약대로 메서드와 호출을 노출하는지 잰다.
# test_package_files.sh 의 git archive pristine source 패턴을 그대로 쓴다.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/assert.sh"

src=${COO_OMARCHY_GIT:-$REPO_ROOT/build/omarchy}
if [[ ! -d $src && -d $REPO_ROOT/packages/cachy-omarchy-shell/src/omarchy ]]; then
  src=$REPO_ROOT/packages/cachy-omarchy-shell/src/omarchy
fi
patched_src="$COO_TEST_SANDBOX/upstream"

assert_file_exists "$src/shell/shell.qml" "clone has shell.qml for polkit test"

mkdir -p "$patched_src"
pinned_commit=$(grep -m1 "^_commit=" "$REPO_ROOT/packages/cachy-omarchy-shell/PKGBUILD" | cut -d= -f2- | tr -d "'\"")
[[ -n $pinned_commit ]] || { printf 'error: PKGBUILD 에서 _commit 을 읽지 못했다\n' >&2; exit 1; }
if [[ -d $src/.git ]]; then
  git -C "$src" archive --format=tar "$pinned_commit" \
    | tar -C "$patched_src" -xf - \
    || { printf 'error: 핀 커밋 %s 를 %s 에서 내보내지 못했다\n' "$pinned_commit" "$src" >&2; exit 1; }
else
  cp -a "$src/." "$patched_src/"
  if grep -q "cancelForSessionLock" "$patched_src/shell/plugins/polkit/PolkitAgent.qml"; then
    printf 'error: 패치 없는 원본이 필요한데 %s 가 이미 패치돼 있다\n' "$src" >&2
    exit 1
  fi
fi
assert_file_exists "$patched_src/shell/plugins/polkit/PolkitAgent.qml" "pristine pinned source exported for polkit test"

# test_package_files.sh 와 동일한 패치 적용 루프 — 실패는 치명.
while IFS= read -r -d '' patch; do
  ( cd "$patched_src" && git apply -p1 "$patch" ) \
    || { printf 'error: 패치 적용 실패: %s\n' "${patch##*/}" >&2; exit 1; }
done < <(find "$REPO_ROOT/packages/cachy-omarchy-shell/patches" -name '*.patch' -type f -print0 | sort -z)

polkit_qml=$(cat "$patched_src/shell/plugins/polkit/PolkitAgent.qml")
lock_qml=$(cat "$patched_src/shell/plugins/lock/Service.qml")

# polkit 취소 API — 잠금이 활성 인증 흐름을 명시적으로 끊는다.
assert_contains "$polkit_qml" "function cancelForSessionLock()" "polkit exposes lock cancellation"
assert_contains "$polkit_qml" "flow.cancelAuthenticationRequest()" "polkit cancels an active flow"
assert_contains "$polkit_qml" "flow.isCompleted || flow.isCancelled" "polkit cancellation is idempotent"

# lock 서비스 — polkit 취소를 소유하고 잠금 요청을 명시적으로 유지한다.
assert_contains "$lock_qml" 'shell.firstPartyServiceFor("omarchy.polkit")' "lock resolves only first-party polkit service"
assert_contains "$lock_qml" "cancelPolkitForSessionLock()" "lock owns cancellation boundary"
assert_contains "$lock_qml" "lockRequested = true" "lock request remains explicit"

# 외부 IPC target 으로 polkit 취소를 위임하지 않는다 — in-process 서비스 호출만 허용.
assert_eq "$(grep -c 'target: "polkit' "$patched_src/shell/plugins/polkit/PolkitAgent.qml")" "0" \
  "no external polkit cancellation IPC target"

[[ $ASSERT_FAILURES -eq 0 ]]