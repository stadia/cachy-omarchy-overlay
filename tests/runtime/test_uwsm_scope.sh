#!/usr/bin/env bash
# Tier 2 (실제 uwsm-app 위임) 이 진짜로 systemd scope 를 만드는지 실측한다.
#
# shim 이 "위임했다"는 것과 "스코프가 생겼다"는 것은 다르다. test_uwsm_app_shim.sh
# 는 가짜 real uwsm-app 으로 위임 자체를 증명하지만, 스코프 격리는 실제
# uwsm-app 의 효과다. 이 테스트는 실제 uwsm-app 을 PATH 에 넣어 shim 을 통해
# 프로브를 띄우고, /proc/<pid>/cgroup 을 읽어 app-graphical.slice 아래 .scope 가
# 생겼는지 직접 확인한다 — "호출했다"가 아니라 "효과가 있었다"를 본다.
#
# PATH 를 통제한다: 실제 uwsm-app 을 PATH 에 넣어 Tier 2 를 강제한다. PATH 를
# 통제하지 않으면 uwsm 없는 머신에서 Tier 1(fallback) 이 발동해도 "대상이
# 실행됐다"만 보고 통과해 버린다 — 이 테스트는 그 false-green 을 막는다.
# 실제 uwsm-app 이 없으면 skip (Tier 1 을 조용히 검증하지 않는다).
#
# 비침습: 데몬을 기동하지 않는다. 데몬이 이미 떠 있어야 Tier 2 를 실측하고,
# 없으면 note 로 남기고 음성 대조만 실행한다. 스코프는 프로브를 죽여 정리한다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

SHIM="$REPO_ROOT/overlay/compat/bin/uwsm-app"
assert_file_exists "$SHIM" "uwsm-app shim 존재"
[[ -x $SHIM ]] || exit 1

WORK="$COO_TEST_SANDBOX/uwsm-scope-test"
mkdir -p "$WORK"

# --- 게이트 1: 실제 uwsm-app 을 PATH 에서 찾는다 ---
# shim 의 resolve_real_uwsm_app(overlay/compat/bin/uwsm-app:22-35) 과 같은 해석
# 규칙을 그대로 따른다. 중복이지만 shim 은 독립 compat 스크립트라 공유 라이브러리로
# 뽑을 수 없다. 갈라지면 아래 Tier 2 양성 대조가 "스코프가 안 생긴다"로 잡는다 —
# shim 이 실제로 위임해야만 통과하므로, 해석 규칙이 어긋나면 조용히 통과하지 않는다.
self=$(readlink -f -- "$SHIM" 2>/dev/null || printf '%s' "$SHIM")
find_real_uwsm_app() {
  local dir candidate resolved
  local IFS=:
  for dir in $PATH; do
    [[ -n $dir ]] || continue
    candidate="$dir/uwsm-app"
    [[ -x $candidate && ! -d $candidate ]] || continue
    resolved=$(readlink -f -- "$candidate" 2>/dev/null || printf '%s' "$candidate")
    [[ $resolved == "$self" ]] && continue
    printf '%s' "$candidate"
    return 0
  done
  return 1
}
real_uwsm_app=$(find_real_uwsm_app) || true
if [[ -z $real_uwsm_app ]]; then
  echo "skip: 실제 uwsm-app 이 PATH 에 없다 — Tier 2 스코프 격리를 검증할 수 없다 (uwsm 미설치 호스트)"
  exit 0
fi
real_dir=$(dirname "$real_uwsm_app")

# --- 프로브: PID 를 남기고 잠시 산다 (cgroup 을 읽을 시간) ---
probe="$WORK/probe.sh"
pidfile="$WORK/pid"
cat >"$probe" <<EOF
#!/usr/bin/env bash
echo "\$\$" > '$pidfile'
sleep 40
EOF
chmod +x "$probe"

