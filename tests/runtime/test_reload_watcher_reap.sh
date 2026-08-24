#!/usr/bin/env bash
# 셸 종료 시 플러그인 감시자(inotifywait) 회수. SPEC 19.3, 46.3, 66.
#
# Quickshell 0.3.0 의 Io.Process 는 소유자가 사라져도 자식을 죽이지 않는다.
# 업스트림 PluginRegistry 의 localPluginWatcher 는 `inotifywait -m -r` 이므로,
# 패치가 없으면 셸을 한 번 띄울 때마다 감시자 하나가 systemd --user 로
# 재부모화되어 select() 에 영원히 걸린 채 남는다. 디렉터리를 지워도 풀리지
# 않는다 (tests/test.sh 의 "죽이고 나서 지운다" 주석과 같은 사정).
#
# 이 테스트는 그 회수를 런타임에서 증명한다 — 러너의 리퍼가 치워 주는 것을
# 보는 게 아니라, 셸 자신이 종료하면서 자기 감시자를 데려가는지를 본다.
# 그래서 회수 판정(await_gone)은 리퍼보다 반드시 먼저 돈다. 리퍼는 마지막
# 안전망일 뿐이며 통과 근거가 아니다.
#
# 패키지를 설치하지 않는다 — 빌드된 아티팩트를 추출해 그 트리를 띄운다.
# 사용자의 라이브 Hyprland 세션 위에서 도는 테스트이므로, 죽이는 대상은 언제나
# 우리가 만든 PID 뿐이다. pkill/killall 은 사용자의 컴포지터까지 잡는다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/tests/lib/sandbox.sh"
source "$REPO_ROOT/lib/runtime.sh"

# 건너뛰기는 프로젝트가 이미 쓰는 게이트 두 개로만 한다. 셸을 띄운 뒤로는
# 어떤 경로로도 조용히 통과하지 않는다 — 아래 단언 두 개는 항상 실행된다.
coo_live_runtime_usable || { echo "skip: 라이브 Wayland 런타임 없음 (quickshell/qs/systemd-cat 사용 불가 또는 WAYLAND_DISPLAY 소켓 없음)"; exit 0; }
coo_pkg_artifact >/dev/null || { echo "skip: build/*.pkg.tar.zst 없음"; exit 0; }

dest="$COO_TEST_SANDBOX/pkg"
coo_extract_pkg "$dest" || { echo "skip: 추출 실패"; exit 0; }
root=$(coo_upstream_root "$dest")

# 아래 쓰기는 전적으로 $HOME 에 의존한다. tests/test.sh 가 HOME 을 샌드박스로
# 덮어써 주기 때문에 안전할 뿐이고, 그건 이 파일 밖의 사정이다. 이 파일을 직접
# 실행하면 사용자의 진짜 ~/.config/omarchy 에 쓰게 된다. 구조로 막는다.
[[ ${HOME:-} == "${COO_TEST_SANDBOX:?}" ]] || {
  printf 'FAIL: HOME 이 샌드박스가 아니다 — 사용자 상태를 건드릴 수 있어 중단한다\n' >&2
  printf '      HOME=%q COO_TEST_SANDBOX=%q\n' "${HOME:-}" "$COO_TEST_SANDBOX" >&2
  exit 1
}

# inotify-tools 는 셸 패키지의 하드 의존이다(PKGBUILD depends). 없으면 감시자가
# 아예 안 뜨므로 건너뛰지 않고 크게 실패시킨다 — 조용한 통과보다 낫다.
assert_exit 0 "inotifywait 사용 가능 (셸 패키지 하드 의존)" command -v inotifywait

# 감시자가 붙을 디렉터리. 없으면 inotifywait 이 즉시 죽고 업스트림 Timer 가
# 1초마다 되살리므로, 관측 대상이 매번 다른 PID 가 되어 판정이 무의미해진다.
plugins_dir="$HOME/.config/omarchy/plugins"
mkdir -p "$plugins_dir"

# test_shell_smoke.sh 와 같은 이유의 화면 점유 가드. 업스트림 자신의 숨김
# 경로이며 HOME 이 샌드박스이므로 사용자 상태는 건드리지 않는다.
mkdir -p "$HOME/.local/state/omarchy/toggles"
: > "$HOME/.local/state/omarchy/toggles/bar-off"

W="$REPO_ROOT/overlay/bin/cachy-omarchy-shell"
export COO_OMARCHY_PATH="$root"
stdout_log="$COO_TEST_SANDBOX/shell.stdout"

"$W" --run > "$stdout_log" 2>&1 &
shell_pid=$!
our_shell_pid=$shell_pid

