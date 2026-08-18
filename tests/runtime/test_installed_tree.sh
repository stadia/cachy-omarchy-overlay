#!/usr/bin/env bash
# 두 패키지를 추출해 "설치된 것처럼" 배치하고, 공개 명령이 그 트리만으로
# 동작하는지 검증한다. 실제 설치(sudo/pacman -U)는 하지 않는다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/lib/runtime.sh"

[[ ${HOME:-} == "${COO_TEST_SANDBOX:?}" ]] \
  || { echo "FAIL: HOME 이 샌드박스가 아니다 — 중단"; exit 1; }

coo_pkg_artifact >/dev/null 2>&1 || { echo "skip: 셸 아티팩트 없음"; exit 0; }
coo_overlay_artifact >/dev/null 2>&1 || { echo "skip: 오버레이 아티팩트 없음"; exit 0; }

root="$COO_TEST_SANDBOX/root"
# 순서가 중요하다: coo_extract_overlay 는 dest 를 rm -rf 로 비우고 시작하므로
# 반드시 먼저 부른다. coo_extract_pkg 는 비우지 않으므로 그 위에 겹친다.
coo_extract_overlay "$root"    # /usr/bin, /usr/lib, /usr/share
coo_extract_pkg "$root"        # /usr/share/cachy-omarchy/upstream 을 겹쳐 놓는다

BIN="$root/usr/bin"
export COO_PREFIX_ROOT="$root/usr/share/cachy-omarchy"
export COO_COMPAT_BIN="$root/usr/lib/cachy-omarchy/compat/bin"

# 1) 셸 래퍼가 추출 트리에서 업스트림을 찾는다.
assert_eq "$("$BIN/cachy-omarchy-shell" --path)" \
  "$COO_PREFIX_ROOT/upstream" "--path 가 설치 트리를 가리킨다"
assert_file_exists "$COO_PREFIX_ROOT/upstream/shell/shell.qml" "업스트림 셸 트리 존재"

# 2) 두 패키지의 shell.json 이 같은 파일이다 (한 정본).
assert_eq "$(jq -S . "$COO_PREFIX_ROOT/upstream/config/omarchy/shell.json")" \
          "$(jq -S . "$COO_PREFIX_ROOT/defaults/shell.json")" \
          "defaults 와 스테이징된 기본값이 동일"

# 3) init 가 설치 트리만으로 동작한다. 이 테스트는 반드시 headless 시드
# 경로만 타야 한다. 실제 세션의 quickshell 을 pgrep 이 발견하면 theme-set post
# 훅이 호스트 Hyprland에 reload를 보낼 수 있다.
stub="$COO_TEST_SANDBOX/stub-bin"
mkdir -p "$stub"
printf '#!/usr/bin/env bash\nexit 1\n' > "$stub/pgrep"
chmod +x "$stub/pgrep"
export COO_HYPR_DIR="$COO_TEST_SANDBOX/hypr"
mkdir -p "$COO_HYPR_DIR"; : > "$COO_HYPR_DIR/hyprland.conf"
out=$(PATH="$stub:$BIN:$PATH" "$BIN/cachy-omarchy-init" 2>&1); code=$?
assert_eq "$code" "0" "설치 트리에서 init exit 0"
assert_file_exists "$HOME/.config/cachy-omarchy/hypr/bindings.conf" "init 가 바인딩 배치"
[[ -e "$HOME/.local/state/omarchy/toggles/bar-off" ]] && made=1 || made=0
assert_eq "$made" "0" "설치 트리의 init 도 bar-off 를 만들지 않는다"

# 4) compat 적응 카피의 **실체**는 통제 경로에만 있고, /usr/bin 에는 그것을
#    가리키는 상대 심링크만 있다 (SPEC §45 개정). 이름을 하드코딩하지 않고
#    디렉터리를 순회한다 — shim 이 추가돼도 단언이 자동으로 따라간다.
for shim in "$COO_COMPAT_BIN"/*; do
  [[ -e $shim ]] || continue   # 빈 글롭 가드
  name=$(basename "$shim")
  [[ -x $shim ]] && ok=0 || ok=1
  assert_eq "$ok" "0" "compat $name 이 통제 경로에서 실행 가능"

  [[ -L $BIN/$name ]] && linked=0 || linked=1
  assert_eq "$linked" "0" "/usr/bin/$name 이 심링크로 노출된다"

  target=$(readlink "$BIN/$name" 2>/dev/null)
  assert_eq "$target" "../lib/cachy-omarchy/compat/bin/$name" \
    "/usr/bin/$name 이 compat 실체를 상대 경로로 가리킨다"
done
# no-op shim 2개는 내용도 단언한다 — 실수로 실제 훅이 compat 에 들어오면
# (섀도잉, D3 주의) 여기서 잡힌다. shim 파일에는 주석이 있으므로 핵심 행만 본다.
for s in omarchy-theme-set-browser omarchy-theme-set-keyboard; do
  grep -q '^exit 0$' "$COO_COMPAT_BIN/$s" && ok=0 || ok=1
  assert_eq "$ok" "0" "no-op shim 내용: $s"
done

# 5) 공식 omarchy 는 여전히 미설치.
pacman -Q omarchy >/dev/null 2>&1 && inst=1 || inst=0
assert_eq "$inst" "0" "공식 omarchy 미설치 (SPEC 61)"

exit "$ASSERT_FAILURES"
