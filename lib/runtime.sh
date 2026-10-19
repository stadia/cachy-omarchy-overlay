#!/usr/bin/env bash
# 패키지 아티팩트 추출과 업스트림 루트 해석. source 전용, 실행하지 않는다.

coo_repo_root() {
  if [[ -n ${COO_REPO_ROOT_OVERRIDE:-} ]]; then
    printf '%s\n' "$COO_REPO_ROOT_OVERRIDE"
    return 0
  fi
  printf '%s\n' "${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
}

# 현재 메타데이터(upstream.lock + PKGBUILD, bin/package-names.sh)가 가리키는
# 아티팩트 경로를 출력한다. build/ 는 롤백 이력으로 옛 버전을 남기므로 mtime 이
# 아니라 이름으로 고른다 — bin/test-packages 가 확인하는 파일과 같다. 이름을 계산할
# 수 없거나 파일이 없으면 exit 1, 출력 없음. 서브셸이라 lock 변수가 새지 않는다.
coo_current_artifact() (
  local kind=${1:?kind} root build_dir name
  root=$(coo_repo_root)
  build_dir=${COO_BUILD_DIR:-$root/build}
  [[ -f $root/bin/package-names.sh ]] || exit 1
  # shellcheck disable=SC1091
  source "$root/bin/package-names.sh"
  coo_current_artifacts "$root" 2>/dev/null || exit 1
  case $kind in
    shell) name=$COO_SHELL_ARTIFACT ;;
    overlay) name=$COO_OVERLAY_ARTIFACT ;;
    *) exit 1 ;;
  esac
  [[ -f $build_dir/$name ]] || exit 1
  printf '%s\n' "$build_dir/$name"
)

# 현재 셸 빌드 아티팩트. 없으면 exit 1, 출력 없음.
coo_pkg_artifact() {
  coo_current_artifact shell
}

# 아티팩트를 dest 에 추출한다. sudo/pacman 을 쓰지 않는다.
coo_extract_pkg() {
  local dest=${1:?dest}
  local artifact; artifact=$(coo_pkg_artifact) || return 1
  mkdir -p "$dest"
  bsdtar -xf "$artifact" -C "$dest"
}

coo_upstream_root() {
  printf '%s/usr/share/cachy-omarchy/upstream\n' "${1:?dest}"
}

# 현재 오버레이 패키지 아티팩트. 셸 패키지용 coo_pkg_artifact 와 별개다.
coo_overlay_artifact() {
  coo_current_artifact overlay
}

# coo_extract_pkg 와 달리 dest 를 먼저 비운다 (rm -rf). M2 리뷰에서 지적된
# 문제: 같은 dest 에 두 번 추출하면 업스트림에서 삭제된 파일이 이전 추출본에서
# 남아 여전히 존재하는 것처럼 보여 회귀를 가린다. coo_extract_pkg 는 셸
# 패키지용으로 이미 굳어진 동작이라 호환성을 위해 그대로 두고, 신규 함수인
# 이 함수에서만 처음부터 올바르게 만든다.
coo_extract_overlay() {
  local dest=${1:?dest}
  # rm -rf 대상을 최소한으로 검증한다: 슬래시가 없는 값(단일 이름, 예: "foo")이나
  # COO_TEST_SANDBOX 자체는 거부한다. 후자를 막는 이유는 미래의 테스트가 실수로
  # dest=$COO_TEST_SANDBOX 를 넘기면 이 함수가 샌드박스 전체를 스위트 도중에
  # 지워버리기 때문이다(M5 리뷰 지적). 정상 호출자는 항상 샌드박스 "아래"의
  # 하위 디렉터리를 넘기므로 이 검사에 걸리지 않는다.
  if [[ $dest != */* ]]; then
    printf 'error: coo_extract_overlay: 슬래시 없는 dest 거부: %s\n' "$dest" >&2
    return 1
  fi
  if [[ -n ${COO_TEST_SANDBOX:-} && $dest == "$COO_TEST_SANDBOX" ]]; then
    printf 'error: coo_extract_overlay: dest 가 COO_TEST_SANDBOX 자체다 — 거부: %s\n' "$dest" >&2
    return 1
  fi
  local artifact; artifact=$(coo_overlay_artifact) || return 1
  rm -rf "$dest"
  mkdir -p "$dest"
  bsdtar -xf "$artifact" -C "$dest"
}