# 정리는 중단 경로에서도 반드시 돈다. EXIT 만 걸면 Ctrl-C 가 사용자의 진짜
# 데스크톱에 quickshell 을 그대로 두고 간다. wait 는 자식이 TERM 을 무시하면
# 영원히 막히므로 2초 감시자로 상한을 준다 (SPEC 19.3). test_shell_smoke.sh 의
# 동일 메커니즘이며, 죽이는 대상은 언제나 우리 PID 하나뿐이다.
cleanup() {
  [[ -n ${shell_pid:-} ]] || return 0
  local pid=$shell_pid
  shell_pid=""
  kill -TERM "$pid" 2>/dev/null
  { sleep 2; kill -KILL "$pid" 2>/dev/null; } &
  local watchdog=$!
  wait "$pid" 2>/dev/null
  local sleeper
  sleeper=$(ps -o pid= --ppid "$watchdog" 2>/dev/null | tr -d ' ')
  kill "$watchdog" 2>/dev/null
  [[ -n $sleeper ]] && kill "$sleeper" 2>/dev/null
  wait "$watchdog" 2>/dev/null
  return 0
}
# 안전망. 단언이 이미 끝난 뒤에만 돈다 — 회수 판정을 대신하지 않는다.
# 경로 스코프는 샌드박스 안의 플러그인 디렉터리 하나로 한정한다.
final_safety_net() {
  cleanup
  coo_reap_sandbox_procs "$plugins_dir" >/dev/null 2>&1
  return 0
}
trap final_safety_net EXIT
trap 'final_safety_net; exit 130' INT
trap 'final_safety_net; exit 143' TERM

# IPC 가 응답할 때까지 상한을 두고 기다린다. 셸이 중간에 죽으면 즉시 끊는다.
reply=""
for _ in $(seq 1 40); do
  reply=$("$W" --ipc shell ping 2>/dev/null) && [[ -n $reply ]] && break
  kill -0 "$shell_pid" 2>/dev/null || break
  sleep 0.25
done
assert_eq "$reply" "ok" "셸이 IPC 로 응답한다 (감시자 관측의 전제)"

# ------------------------------------------------- 감시자 식별
#
# 이름이 아니라 경로로 찾는다. `pgrep inotifywait` 는 사용자의 라이브 셸이
# 띄운 감시자까지 잡고, `pkill` 은 그것을 죽인다. 유일 식별자는 이 샌드박스의
# 플러그인 디렉터리 경로이며, 그 문자열은 감시자 cmdline 의 마지막 인자로만
# 나타난다 (quickshell 자신의 cmdline 은 $COO_TEST_SANDBOX/pkg/... 를 가리켜
# 이 경로와 겹치지 않는다).
watcher_pids=""
for _ in $(seq 1 40); do
  watcher_pids=$(coo_sandbox_pids "$plugins_dir")
  [[ -n $watcher_pids ]] && break
  kill -0 "$shell_pid" 2>/dev/null || break
  sleep 0.25
done

watcher_count=$(printf '%s' "$watcher_pids" | grep -c '[0-9]')
[[ $watcher_count =~ ^[0-9]+$ ]] || watcher_count=0
old_watcher_pid=$(printf '%s\n' "$watcher_pids" | head -n 1)
old_watcher_found=$(( watcher_count == 1 ? 0 : 1 ))

assert_eq "$old_watcher_found" "0" "shell started one sandbox plugin watcher"
(( old_watcher_found == 0 )) || \
  printf '      FINDING: %s 를 감시하는 프로세스 %d개 (PID: %s)\n' \
    "$plugins_dir" "$watcher_count" "${watcher_pids//$'\n'/ }"

# ------------------------------------------------- 회수 판정
#
# 상한 있는 폴링. 20 x 100ms = 2s (SPEC 19.3: 무한 대기 금지).
await_gone() {
  local pid=$1 i
  for ((i = 0; i < 20; i++)); do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.1
  done
  return 1
}

# 셸을 끝낸다. 이 지점 이후 감시자가 살아 있으면 그것이 곧 누수다.
cleanup

old_watcher_gone=1
if [[ -n $old_watcher_pid ]]; then
  await_gone "$old_watcher_pid" && old_watcher_gone=0
fi

assert_eq "$old_watcher_gone" "0" "shell exit reaps its sandbox plugin watcher"
(( old_watcher_gone == 0 )) || {
  printf '      FINDING: 셸(PID %s) 종료 후에도 감시자 PID %s 가 살아 있다\n' \
    "$our_shell_pid" "$old_watcher_pid"
  printf '      FINDING: cmdline = %s\n' \
    "$(tr '\0' ' ' < "/proc/$old_watcher_pid/cmdline" 2>/dev/null)"
}

if (( ASSERT_FAILURES )); then
  printf '      --- shell.stdout (systemd-cat 이 저널로 보내므로 보통 비어 있다) ---\n'
  tail -10 "$stdout_log" | sed 's/^/      /'
fi

exit "$ASSERT_FAILURES"
