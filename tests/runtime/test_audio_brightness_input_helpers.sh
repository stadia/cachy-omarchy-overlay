#!/usr/bin/env bash
# Audio switch / brightness / touchpad-touchscreen helpers.
# fake pactl/wpctl/hyprctl/brightnessctl/systemctl only — live session untouched.
# omarchy-restart-audio and audio-tuning on/off are not executed (they would
# talk to user systemd / pipewire).
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

src=${COO_OMARCHY_GIT:-$REPO_ROOT/build/omarchy}
[[ -d $src ]] || { echo "skip: 업스트림 클론 없음"; exit 0; }
command -v jq >/dev/null || { echo "skip: jq 없음"; exit 0; }

bin_src="$src/bin"
fake="$COO_TEST_SANDBOX/fakebin"
mkdir -p "$fake"
log="$COO_TEST_SANDBOX/calls.log"
export XDG_RUNTIME_DIR="$COO_TEST_SANDBOX/runtime"
mkdir -p "$XDG_RUNTIME_DIR"
backlight="$COO_TEST_SANDBOX/backlight"
mkdir -p "$backlight/intel_backlight" "$backlight/appletb_backlight"
export OMARCHY_BACKLIGHT_PATH="$backlight"
export OMARCHY_PATH="$src"

cat >"$fake/sudo" <<EOF
#!/usr/bin/env bash
echo "UNEXPECTED sudo \$*" >>"$log"
echo "UNEXPECTED sudo \$*" >&2
exit 99
EOF
cat >"$fake/systemctl" <<EOF
#!/usr/bin/env bash
echo "UNEXPECTED systemctl \$*" >>"$log"
echo "UNEXPECTED systemctl \$*" >&2
exit 99
EOF
cat >"$fake/omarchy-osd" <<EOF
#!/usr/bin/env bash
echo "osd \$*" >>"$log"
exit 0
EOF
cat >"$fake/omarchy-audio-tuning" <<EOF
#!/usr/bin/env bash
echo "audio-tuning \$*" >>"$log"
exit 1
EOF
cat >"$fake/pactl" <<'EOF'
#!/usr/bin/env bash
echo "pactl $*" >>"${COO_FAKE_LOG:?}"
if [[ ${1:-} == -f && ${2:-} == json && ${3:-} == list && ${4:-} == sinks ]]; then
  cat <<'JSON'
[
  {"index": 41, "name": "alsa_output.fake-a", "description": "Speakers", "ports": [], "volume": {"front-left": {"value_percent": "50%"}}},
  {"index": 42, "name": "alsa_output.fake-b", "description": "Headphones", "ports": [], "volume": {"front-left": {"value_percent": "40%"}}}
]
JSON
  exit 0
fi
case "${1:-}" in
  get-default-sink) echo "alsa_output.fake-a" ;;
  get-sink-volume) echo 'Volume: front-left: 26214 /  40% / -23.52 dB' ;;
  get-sink-mute) echo 'Mute: no' ;;
  set-default-sink) ;;
  list) ;;
esac
exit 0
EOF
cat >"$fake/wpctl" <<EOF
#!/usr/bin/env bash
echo "wpctl \$*" >>"$log"
exit 0
EOF
cat >"$fake/hyprctl" <<EOF
#!/usr/bin/env bash
echo "hyprctl \$*" >>"$log"
case "\${1:-}" in
  devices)
    cat <<'JSON'
{"mice":[{"name":"test-touchpad"}],"touch":[],"tablets":[]}
JSON
    ;;
  monitors)
    cat <<'JSON'
[{"name":"eDP-1","focused":true,"disabled":false,"dpmsStatus":true,"make":"AUO","model":"Panel"}]
JSON
    ;;
esac
exit 0
EOF
cat >"$fake/brightnessctl" <<EOF
#!/usr/bin/env bash
echo "brightnessctl \$*" >>"$log"
if [[ \${1:-} == -d && \${3:-} == -m ]]; then
  echo "intel_backlight,backlight,960,50%,1920"