# --- 정리: 프로브/런처가 남으면 죽인다 (스코프가 40초 뒤 스스로 사라지기 전에) ---
probe_pid=""
launcher=""
cleanup() {
  [[ -n $probe_pid ]] && kill "$probe_pid" 2>/dev/null
  [[ -n $launcher ]] && kill "$launcher" 2>/dev/null
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# --- Tier 1 (음성 대조): PATH 에서 uwsm-app 을 빼면 새 스코프가 안 생긴다 ---
# fallback 은 프로브를 테스트 러너의 cgroup 에 그대로 두므로, 프로브 cgroup 이
# 러너 cgroup 과 정확히 같아야 한다. "app-graphical.slice 가 아니다"로 단언하면
# 테스트 러너가 이미 app-graphical.slice 안에서 떠 있을 때(예: 런처로 연 터미널
# 에서 test-packages 실행) 오탐한다 — cgroup 상속을 직접 비교하는 게 맥락에
# 무관하다. PATH 를 통제하지 않는 테스트가 Tier 1 을 조용히 통과시키는
# false-green 을 이 대조가 잡는다.
runner_cgroup=$(cat "/proc/$$/cgroup" 2>/dev/null || true)
narrow="$WORK/narrow-bin"
mkdir -p "$narrow"
for b in bash env timeout cat printf readlink sleep; do
  p=$(command -v "$b" 2>/dev/null) || continue
  ln -sf "$p" "$narrow/$b"
done
rm -f "$pidfile"
PATH="$narrow" timeout 25 "$SHIM" -- "$probe" &
launcher=$!
probe_pid=""
for _ in $(seq 1 100); do
  [[ -f $pidfile ]] && { probe_pid=$(cat "$pidfile"); break; }
  kill -0 "$launcher" 2>/dev/null || break
  sleep 0.25
done
if [[ -z $probe_pid ]]; then
  printf 'FAIL: Tier 1 프로브가 PID 를 쓰지 않았다\n' >&2
  exit 1
fi
cgroup=$(cat "/proc/$probe_pid/cgroup" 2>/dev/null || true)
[[ $cgroup == "$runner_cgroup" ]] && inherited=1 || inherited=0
assert_eq "$inherited" "1" "Tier 1 (음성 대조): fallback 은 새 스코프를 만들지 않고 러너 cgroup 을 그대로 상속한다"
kill "$probe_pid" 2>/dev/null
kill "$launcher" 2>/dev/null
wait "$launcher" 2>/dev/null || true
probe_pid=""
launcher=""

# --- 게이트 2: uwsm-app 데몬이 이미 떠 있어야 Tier 2 를 실측할 수 있다 ---
# 데몬을 기동하지 않는다 — 기본 스위트가 실제 세션을 바꾸지 않게. 없으면 note 로
# 남기고 음성 대조까지만 실행한다 (Tier 2 는 UNVERIFIED 로 명시).
if [[ -z ${XDG_RUNTIME_DIR:-} ]]; then
  printf '%s\n' 'note: Tier 2 스코프 격리 UNVERIFIED (XDG_RUNTIME_DIR 없음 — systemd 유저 세션 부재)'
  exit "$ASSERT_FAILURES"
fi
pipe_in="$XDG_RUNTIME_DIR/uwsm-app-daemon-in"
if [[ ! -p $pipe_in ]]; then
  printf '%s\n' 'note: Tier 2 스코프 격리 UNVERIFIED (wayland-wm-app-daemon 미기동 — 데몬을 기동하지 않는다)'
  exit "$ASSERT_FAILURES"
fi

# --- Tier 2: 실제 uwsm-app 을 PATH 에 넣고 shim 을 통해 실행 ---
rm -f "$pidfile"
PATH="$real_dir:$PATH" timeout 25 "$SHIM" -- "$probe" &
launcher=$!
probe_pid=""
for _ in $(seq 1 100); do
  [[ -f $pidfile ]] && { probe_pid=$(cat "$pidfile"); break; }
  kill -0 "$launcher" 2>/dev/null || break
  sleep 0.25
done
if [[ -z $probe_pid ]]; then
  printf 'FAIL: Tier 2 프로브가 PID 를 쓰지 않았다 (위임/데몬 실패?)\n' >&2
  exit 1
fi
cgroup=$(cat "/proc/$probe_pid/cgroup" 2>/dev/null || true)
assert_contains "$cgroup" "app-graphical.slice" "Tier 2: 프로브가 app-graphical.slice 아래 있다"
assert_contains "$cgroup" ".scope" "Tier 2: 프로브가 .scope 안에 있다"
kill "$probe_pid" 2>/dev/null
kill "$launcher" 2>/dev/null
wait "$launcher" 2>/dev/null || true
probe_pid=""
launcher=""

exit "$ASSERT_FAILURES"
