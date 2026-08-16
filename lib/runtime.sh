#!/usr/bin/env bash
# 패키지 아티팩트 추출과 업스트림 루트 해석. source 전용, 실행하지 않는다.

coo_repo_root() {
  if [[ -n ${COO_REPO_ROOT_OVERRIDE:-} ]]; then
    printf '%s\n' "$COO_REPO_ROOT_OVERRIDE"
    return 0
  fi
  printf '%s\n' "${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
}

# 최신 빌드 아티팩트 하나를 출력한다. 없으면 exit 1, 출력 없음.
coo_pkg_artifact() {
  local root; root=$(coo_repo_root)
  local newest=""
  local f
  for f in "$root"/build/cachy-omarchy-shell-*.pkg.tar.zst; do
    [[ -f $f ]] || continue
    [[ -z $newest || $f -nt $newest ]] && newest=$f
  done
  [[ -n $newest ]] || return 1
  printf '%s\n' "$newest"
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
