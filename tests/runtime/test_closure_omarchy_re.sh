#!/usr/bin/env bash
# v0.9: closure_check.py 의 omarchy-* 루트 수확 회귀 검사.
#
# 이 스캐너는 좁히는 수정에서 두 번 조용히 루트를 잃었고, 두 번 다 나중에
# "사라진 것을 diff 해 본 사람" 이 찾아냈다. 그 diff 를 여기 고정한다.
#
# 고정하는 결함 셋:
#  1) `\bomarchy-` 가 `cachy-omarchy-launcher` **안쪽**에 매치돼 우리가
#     직접 배포하는 명령을 미스테이징 업스트림 헬퍼로 보고했다.
#  2) 그것을 막으려고 넣은 lookbehind 가 하이픈을 무조건 거부해,
#     `${VAR:-omarchy-...}` 안의 진짜 호출까지 함께 버렸다.
#  3) BFS 가 preprocess_bash() 된 텍스트에서 루트를 수확해, 큰따옴표
#     안에서만 불리는 헬퍼가 그래프에서 통째로 사라졌다(실측 30개).
#
# 빌드 아티팩트가 필요 없는 순수 텍스트 검사라 build/ 없이도 매번 돈다 —
# test_closure_pkgbuild_parse.sh 와 같은 이유다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

result=$(python3 - "$REPO_ROOT/tests/runtime" <<'PY'
import sys

sys.path.insert(0, sys.argv[1])
import closure_check as m


def names(text):
    return "|".join(sorted(m.OMARCHY_RE.findall(text)))


def harvested(text):
    return "|".join(sorted(m.omarchy_names(text)))


# --- OMARCHY_RE boundary ---------------------------------------------
print(names("exec, cachy-omarchy-launcher"))
print(names('hl.dsp.exec_cmd("cachy-omarchy-keybindings")'))
print(names('EXEC_COMMAND="${CUSTOM_EXEC:-omarchy-launch-webapp $APP_URL}"'))
print(names('stale="$h/pipewire.conf.d/90-omarchy-speaker-tuning.conf"'))
print(names("NM_DNS_CONF=/etc/NetworkManager/conf.d/20-omarchy-dns.conf"))
print(names("99-omarchy-nopasswd-$USER"))
print(names('"omarchy-hw-$KIND"'))

# --- raw vs preprocessed harvesting ----------------------------------
quoted = 'notify_cmd="omarchy-clipboard-paste-file --wait"\n'
# preprocess_bash() 는 큰따옴표 payload 를 지운다: 이것이 결함의 원인.
print(names(m.preprocess_bash(quoted)))
# 실제 수확기는 원문을 읽으므로 헬퍼가 보인다.
print(harvested(quoted))

# 수확기가 걷어내야 하는 것들: 주석 산문, 동적 조립, 확장자 달린 파일
# 이름, 런타임 데이터 경로.
print(harvested("# see omarchy-migrate for the carried-on case\n"))
print(harvested('KIND_CMD="omarchy-hw-$KIND"\n'))
print(harvested('ln -sfn "$g" "$d/themes/omarchy-color-theme.json"\n'))
print(harvested('MARKER="${XDG_RUNTIME_DIR:-/tmp}/omarchy-capture-region-window"\n'))
# 반대로 bin/ 아래 실행 파일 경로는 살아남아야 한다.
print(harvested('"$OMARCHY_PATH/bin/omarchy-clipboard-paste-file"\n'))

# --- QML/JS: 모든 문자열 리터럴에서 넓게 수확 --------------------------
# idle 서비스의 자체 정의 runProcess(process, label, command) — 좁은 다섯
# 형태 중 어느 것도 잡지 못했고, omarchy-launch-screensaver 가 감사에서
# 통째로 빠져 있었다.
idle = (
    'runProcess(screensaverProcess, "screensaver", '
    '"[[ $(omarchy-shell lock isLocked) == true ]] || omarchy-launch-screensaver")'
)
print("|".join(sorted(m.qml_commands(idle))))
print("|".join(sorted(m.qml_omarchy_names(idle))))

# 식별자 문자열도 넓은 수확에는 걸린다 — 그것을 거르는 것은 이제 정규식이
# 아니라 인벤토리(ground truth)의 몫이다.
print("|".join(sorted(m.qml_omarchy_names('reloadableId: "omarchy-battery"'))))

# 문자열 리터럴은 개행을 넘지 않는다: 영어 산문의 아포스트로피 두 개가
# 짝지어져 주석 여러 줄을 문자열로 삼키면 안 된다.
prose = "// an empty commit returns to auto.\n// mirrors omarchy-weather-icon's map.\n"
print("|".join(sorted(m.qml_omarchy_names(prose))))

# 함수 정의는 호출이 아니다 — MenuModel.js 가 생성 스크립트 서두에 인라인
# 정의하는 이름들이 업스트림 bin/ 에도 실재해 인벤토리를 통과한다.
print("|".join(sorted(m.omarchy_names("omarchy-pkg-present() { local p; return 0; }"))))
PY
)

line() { printf '%s\n' "$result" | sed -n "$1p"; }

assert_eq "$(line 1)" "" "cachy-omarchy-launcher 안쪽에 매치되지 않는다"
assert_eq "$(line 2)" "" "cachy-omarchy-keybindings 안쪽에 매치되지 않는다"
assert_eq "$(line 3)" "omarchy-launch-webapp" \
  '${VAR:-omarchy-...} 의 진짜 호출은 잡는다'
assert_eq "$(line 4)" "" "90- 접두 설정 파일 이름은 명령이 아니다"
assert_eq "$(line 5)" "" "20- 접두 설정 파일 이름은 명령이 아니다"
assert_eq "$(line 6)" "" "99- 접두 sudoers 드롭인 이름은 명령이 아니다"
assert_eq "$(line 7)" "omarchy-hw" \
  "동적 조립 이름은 잘린 리터럴로 남지 않는다(세그먼트 non-empty)"

assert_eq "$(line 8)" "" \
  "preprocess_bash 는 큰따옴표 안 헬퍼를 지운다(결함 재현)"
assert_eq "$(line 9)" "omarchy-clipboard-paste-file" \
  "루트 수확은 원문을 읽어 큰따옴표 안 헬퍼를 본다"

assert_eq "$(line 10)" "" "주석 산문 속 이름은 수확하지 않는다"
assert_eq "$(line 11)" "" "동적 조립 접두사는 수확하지 않는다"
assert_eq "$(line 12)" "" "확장자 달린 파일 이름은 수확하지 않는다"
assert_eq "$(line 13)" "" "런타임 데이터 경로의 마커 이름은 수확하지 않는다"
assert_eq "$(line 14)" "omarchy-clipboard-paste-file" \
  "bin/ 아래 실행 파일 경로는 그대로 수확한다"

assert_eq "$(line 15)" "" \
  "좁은 다섯 형태는 자체 정의 runProcess 호출을 잡지 못한다(결함 재현)"
assert_eq "$(line 16)" "omarchy-launch-screensaver|omarchy-shell" \
  "넓은 수확은 runProcess 셸 문자열 속 헬퍼를 본다"
assert_eq "$(line 17)" "omarchy-battery" \
  "식별자 문자열도 넓게 잡고, 거르는 일은 인벤토리에 맡긴다"
assert_eq "$(line 18)" "" \
  "문자열 리터럴은 개행을 넘지 않는다(주석 아포스트로피 짝짓기 방지)"
assert_eq "$(line 19)" "" \
  "bash 함수 정의는 호출이 아니다"

exit $((ASSERT_FAILURES > 0))
