#!/usr/bin/env bash
# M10 Task 5 — OSD direct IPC + audio bridge(volume/input-mute) 계약.
# fake omarchy-shell/pactl/wpctl/omarchy-osd/brightness-keyboard-mute 로 검증하고
# 실제 오디오 장치·OSD 패널·/sys LED 는 만지지 않는다.
# 근거: M10 플랜 Task 5, 설계 문서 D6 (switch/tuning·display brightness 제외).
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

cat >"$fake/omarchy-shell" <<EOF
#!/usr/bin/env bash
echo "omarchy-shell \$*" >>"$log"
[[ \${COO_FAKE_SHELL_FAIL:-0} == 1 ]] && exit 1
exit 0
EOF
cat >"$fake/omarchy-osd" <<EOF
#!/usr/bin/env bash
echo "osd \$*" >>"$log"
exit 0
EOF
cat >"$fake/omarchy-audio-output-sink" <<'EOF'
#!/usr/bin/env bash
echo "alsa_output.fake"
EOF
cat >"$fake/pactl" <<EOF
#!/usr/bin/env bash
echo "pactl \$*" >>"$log"
case "\${1:-} \${2:-}" in
  "get-sink-volume "*) echo 'Volume: front-left: 32768 /  50% / -18.06 dB' ;;
  "get-sink-mute "*) echo 'Mute: no' ;;
esac
exit 0
EOF
cat >"$fake/wpctl" <<EOF
#!/usr/bin/env bash
echo "wpctl \$*" >>"$log"
if [[ \${1:-} == get-volume ]]; then
  # :- 가 아니라 - 를 쓴다: 빈 문자열(unmute)과 unset(muted)을 구분해야 한다.
  echo "Volume: 0.40 \${FAKE_WPCTL_SUFFIX-[MUTED]}"
fi
exit 0
EOF
cat >"$fake/omarchy-brightness-keyboard-mute" <<EOF
#!/usr/bin/env bash
echo "keyboard-mute \$*" >>"$log"
exit 0
EOF
chmod +x "$fake"/*

run() { PATH="$fake:$PATH" bash "$@"; }

# --- omarchy-osd: payload shape + shell IPC ---
: >"$log"
run "$bin_src/omarchy-osd" -i volume-high -m "Hello" -p 42; code=$?
assert_eq "$code" "0" "osd: exit 0"
payload=$(sed -n 's/^omarchy-shell -q osd show //p' "$log")
[[ -n $payload ]] && x=0 || x=1
assert_eq "$x" "0" "osd: omarchy-shell -q osd show 호출"
assert_eq "$(jq -r '.icon' <<<"$payload")" "volume-high" "osd: payload icon"
assert_eq "$(jq -r '.message' <<<"$payload")" "Hello" "osd: payload message"
assert_eq "$(jq -r '.value' <<<"$payload")" "42" "osd: payload value"
assert_eq "$(jq -r '.progressText' <<<"$payload")" "42%" "osd: payload progressText"

# --- omarchy-osd: shell 실패는 non-zero 로 전파 (조용한 실패 아님) ---
: >"$log"
COO_FAKE_SHELL_FAIL=1 run "$bin_src/omarchy-osd" -m x >/dev/null 2>&1 && x=0 || x=$?
[[ $x -ne 0 ]] && x=0 || x=1
assert_eq "$x" "0" "osd: shell 실패 시 non-zero"

# --- audio-output-volume raise: pactl + OSD ---
: >"$log"
run "$bin_src/omarchy-audio-output-volume" raise; code=$?
assert_eq "$code" "0" "volume raise: exit 0"
grep -q '^pactl set-sink-volume alsa_output.fake 55%' "$log" && x=0 || x=1
assert_eq "$x" "0" "volume raise: pactl set-sink-volume 55%"
grep -q '^osd -i volume-high -p 50' "$log" && x=0 || x=1
assert_eq "$x" "0" "volume raise: omarchy-osd 호출"

# --- audio-output-volume mute-toggle: debounce 파일은 runtime dir 에 ---
: >"$log"
run "$bin_src/omarchy-audio-output-volume" mute-toggle; code=$?
assert_eq "$code" "0" "volume mute-toggle: exit 0"
grep -q '^pactl set-sink-mute alsa_output.fake toggle' "$log" && x=0 || x=1
assert_eq "$x" "0" "volume mute-toggle: pactl mute toggle"
[[ -f $XDG_RUNTIME_DIR/omarchy-audio-output-volume-mute-toggle.last ]] && x=0 || x=1
assert_eq "$x" "0" "volume mute-toggle: debounce 파일은 runtime dir"

# --- audio-input-mute: wpctl + mic LED guard + OSD ---
: >"$log"
run "$bin_src/omarchy-audio-input-mute"; code=$?
assert_eq "$code" "0" "input-mute: exit 0"
grep -q '^wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle' "$log" && x=0 || x=1
assert_eq "$x" "0" "input-mute: wpctl set-mute toggle"
grep -q '^keyboard-mute on' "$log" && x=0 || x=1
assert_eq "$x" "0" "input-mute: brightness-keyboard-mute on 호출 (closure)"
grep -q '^osd -i microphone-muted -m Microphone muted' "$log" && x=0 || x=1
assert_eq "$x" "0" "input-mute: microphone-muted OSD"

: >"$log"
FAKE_WPCTL_SUFFIX="" run "$bin_src/omarchy-audio-input-mute"
grep -q '^keyboard-mute off' "$log" && x=0 || x=1
assert_eq "$x" "0" "input-mute unmute: keyboard-mute off"
grep -q '^osd -i microphone -m Microphone on' "$log" && x=0 || x=1
assert_eq "$x" "0" "input-mute unmute: microphone on OSD"

# --- keyboard-mute: LED 노드/brightnessctl 부재 시 no-op exit 0 ---
# PATH 에 brightnessctl 을 두지 않는다 — 스크립트 자체 가드가 성립해야 한다.
( PATH="/usr/bin:/bin" bash "$bin_src/omarchy-brightness-keyboard-mute" on ) && x=0 || x=1
assert_eq "$x" "0" "keyboard-mute: LED/brightnessctl 부재 시 no-op exit 0"
src_body=$(cat "$bin_src/omarchy-brightness-keyboard-mute")
assert_contains "$src_body" 'platform::micmute' "keyboard-mute: micmute LED 노드 가드"
if grep -q 'brightness-display' <<<"$src_body"; then x=1; else x=0; fi
assert_eq "$x" "0" "keyboard-mute: display brightness 체인 참조 없음"

# --- M10 소스 경계: audio-output-volume 은 여전히 switch/tuning 을 부르지 않는다.
#     switch 채택은 tests/runtime/test_audio_brightness_input_helpers.sh. ---
vol_body=$(cat "$bin_src/omarchy-audio-output-volume")
if grep -q 'audio-tuning\|output-switch' <<<"$vol_body"; then x=1; else x=0; fi
assert_eq "$x" "0" "volume: audio-tuning/switch 참조 없음"

exit "$ASSERT_FAILURES"
