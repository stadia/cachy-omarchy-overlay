#!/usr/bin/env bash
# init 은 잠금 화면 PAM 서비스를 업스트림 흐름 그대로 omarchy-apply-lock 에
# 위임한다. 재구현하지 않는다 — PAM 스탠자를 우리 쪽에 복사하면 업스트림이
# 그것을 바꿀 때 조용히 갈라진다.
#
# 계약:
#   - PAM 파일이 이미 있으면 apply-lock 을 부르지 않는다 (멱등, sudo 불필요).
#   - 없으면 부른다. sudo 가 필요하다는 것을 먼저 말한다.
#   - apply-lock 이 실패해도 init 은 실패하지 않는다 — 바인딩 설치가 잠금
#     설정 때문에 막히면 안 된다 (테마 시드와 같은 격하 정책).
#   - --dry-run 은 아무것도 부르지 않는다.
#
# 전부 샌드박스 HOME 에서 돌며 실제 /etc/pam.d 는 건드리지 않는다 —
# 탐지 경로는 COO_PAM_LOCK_FILE 로, 호출 대상은 PATH 스텁으로 갈아끼운다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

# 사용자 실제 HOME 을 건드릴 수 없게 구조적으로 막는다.
[[ ${HOME:-} == "${COO_TEST_SANDBOX:?}" ]] \
  || { echo "FAIL: HOME 이 샌드박스가 아니다 — 중단"; exit 1; }

# 호스트 PAM 경로. 이 테스트가 무엇을 하든 이 파일은 없거나 불변이어야 한다.
HOST_PAM=/etc/pam.d/omarchy-lock-password
host_pam_snapshot() {
  if [[ -e $HOST_PAM ]]; then
    # device+inode+size+mtime: 내용 읽기 없이 교체/truncate 를 잡는다.
    stat -c '%d %i %s %Y' "$HOST_PAM"
  else
    printf 'absent\n'
  fi
}
HOST_PAM_BEFORE=$(host_pam_snapshot)

INIT="$REPO_ROOT/overlay/bin/cachy-omarchy-init"
assert_file_exists "$INIT" "init 존재"
[[ -x $INIT ]] || { echo "FAIL: init 실행 가능"; exit 1; }

export COO_PREFIX_ROOT="$REPO_ROOT/overlay"
export COO_SRC_HYPR="$REPO_ROOT/overlay/hypr"
export COO_HYPR_DIR="$COO_TEST_SANDBOX/hypr"
mkdir -p "$COO_HYPR_DIR"
: > "$COO_HYPR_DIR/hyprland.conf"

stub_bin=$COO_TEST_SANDBOX/stub-bin
pam_dir=$COO_TEST_SANDBOX/pam
mkdir -p "$stub_bin" "$pam_dir"

marker=$COO_TEST_SANDBOX/apply-lock.called
cat >"$stub_bin/omarchy-apply-lock" <<EOF
#!/usr/bin/env bash
printf 'called\n' >>"$marker"
exit \${STUB_APPLY_LOCK_EXIT:-0}
EOF
chmod +x "$stub_bin/omarchy-apply-lock"

# 테마 시드는 이 테스트의 관심사가 아니다 — no-op 스텁으로 고정해 실제
# 사용자 테마 상태나 실행 중 셸에 의존하지 않게 한다.
printf '#!/usr/bin/env bash\nexit 0\n' >"$stub_bin/omarchy-theme-set"
chmod +x "$stub_bin/omarchy-theme-set"

reset_user_state() {
  rm -rf "$HOME/.config/cachy-omarchy" "$HOME/.local/state/omarchy"
}

run_init() {
  local pam_file=$1; shift
  reset_user_state
  PATH="$stub_bin:$PATH" COO_PAM_LOCK_FILE="$pam_file" "$INIT" "$@" 2>&1
}

# 1) PAM 파일이 이미 있으면 부르지 않는다.
: >"$marker"
present=$pam_dir/omarchy-lock-password
printf '#%%PAM-1.0\n' >"$present"
out=$(run_init "$present"); code=$?
assert_eq "$code" "0" "PAM 이 이미 있으면 init exit 0"
assert_eq "$(wc -l <"$marker")" "0" "PAM 이 이미 있으면 apply-lock 을 부르지 않는다"

# 2) 없으면 부른다.
: >"$marker"
missing=$pam_dir/absent-lock-password
rm -f "$missing"
out=$(run_init "$missing"); code=$?
assert_eq "$code" "0" "PAM 이 없어도 init exit 0"
assert_eq "$(wc -l <"$marker")" "1" "PAM 이 없으면 apply-lock 을 한 번 부른다"
assert_contains "$out" "sudo" "sudo 가 필요하다는 것을 미리 말한다"

