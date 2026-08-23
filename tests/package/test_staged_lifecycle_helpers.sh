#!/usr/bin/env bash
# v0.11.0 Session Lifecycle Parity: idle → screensaver → lock → wake 체인이
# 부르는 헬퍼의 스테이징을 고정한다.
# omarchy-cmd-missing 은 예외 표에 행조차 없던 미스테이징이었고, 이것이
# 없으면 omarchy-launch-screensaver 의 `if omarchy-cmd-missing ttfx` 가드가
# 127 로 끝난다 — bash if 에서 비영 종료는 거짓이므로 가드를 통과해 버리고,
# ttfx 가 실제로 없을 때 그 뒤 경로가 실패한다. 가드가 먼저 와야 fail-safe 다.
set -uo pipefail
REPO_ROOT="${REPO_ROOT:?}"
source "$REPO_ROOT/tests/lib/assert.sh"

src=${COO_OMARCHY_GIT:-$REPO_ROOT/build/omarchy}
[[ -d $src ]] || { echo "skip: 업스트림 클론 없음"; exit 0; }

stage=$COO_TEST_SANDBOX/pkg
bash "$REPO_ROOT/packages/cachy-omarchy-shell/stage-upstream.sh" "$src" "$stage" \
  "$REPO_ROOT/overlay/defaults"
bin="$stage/usr/share/cachy-omarchy/upstream/bin"

# Task 1: 가드 + 프로브 3종. 전부 verbatim, 새 외부 의존 0.
probes=(
  omarchy-cmd-missing
  omarchy-hw-laptop-closed
  omarchy-hw-external-monitors
  omarchy-hw-clamshell
)
for h in "${probes[@]}"; do
  assert_file_exists "$bin/$h" "lifecycle 프로브 스테이징: $h"
  [[ -x $bin/$h ]] && x=0 || x=1
  assert_eq "$x" "0" "실행 가능: $h"
  if cmp -s "$src/bin/$h" "$bin/$h"; then x=0; else x=1; fi
  assert_eq "$x" "0" "verbatim: $h 는 업스트림과 바이트 동일"
done

# Task 2: 키보드 백라이트. brightnessctl 은 이미 optdepends(OPT) 이고
# omarchy-osd 는 이미 스테이징돼 있다 — 새 의존 선언이 필요 없다.
for h in omarchy-brightness-keyboard; do
  assert_file_exists "$bin/$h" "lifecycle 스테이징: $h"
  if cmp -s "$src/bin/$h" "$bin/$h"; then x=0; else x=1; fi
  assert_eq "$x" "0" "verbatim: $h 는 업스트림과 바이트 동일"
done

# Task 5: 뚜껑 닫기. seam(overlay/hypr/bindings.lua) 이 열려 있어야 의미가
# 있다 — disable_internal() 이 toggles/hypr/*.lua 를 쓰고 hyprctl reload 한다.
for h in omarchy-hyprland-monitor-clamshell; do
  assert_file_exists "$bin/$h" "lifecycle 스테이징: $h"
  if cmp -s "$src/bin/$h" "$bin/$h"; then x=0; else x=1; fi
  assert_eq "$x" "0" "verbatim: $h 는 업스트림과 바이트 동일"
done

# 전이 의존이 전부 서 있다. 하나라도 빠지면 clamshell 은 절반만 동작한다.
for h in omarchy-hyprland-monitor-laptop omarchy-hyprland-monitor-internal \
         omarchy-hyprland-monitor-internal-mirror \
         omarchy-hyprland-monitor-external-active omarchy-hw-clamshell; do
  assert_file_exists "$bin/$h" "clamshell 전이 의존: $h"
done

# seam 이 실제로 있다 — 이 단언이 깨지면 clamshell 은 dead file 만 쓴다.
assert_contains "$(<"$REPO_ROOT/overlay/hypr/bindings.lua")" "toggles/hypr" \
  "clamshell 이 쓰는 toggles 를 읽는 seam 이 있다"

# Task 6: wake 끝단. 자체 체인 3개가 전부 서 있어야 절반 127 이 아니다.
for h in omarchy-system-wake; do
  assert_file_exists "$bin/$h" "lifecycle 스테이징: $h"
  if cmp -s "$src/bin/$h" "$bin/$h"; then x=0; else x=1; fi
  assert_eq "$x" "0" "verbatim: $h 는 업스트림과 바이트 동일"
done
for h in omarchy-brightness-display omarchy-brightness-keyboard \
         omarchy-hyprland-monitor-clamshell; do
  assert_file_exists "$bin/$h" "system-wake 자체 체인: $h"
done

# Task 7: 스크린세이버 짝. launch 만 올리면 본체가 127 이라 창이 즉시 죽는다.
for h in omarchy-screensaver omarchy-launch-screensaver; do
  assert_file_exists "$bin/$h" "lifecycle 스테이징: $h"
  if cmp -s "$src/bin/$h" "$bin/$h"; then x=0; else x=1; fi
  assert_eq "$x" "0" "verbatim: $h 는 업스트림과 바이트 동일"
done

# 터미널별 screensaver 설정. launch 가 $OMARCHY_PATH/default/... 로 참조한다.
# kitty 는 --override 인자만 쓰므로 설정 파일이 없다 — 부재가 결손이 아니다.
share=$stage/usr/share/cachy-omarchy/upstream
for f in default/alacritty/screensaver.toml default/foot/screensaver.ini \
         default/ghostty/screensaver; do
  assert_file_exists "$share/$f" "screensaver 설정 스테이징: $f"
  if cmp -s "$src/$f" "$share/$f"; then x=0; else x=1; fi
  assert_eq "$x" "0" "verbatim: $f"
done
[[ -e $share/default/kitty/screensaver ]] && x=1 || x=0
assert_eq "$x" "0" "kitty 설정은 업스트림에 없다 — 만들지 않는다"

# ttfx 가드의 fail-safe 전제. 이것이 없으면 가드가 127 로 끝나 통과해 버린다.
assert_file_exists "$bin/omarchy-cmd-missing" "ttfx 가드의 전제가 서 있다"

# 의존 선언: socat 은 extra 리포에 있어 v0.12.1 에서 hard depends 로 승격됐고,
# ttfx 는 AUR 전용이라 optdepends 로만 선언한다.
pkgbuild=$(<"$REPO_ROOT/packages/cachy-omarchy-shell/PKGBUILD")
deps=$(sed -n '/^depends=(/,/)/p' "$REPO_ROOT/packages/cachy-omarchy-shell/PKGBUILD")
assert_contains "$deps" "socat" "socat 이 depends 에 선언됐다"
assert_contains "$pkgbuild" "ttfx:" "ttfx 가 optdepends 에 선언됐다"
grep -qP "^\s*'?ttfx'?\s*$" <<<"$pkgbuild" && x=1 || x=0
assert_eq "$x" "0" "ttfx 는 depends 에 없다(AUR 전용 — pacman -U 가 해결 못 한다)"

exit "$ASSERT_FAILURES"
