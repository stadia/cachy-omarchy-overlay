#!/usr/bin/env bash
# omarchy-weather-location / -status 는 실 wttr.in 을 치지 않고, IP 조회는
# weather.json 을 쓰지 않는다. 패널 QML 은 Open-Meteo 도 부른다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

src=${COO_OMARCHY_GIT:-$REPO_ROOT/build/omarchy}
[[ -d $src/bin ]] || { echo "skip: 업스트림 클론 없음"; exit 0; }

stage=$COO_TEST_SANDBOX/pkg
bash "$REPO_ROOT/packages/cachy-omarchy-shell/stage-upstream.sh" "$src" "$stage" \
  "$REPO_ROOT/overlay/defaults"
bin="$stage/usr/share/cachy-omarchy/upstream/bin"
assert_file_exists "$bin/omarchy-weather-location" "스테이징: omarchy-weather-location"
assert_file_exists "$bin/omarchy-weather-status" "스테이징: omarchy-weather-status"

fake=$COO_TEST_SANDBOX/fake-bin
mkdir -p "$fake"
export COO_CURL_LOG=$COO_TEST_SANDBOX/curl.log
: >"$COO_CURL_LOG"

cat >"$fake/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${COO_CURL_LOG:?}"
url=
for arg in "$@"; do
  [[ $arg == https://* ]] && url=$arg
done
case $url in
  *'wttr.in/?format=%l'*) printf 'Seoul,South Korea\n' ;;
  *'wttr.in/'*'format=%t|'*) printf '+21°C|11km/h\n' ;;
  *)
    printf 'unexpected curl url: %s\n' "$url" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$fake/curl"

loc_file=$HOME/.local/state/omarchy/settings/weather.json
rm -rf "$HOME/.local/state/omarchy"
: >"$COO_CURL_LOG"

out=$(PATH="$fake:$bin:$PATH" "$bin/omarchy-weather-location")
assert_eq "$out" "Seoul" "인자 없는 조회는 IP 도시명을 stdout 에만 낸다"
if [[ -e $loc_file ]]; then wrote=1; else wrote=0; fi
assert_eq "$wrote" "0" "IP 조회는 weather.json 을 만들지 않는다"
assert_contains "$(cat "$COO_CURL_LOG")" "wttr.in/?format=%l" "IP 조회는 wttr.in format=%l 만 친다"

PATH="$fake:$bin:$PATH" "$bin/omarchy-weather-location" --set "Malibu" "34.02577,-118.7804"
assert_file_exists "$loc_file" "--set 은 weather.json 을 만든다"
assert_eq "$(jq -c . "$loc_file")" '{"name":"Malibu","latitude":34.02577,"longitude":-118.7804}' \
  "--set 은 name+좌표 JSON 을 쓴다"

: >"$COO_CURL_LOG"
out=$(PATH="$fake:$bin:$PATH" "$bin/omarchy-weather-location")
assert_eq "$out" "Malibu" "저장된 이름은 curl 없이 반환한다"
if [[ -s $COO_CURL_LOG ]]; then curled=1; else curled=0; fi
assert_eq "$curled" "0" "저장된 위치가 있으면 IP 조회를 다시 치지 않는다"

PATH="$fake:$bin:$PATH" "$bin/omarchy-weather-location" --clear
if [[ -e $loc_file ]]; then left=1; else left=0; fi
assert_eq "$left" "0" "--clear 는 weather.json 을 지운다"

: >"$COO_CURL_LOG"
out=$(PATH="$fake:$bin:$PATH" "$bin/omarchy-weather-status")
assert_eq "$out" "Seoul  ·  Temp 21°C  ·  Wind 11km/h" \
  "weather-status 는 location+wttr 온도/풍속 문자열을 만든다"

qml="$stage/usr/share/cachy-omarchy/upstream/shell/plugins/panels/weather/Panel.qml"
assert_file_exists "$qml" "weather 패널 QML 스테이징"
panel=$(cat "$qml")
assert_contains "$panel" "https://api.open-meteo.com/v1/forecast" \
  "패널은 Open-Meteo forecast 를 요청한다"
assert_contains "$panel" "https://geocoding-api.open-meteo.com/v1/search" \
  "패널은 Open-Meteo geocoding 을 요청한다"
assert_contains "$panel" "https://wttr.in/" "패널은 wttr.in 도 요청한다"

# 업데이트 파이프라인 중첩 픽스처는 overlay README 를 복사하지 않는다.
# 헬퍼/QML 단언은 그 픽스처에서도 유효하고, 문서 단언만 실제 저장소에서 한다.
if [[ -n ${COO_UPDATE_PIPELINE_NESTED:-} ]]; then
  printf 'note: 중첩 업데이트 픽스처 — README Open-Meteo 단언 생략\n'
else
  for doc in "$REPO_ROOT/README.md" "$REPO_ROOT/README.ko-KR.md" \
             "$REPO_ROOT/docs/CLOSURE_PRIORITY.md"; do
    assert_file_exists "$doc" "$doc 존재"
    body=$(cat "$doc")
    assert_contains "$body" "Open-Meteo" "$doc 가 Open-Meteo 를 명시한다"
    assert_contains "$body" "wttr.in" "$doc 가 wttr.in 을 명시한다"
  done
fi

exit "$ASSERT_FAILURES"
