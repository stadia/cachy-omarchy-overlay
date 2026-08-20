#!/usr/bin/env bash
# v0.9: closure_check.py 의 depends=()/optdepends=() 파서가 첫 항목에서
# 멈추지 않는지 회귀 검사한다.
#
# 실제 결함: `re.search(r"^optdepends=\((.*?)\)", ...)` 의 non-greedy `.*?\)`
# 는 텍스트에서 처음 만나는 ')' 에서 멈춘다 — 배열의 진짜 종료 괄호가 아니라
# 따옴표 안 설명문에 있는 괄호(예: "... hook (OSC reload)")일 수 있다.
# 실제 PKGBUILD 에서 이 결함은 optdepends 5개 중 1개("tmux")만 파싱하는
# 결과를 냈고, 두 번의 리뷰를 통과할 만큼 조용했다 — 파싱 결과를 파일과
# diff 해 본 사람이 없었기 때문이다. 이 테스트가 그 diff 역할을 고정한다.
#
# 빌드 아티팩트가 필요 없는 순수 텍스트 파싱 검사라 build/ 없이도 항상
# 돈다 — 이 회귀를 다시 놓치지 않으려면 조건 없이 매번 돌아야 한다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

fixture=$(mktemp "${COO_TEST_SANDBOX:-/tmp}/coo-pkgbuild-fixture-XXXXXX")
trap 'rm -f "$fixture"' EXIT
cat >"$fixture" <<'PKGBUILD'
pkgname=fixture
depends=('quickshell' 'hyprland' 'uwsm')
optdepends=(
  'tmux: omarchy-theme-set-tmux hook'
  'foot: omarchy-theme-set-foot hook (OSC reload)'
  'brightnessctl: omarchy-brightness-display internal backlight'
  'ddcutil: omarchy-brightness-display-ddc external monitors'
  'lsp-plugins-lv2: omarchy-audio-tuning limiter'
)
PKGBUILD

result=$(python3 - "$REPO_ROOT/tests/runtime" "$fixture" <<'PY'
import re
import sys

sys.path.insert(0, sys.argv[1])
import closure_check as m

text = open(sys.argv[2]).read()
dep_body = m.extract_bash_array_body(text, "depends")
opt_body = m.extract_bash_array_body(text, "optdepends")
depends = sorted(re.findall(r"'([^']+)'", dep_body))
optdeps = sorted(s.split(":")[0].strip() for s in re.findall(r"'([^']+)'", opt_body))
print("|".join(depends))
print("|".join(optdeps))
PY
)

deps_line=$(printf '%s\n' "$result" | sed -n '1p')
opt_line=$(printf '%s\n' "$result" | sed -n '2p')

assert_eq "$deps_line" "hyprland|quickshell|uwsm" "depends=() 전체 파싱(괄호 없는 케이스)"
assert_eq "$opt_line" "brightnessctl|ddcutil|foot|lsp-plugins-lv2|tmux" \
  "optdepends=() 전체 파싱 — 설명문 안 괄호에서 멈추지 않는다"

exit $((ASSERT_FAILURES > 0))