# 3) apply-lock 실패는 init 을 죽이지 않고, 수동 복구 경로를 말한다.
: >"$marker"
out=$(STUB_APPLY_LOCK_EXIT=1 run_init "$missing"); code=$?
assert_eq "$code" "0" "apply-lock 실패해도 init exit 0"
assert_contains "$out" "omarchy-apply-lock" "실패 시 수동 실행 명령을 안내한다"
assert_file_exists "$HOME/.config/cachy-omarchy/hypr/bindings.conf" \
  "apply-lock 실패가 뒤따르는 바인딩 설치를 막지 않는다"

# 4) --dry-run 은 아무것도 부르지 않는다.
: >"$marker"
out=$(run_init "$missing" --dry-run); code=$?
assert_eq "$code" "0" "--dry-run exit 0"
assert_eq "$(wc -l <"$marker")" "0" "--dry-run 은 apply-lock 을 부르지 않는다"
# "would:" 만 보면 바인딩 설치 줄에 걸려 헛통과한다 — apply-lock 을 명시한
# would 줄인지 본다.
would_line=$(grep '^would:' <<<"$out" | grep -c 'omarchy-apply-lock')
assert_eq "$would_line" "1" "--dry-run 은 apply-lock 을 하려던 일로 출력한다"

# 5) apply-lock 이 아예 없는 트리에서도 init 은 성립한다.
#    호스트 helper 를 다시 열면 command -v 가 /usr/bin/omarchy-apply-lock 을
#    찾고, 그 헬퍼는 COO_PAM_LOCK_FILE 을 무시하고 실 /etc/pam.d 에 sudo tee
#    한다. PATH 구성 요소는 전부 샌드박스 안이어야 한다.
: >"$marker"
bare_bin=$COO_TEST_SANDBOX/bare-bin
sysbin=$COO_TEST_SANDBOX/sysbin
mkdir -p "$bare_bin"
cp "$stub_bin/omarchy-theme-set" "$bare_bin/"
# /usr/bin 과 /bin 을 PATH 에 붙이지 않는다 — Arch 에서 /bin 은 /usr/bin
# 심링크라 호스트 omarchy-* 가 다시 보인다. dirname/pgrep 등 비-헬퍼만
# 샌드박스로 심링크한다. cp -as 는 /usr/bin 의 심링크 숲을 sysbin 에 만들고,
# 호스트 omarchy-* 와 cachy-omarchy-* 는 지운다 (구 루프는 omarchy-* 만 건너뛰어
# 호스트 cachy-omarchy-* 가 PATH 에 남을 수 있었다).
cp -as /usr/bin "$sysbin"
rm -f "$sysbin"/omarchy-* "$sysbin"/*omarchy-*
reset_user_state
case5_path="$bare_bin:$sysbin"
path_ok=1
IFS=':' read -r -a case5_parts <<<"$case5_path"
for part in "${case5_parts[@]}"; do
  [[ $part == "$COO_TEST_SANDBOX"/* ]] && continue
  printf 'FAIL: case 5 PATH 구성 요소가 샌드박스 밖이다: %s\n' "$part"
  ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
  path_ok=0
done
found_apply=$(PATH="$case5_path" command -v omarchy-apply-lock 2>/dev/null || true)
if [[ -n $found_apply ]]; then
  printf 'FAIL: case 5 PATH 에서 omarchy-apply-lock 이 보인다: %s\n' "$found_apply"
  ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
  path_ok=0
else
  printf 'ok:   case 5 PATH 에서 omarchy-apply-lock 부재\n'
fi
if (( path_ok )); then
  out=$(PATH="$case5_path" COO_PAM_LOCK_FILE="$missing" "$INIT" 2>&1); code=$?
  assert_eq "$code" "0" "apply-lock 부재에도 init exit 0"
  assert_eq "$(wc -l <"$marker")" "0" "부재 시 아무것도 부르지 않는다"
  assert_contains "$out" "omarchy-apply-lock" "부재를 조용히 넘기지 않는다"
else
  printf 'note: 호스트 helper 탐색이 남아 있어 case 5 init 을 건너뛴다 (/etc/pam.d 보호)\n'
fi

# 6) 우리 쪽에서 PAM 스탠자를 재구현하지 않는다 — 소유는 업스트림이다.
#    탐지용 기본 경로 한 줄은 필요하므로 스탠자 모듈만 금지한다.
if grep -qE 'pam_unix\.so|pam_faillock\.so|pam_systemd_home\.so' "$INIT"; then x=1; else x=0; fi
assert_eq "$x" "0" "init 은 PAM 스탠자를 복사하지 않는다"

assert_eq "$(host_pam_snapshot)" "$HOST_PAM_BEFORE" \
  "호스트 $HOST_PAM 을 쓰거나 만들지 않는다"

exit "$ASSERT_FAILURES"
