#!/usr/bin/env bash
# README 의 패키지 버전 표가 실제 PKGBUILD 와 일치하는지 고정한다.
#
# 이 표는 v0.9.0·v0.10.0 릴리스마다 사람이 손으로 고쳐 왔고, v0.11.0 에서
# 빠졌다(shell 4.0.0-17, overlay 0.10.0-1 로 낡은 채 출고). 아무 테스트도
# 검사하지 않았기 때문이다 — 이 저장소가 클로저 예외(STALE_EXCEPTION)와 감사
# 표(test_command_audit.sh)에 대해 이미 두 번 내린 결론을, 정작 README 표에는
# 적용하지 않고 있었다. 표가 조용히 거짓말하는 것을 여기서 막는다.
#
# README.md(영어 정본)와 README.ko-KR.md 는 짝이다 — 둘 다 검사한다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

# 업데이트 파이프라인 중첩 픽스처는 후보 트리에서 pkgver 를 새 핀으로 올리고
# overlay README 를 복사하지도 않는다. 이 대조는 실제 저장소에서만 유효하다
# (tests/runtime/test_weather_helpers.sh 와 같은 가드).
if [[ -n ${COO_UPDATE_PIPELINE_NESTED:-} ]]; then
  printf 'note: 중첩 업데이트 픽스처 — README 버전 대조 생략\n'
  exit 0
fi

pkg_version() {
  local pkgbuild=$REPO_ROOT/packages/$1/PKGBUILD ver rel
  ver=$(grep -m1 '^pkgver=' "$pkgbuild" | cut -d= -f2 | tr -d "'\"")
  rel=$(grep -m1 '^pkgrel=' "$pkgbuild" | cut -d= -f2 | tr -d "'\"")
  printf '%s-%s\n' "$ver" "$rel"
}

# 표에서 그 패키지 행의 버전 칸만 뽑는다. 행 전체를 grep 하면 설명 문구가
# 바뀔 때마다 같이 깨지므로, 두 번째 칸만 본다.
readme_version() {
  local readme=$REPO_ROOT/$1 pkg=$2
  grep -F "\`$pkg\`" "$readme" | head -1 | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3}'
}

for pkg in cachy-omarchy-shell cachy-omarchy-overlay; do
  actual=$(pkg_version "$pkg")
  for readme in README.md README.ko-KR.md; do
    assert_eq "$(readme_version "$readme" "$pkg")" "$actual" \
      "$readme 의 $pkg 버전이 PKGBUILD 와 일치"
  done
done

exit "$ASSERT_FAILURES"
