#!/usr/bin/env bash
# omarchy-brightness-keyboard 의 분기를 brightnessctl PATH 스텁으로 고정한다.
# 이 머신은 데스크톱이라 /sys/class/leds/*kbd_backlight* 가 없다 — 실기기로
# 밟히는 것은 "장치 부재 → exit 1" 분기뿐이고, 나머지는 스텁으로 잰다.
# 헬퍼가 /sys 경로를 하드코딩하므로(오버라이드 env 없음) 장치 존재 분기는
# 이 머신에서 실측 불가다. 그 사실을 테스트가 명시적으로 기록한다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

# 업데이트 파이프라인 중첩 픽스처(bin/update-upstream 이 후보 트리에서 이 스위트를
# 돌린다)는 src/omarchy/bin 을 새 핀에서 재생성하는데, 그 픽스처 저장소에는 헬퍼가
# 5개뿐이라 이 파일이 존재하지 않는다. 이 테스트는 통째로 그 한 파일에 대한
# 특성화 테스트이므로 중첩 픽스처에서는 잴 것이 없다 — test_weather_helpers.sh 와
# 같은 가드를 쓴다. 파일 부재가 아니라 중첩 플래그를 조건으로 삼는 것이 중요하다:
# 부재를 조건으로 하면 실제 스테이징 회귀까지 조용히 통과시킨다.
if [[ -n ${COO_UPDATE_PIPELINE_NESTED:-} ]]; then
  printf 'note: 중첩 업데이트 픽스처 — 업스트림 헬퍼 원본 없음, 분기 단언 생략\n'
  exit 0
fi

helper=$REPO_ROOT/packages/cachy-omarchy-shell/src/omarchy/bin/omarchy-brightness-keyboard
assert_file_exists "$helper" "업스트림 소스가 있다"

# 장치 부재 분기: 이 머신의 실제 상태. exit 1 + stderr 문구를 고정한다.
if compgen -G '/sys/class/leds/*kbd_backlight*' >/dev/null; then
  echo "note: 이 머신에 키보드 백라이트가 있다 — 부재 분기 단언을 건너뛴다"
else
  out=$(bash "$helper" up 2>&1); rc=$?
  assert_eq "$rc" "1" "장치 부재 시 exit 1"
  assert_contains "$out" "No keyboard backlight device found" "부재 메시지를 stderr 로 낸다"
fi

# 스텁 층: brightnessctl / omarchy-osd 를 가로채 인자를 기록한다.
stub=$COO_TEST_SANDBOX/stub
mkdir -p "$stub"
cat > "$stub/brightnessctl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "brightnessctl $*" >> "$STUB_LOG"
# max/get 조회에만 값을 돌려준다: max=100, current=50.
case "${*: -1}" in
  max) echo 100 ;;
  get) echo 50 ;;
esac
exit 0
STUB
cat > "$stub/omarchy-osd" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "osd $*" >> "$STUB_LOG"
STUB
chmod +x "$stub/brightnessctl" "$stub/omarchy-osd"

# 헬퍼는 /sys/class/leds 를 직접 글롭한다. 가짜 장치를 만들 수 없으므로
# 장치 탐색 루프만 우회한 복제본으로 계산 분기를 잰다 — 복제 대상은
# 업스트림 원본이며, 바꾸는 것은 device 변수 초기화 한 줄뿐이다.
probe=$COO_TEST_SANDBOX/kbd-probe
sed 's|^device=""$|device="stub_kbd_backlight"|' "$helper" > "$probe"
# 탐색 루프가 device 를 다시 비우지 않도록, 루프 전체를 지운다.
python3 - "$probe" <<'PY'
import sys, io, re
p = sys.argv[1]
s = io.open(p, encoding='utf-8').read()
s = re.sub(r'for candidate in /sys/class/leds/\*kbd_backlight\*; do.*?\ndone\n', '', s, flags=re.S)
io.open(p, 'w', encoding='utf-8').write(s)
PY
grep -q 'device="stub_kbd_backlight"' "$probe" \
  && x=0 || x=1
assert_eq "$x" "0" "복제본이 스텁 장치를 쓴다"
grep -q '/sys/class/leds' "$probe" && x=1 || x=0
assert_eq "$x" "0" "복제본에서 장치 탐색 루프가 제거됐다"

run_probe() {
  STUB_LOG=$COO_TEST_SANDBOX/calls.log
  : > "$STUB_LOG"
  export STUB_LOG
  PATH="$stub:$PATH" bash "$probe" "$@" >/dev/null 2>&1
  cat "$STUB_LOG"
}

# max=100 → step=10, current=50.
assert_contains "$(run_probe up)" "brightnessctl -d stub_kbd_backlight set 60" "up 은 +10"
assert_contains "$(run_probe down)" "brightnessctl -d stub_kbd_backlight set 40" "down 은 -10"
assert_contains "$(run_probe cycle)" "brightnessctl -d stub_kbd_backlight set 60" "cycle 은 상한 전까지 +10"
assert_contains "$(run_probe off)" "brightnessctl -sd stub_kbd_backlight set 0" "off 는 저장 후 0"
assert_contains "$(run_probe restore)" "brightnessctl -rd stub_kbd_backlight" "restore 는 -r"
assert_contains "$(run_probe up)" "osd -i keyboard -p 60" "OSD 는 백분율로 부른다"
out=$(run_probe --no-osd up)
grep -q '^osd ' <<<"$out" && x=1 || x=0
assert_eq "$x" "0" "--no-osd 는 OSD 를 부르지 않는다"

exit "$ASSERT_FAILURES"
