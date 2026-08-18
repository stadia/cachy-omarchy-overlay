#!/usr/bin/env bash
# 실제 uwsm-app 이 앱을 app-graphical.slice scope 에 격리하는지 확인한다.
# 라이브 세션을 건드리므로 COO_RUN_LIVE=1 에서만 실행한다 (SPEC §45).
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

[[ ${HOME:-} == "${COO_TEST_SANDBOX:?}" ]] \
  || { echo "FAIL: HOME 이 샌드박스가 아니다 — 중단"; exit 1; }
[[ ${COO_RUN_LIVE:-} == 1 ]] || { echo "skip: COO_RUN_LIVE=1 이 아니다"; exit 0; }
coo_live_runtime_usable || { echo "skip: 라이브 런타임 사용 불가"; exit 0; }
command -v uwsm-app >/dev/null 2>&1 || { echo "skip: uwsm-app 없음"; exit 0; }

SHELL_BIN=${COO_SHELL_BIN:-cachy-omarchy-shell}
command -v "$SHELL_BIN" >/dev/null 2>&1 \
  || { echo "skip: cachy-omarchy-shell 없음"; exit 0; }

marker="$COO_TEST_SANDBOX/app-scope.pid"
probe="$COO_TEST_SANDBOX/app-scope-probe"
cat >"$probe" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$$" >"${COO_APP_SCOPE_MARKER:?}"
exec sleep 60
EOF
chmod +x "$probe"
pid=""
cleanup() {
  [[ -n $pid ]] && kill "$pid" 2>/dev/null || true
  rm -f "$marker" "$probe"
}
trap cleanup EXIT

COO_APP_SCOPE_MARKER="$marker" setsid uwsm-app -- "$probe" >/dev/null 2>&1 &
for _ in {1..20}; do
  [[ -s $marker ]] && break
  sleep 0.1
done
pid=$(cat "$marker" 2>/dev/null || true)
[[ $pid =~ ^[0-9]+$ ]] && found=0 || found=1
assert_eq "$found" "0" "uwsm-app 이 앱을 띄웠다"

if (( found == 0 )); then
  cgroup=$(cat "/proc/$pid/cgroup" 2>/dev/null || true)
  assert_contains "$cgroup" "app-graphical.slice" \
    "앱이 app-graphical.slice 아래 scope 에 있다"
  assert_contains "$cgroup" ".scope" "앱이 자기 systemd scope 를 가진다"

  shell_pid=$(pgrep -f 'quickshell -n -p ' | head -1)
  if [[ -n $shell_pid ]]; then
    shell_cgroup=$(cat "/proc/$shell_pid/cgroup" 2>/dev/null || true)
    [[ $cgroup != "$shell_cgroup" ]] && detached=0 || detached=1
    assert_eq "$detached" "0" "앱 cgroup 이 셸 cgroup 과 다르다"
  else
    echo "note: 셸 미기동 — cgroup 분리 비교 생략"
  fi

  "$SHELL_BIN" --restart >/dev/null 2>&1
  sleep 1
  kill -0 "$pid" 2>/dev/null && survived=0 || survived=1
  assert_eq "$survived" "0" "셸 재시작 뒤에도 uwsm-app 앱이 생존한다"
fi

exit "$ASSERT_FAILURES"