fi
exit 0
EOF
chmod +x "$fake"/*

export COO_FAKE_LOG="$log"
run() { PATH="$fake:$bin_src:/usr/bin:/bin" bash "$@"; }

# --- audio-output-switch: rotate default sink, no live pactl ---
: >"$log"
run "$bin_src/omarchy-audio-output-switch"; code=$?
assert_eq "$code" "0" "audio-output-switch: exit 0"
grep -q '^audio-tuning fronted-sink' "$log" && x=0 || x=1
assert_eq "$x" "0" "audio-output-switch: tuning fronted-sink 가드"
grep -q '^wpctl set-default 42' "$log" && x=0 || x=1
assert_eq "$x" "0" "audio-output-switch: wpctl set-default next index"
grep -q '^pactl set-default-sink alsa_output.fake-b' "$log" && x=0 || x=1
assert_eq "$x" "0" "audio-output-switch: pactl set-default-sink next name"
grep -q '^osd -i volume-medium -m Headphones' "$log" && x=0 || x=1
assert_eq "$x" "0" "audio-output-switch: OSD 다음 장치"
if grep -q '^UNEXPECTED ' "$log"; then x=1; else x=0; fi
assert_eq "$x" "0" "audio-output-switch: sudo/systemctl 미호출"

# --- hw-display: fake sysfs, appletb 제외 후 intel 선호 ---
out=$(run "$bin_src/omarchy-hw-display"); code=$?
assert_eq "$code" "0" "hw-display: exit 0"
assert_eq "$out" "intel_backlight" "hw-display: intel_backlight 선택"

# --- brightness-display query + step on internal panel ---
: >"$log"
out=$(run "$bin_src/omarchy-brightness-display"); code=$?
assert_eq "$code" "0" "brightness-display query: exit 0"
assert_eq "$out" "50" "brightness-display query: 50%"
: >"$log"
run "$bin_src/omarchy-brightness-display" "+5%"; code=$?
assert_eq "$code" "0" "brightness-display +5%: exit 0"
grep -q '^brightnessctl -d intel_backlight set 55%' "$log" && x=0 || x=1
assert_eq "$x" "0" "brightness-display +5%: brightnessctl set 55%"
grep -q '^osd -i brightness -p 50' "$log" && x=0 || x=1
assert_eq "$x" "0" "brightness-display +5%: OSD"
if grep -q '^UNEXPECTED ' "$log"; then x=1; else x=0; fi
assert_eq "$x" "0" "brightness-display: sudo 미호출 (apple 경로 아님)"

# --- hw-touchpad / empty touchscreen ---
out=$(run "$bin_src/omarchy-hw-touchpad"); code=$?
assert_eq "$code" "0" "hw-touchpad: exit 0"
assert_eq "$out" "test-touchpad" "hw-touchpad: hyprctl devices 이름"
out=$(run "$bin_src/omarchy-hw-touchscreen"); code=$?
assert_eq "$out" "" "hw-touchscreen: 장치 없으면 빈 출력"

# --- toggle-touchpad: hyprctl eval + sandbox state file, no live compositor ---
# 4.0.1: 상태는 생성 Lua(touchpad-disabled.lua)가 아니라 데이터 파일
# (*-disabled-name)에 장치 이름만 들어간다 — 이름이 절대 코드로 생성되지
# 않는다. 복원 쪽은 overlay/hypr/bindings.lua seam 이 담당한다.
: >"$log"
run "$bin_src/omarchy-toggle-touchpad" off; code=$?
assert_eq "$code" "0" "toggle-touchpad off: exit 0"
state="$HOME/.local/state/omarchy/toggles/hypr/touchpad-disabled-name"
assert_file_exists "$state" "toggle-touchpad off: 상태 파일"
assert_contains "$(cat "$state")" "test-touchpad" "toggle-touchpad off: 장치 이름"
grep -q 'hyprctl eval' "$log" && x=0 || x=1
assert_eq "$x" "0" "toggle-touchpad off: hyprctl eval"
grep -q '^osd -i touchpad -m Touchpad disabled' "$log" && x=0 || x=1
assert_eq "$x" "0" "toggle-touchpad off: OSD"
: >"$log"
run "$bin_src/omarchy-toggle-touchpad" on; code=$?
assert_eq "$code" "0" "toggle-touchpad on: exit 0"
[[ -e $state ]] && x=1 || x=0
assert_eq "$x" "0" "toggle-touchpad on: 상태 파일 제거"
grep -q '^osd -i touchpad -m Touchpad enabled' "$log" && x=0 || x=1
assert_eq "$x" "0" "toggle-touchpad on: OSD"

exit "$ASSERT_FAILURES"
