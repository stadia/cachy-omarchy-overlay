#!/usr/bin/env bash
# M10 Task 4 — omarchy-reminder 계약: user systemd timer + runtime-dir metadata
# (${XDG_RUNTIME_DIR:-/tmp}/omarchy-reminders, omarchy-reminder:185) 만 만진다.
# fake systemctl/systemd-run/notification/shell 로 검증하고 실제 타이머는
# 기다리지 않는다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

src=${COO_OMARCHY_GIT:-$REPO_ROOT/build/omarchy}
[[ -d $src ]] || { echo "skip: 업스트림 클론 없음"; exit 0; }
command -v jq >/dev/null || { echo "skip: jq 없음"; exit 0; }

reminder="$src/bin/omarchy-reminder"
fake="$COO_TEST_SANDBOX/fakebin"
mkdir -p "$fake"
log="$COO_TEST_SANDBOX/calls.log"
export XDG_RUNTIME_DIR="$COO_TEST_SANDBOX/runtime"
mkdir -p "$XDG_RUNTIME_DIR"
reminder_dir="$XDG_RUNTIME_DIR/omarchy-reminders"

timers_json="$COO_TEST_SANDBOX/timers.json"
timers_text="$COO_TEST_SANDBOX/timers.txt"
echo '[]' >"$timers_json"
: >"$timers_text"

cat >"$fake/systemctl" <<EOF
#!/usr/bin/env bash
echo "systemctl \$*" >>"$log"
if [[ " \$* " == *" list-timers "* ]]; then
  if [[ " \$* " == *" --output=json "* ]]; then
    cat "$timers_json"
  else
    cat "$timers_text"
  fi
fi
exit 0
EOF
cat >"$fake/systemd-run" <<EOF
#!/usr/bin/env bash
echo "systemd-run \$*" >>"$log"
exit 0
EOF
cat >"$fake/omarchy-notification-send" <<EOF
#!/usr/bin/env bash
echo "notify \$*" >>"$log"
exit 0
EOF
cat >"$fake/omarchy-shell" <<EOF
#!/usr/bin/env bash
echo "omarchy-shell \$*" >>"$log"
exit 0
EOF
chmod +x "$fake"/*

run_reminder() { PATH="$fake:$PATH" bash "$reminder" "$@"; }

# --- create: systemd-run --user + runtime-dir message file ---
: >"$log"
run_reminder 5 "Check the oven"; code=$?
assert_eq "$code" "0" "reminder create: exit 0"
grep -q '^systemd-run --user .*--on-active=5m .*--unit=omarchy-reminder-5m-' "$log" && x=0 || x=1
assert_eq "$x" "0" "reminder create: systemd-run --user --on-active=5m"
grep -q '^systemd-run --system' "$log" && x=1 || x=0
assert_eq "$x" "0" "reminder create: system systemd-run 없음"
msg_file=$(find "$reminder_dir" -name 'omarchy-reminder-5m-*.message' 2>/dev/null | head -1)
[[ -n $msg_file ]] && x=0 || x=1
assert_eq "$x" "0" "reminder create: runtime-dir message 파일"
assert_eq "$(cat "$msg_file")" "Check the oven" "reminder create: message 내용"
grep -q '^notify ' "$log" && x=0 || x=1
assert_eq "$x" "0" "reminder create: 확인 알림"

# --- show --json: timer fixture + message label ---
now=$(date +%s)
next_us=$(( (now + 300) * 1000000 ))
cat >"$timers_json" <<EOF
[{"unit":"omarchy-reminder-5m-123.timer","next":$next_us}]
EOF
# show 는 timer unit 이름에서 message 파일을 찾는다 — fixture unit 과 맞춘다.
printf 'Check the oven' >"$reminder_dir/omarchy-reminder-5m-123.message"
out=$(run_reminder show --json); code=$?
assert_eq "$code" "0" "reminder show --json: exit 0"
assert_eq "$(jq -r '.count' <<<"$out")" "1" "show --json: count 1"
assert_eq "$(jq -r '.reminders[0].label' <<<"$out")" "Check the oven" "show --json: message label"
assert_eq "$(jq -r '.reminders[0].minutes' <<<"$out")" "5" "show --json: minutes 5"
assert_eq "$(jq -r '.active' <<<"$out")" "true" "show --json: active true"

# --- clear: 일치하는 user timer 만 stop, own message 만 삭제 ---
cat >"$timers_text" <<'EOF'
Mon 2026-08-17 21:00:00 KST  4min left  n/a  n/a  omarchy-reminder-5m-123.timer  omarchy-reminder-5m-123.service
EOF
stray="$reminder_dir/unrelated.message"
printf 'keep me' >"$stray"
: >"$log"
run_reminder clear; code=$?
assert_eq "$code" "0" "reminder clear: exit 0"
grep -q '^systemctl --user stop omarchy-reminder-5m-123.timer omarchy-reminder-5m-123.service' "$log" && x=0 || x=1
assert_eq "$x" "0" "reminder clear: 일치 timer 만 stop"
[[ ! -e $reminder_dir/omarchy-reminder-5m-123.message && ! -e $reminder_dir/omarchy-reminder-5m-"$now".message ]] && x=0 || x=1
n=$(find "$reminder_dir" -name 'omarchy-reminder-*.message' 2>/dev/null | wc -l)
assert_eq "$n" "0" "reminder clear: own message 전부 삭제"
[[ -f $stray && $(cat "$stray") == "keep me" ]] && x=0 || x=1
assert_eq "$x" "0" "reminder clear: 무관한 파일은 유지"

# --- -i: shell summon omarchy.reminders ---
: >"$log"
run_reminder -i; code=$?
assert_eq "$code" "0" "reminder -i: exit 0"
grep -q '^omarchy-shell shell summon omarchy.reminders {}' "$log" && x=0 || x=1
assert_eq "$x" "0" "reminder -i: shell summon omarchy.reminders"

# --- 잘못된 인자: usage + exit 1 ---
assert_exit 1 "reminder 0분: exit 1" env PATH="$fake:$PATH" bash "$reminder" 0
assert_exit 1 "reminder 비숫자: exit 1" env PATH="$fake:$PATH" bash "$reminder" soon

exit "$ASSERT_FAILURES"
