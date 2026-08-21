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

exit $((ASSERT_FAILURES > 0))
