#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/assert.sh"

src=${COO_OMARCHY_GIT:-$REPO_ROOT/build/omarchy}
stage=$COO_TEST_SANDBOX/pkg
bash "$REPO_ROOT/packages/cachy-omarchy-shell/stage-upstream.sh" "$src" "$stage" \
  "$REPO_ROOT/overlay/defaults"

mapfile -t files < <(find "$stage" -type f -o -type l | sed "s|^$stage||" | sort)

forbidden_regex='^/(etc|boot|efi)(/|$)'
for f in "${files[@]}"; do
  if [[ $f =~ $forbidden_regex ]]; then
    printf 'FAIL: P01 forbidden path %s\n' "$f"
    ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
  fi
done
if [[ $ASSERT_FAILURES -eq 0 ]]; then
  printf 'ok:   P01 no /etc /boot /efi paths\n'
fi

# /usr/bin/omarchy-* 는 SPEC §45 노출 심링크다 (Task 1) — stage-upstream.sh
# 의 helpers 배열이 소유를 선언하는 것과 같은 이름 규칙이라 여기서도 허용한다.
allowed_regex='^/usr/share/(cachy-omarchy|licenses/cachy-omarchy-shell)/|^/usr/bin/omarchy-[a-z0-9-]+$'
for f in "${files[@]}"; do
  if [[ ! $f =~ $allowed_regex ]]; then
    printf 'FAIL: P10 unowned path %s\n' "$f"
    ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
  fi
done
if [[ $ASSERT_FAILURES -eq 0 ]]; then
  printf 'ok:   P10 all files under owned prefixes\n'
fi

pkgbuild=$REPO_ROOT/packages/cachy-omarchy-shell/PKGBUILD
# depends= 배열은 여러 줄일 수 있다 — 괄호가 닫힐 때까지 읽는다.
deps=$(sed -n '/^depends=(/,/)/p' "$pkgbuild")
# perl 은 M1 감사(docs/superpowers/plans/2026-08-16-spec10-m1.md) 시점엔 기동에
# 안 쓰인다고 봐서 금지 목록에 있었다. v0.9 클로저 스캐너 실측(task-2-input.md)
# 으로 omarchy-menu-select 의 -MEncode -MJSON::PP 키바인딩 UI 경로가 실제로
# perl 을 부른다는 것이 드러났다 — HARD 승격 대상이지 금지 대상이 아니다.
for bad in omarchy-settings limine snapper sddm plymouth omarchy-keyring; do
  if [[ $deps == *"$bad"* ]]; then
    printf 'FAIL: forbidden dependency %s in %s\n' "$bad" "$deps"
    ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
  fi
done
assert_contains "$deps" "quickshell" "depends quickshell"
assert_contains "$deps" "hyprland" "depends hyprland"
assert_contains "$deps" "inotify-tools" "depends inotify-tools (§28 실측)"
assert_contains "$deps" "libvips" "depends libvips (menu-images 썸네일, M9)"
assert_contains "$deps" "procps-ng" "depends procps-ng (pgrep/pkill, M9)"
assert_contains "$deps" "psmisc" "depends psmisc (killall, M9)"
assert_contains "$deps" "jq" "depends jq (M10 승격: clipboard/reminders/OSD)"
assert_contains "$deps" "wl-clipboard" "depends wl-clipboard (M10 clipboard watcher)"
assert_contains "$deps" "wtype" "depends wtype (M10 emoji/clipboard paste)"
assert_contains "$deps" "wireplumber" "depends wireplumber (M10 wpctl mic mute)"
assert_contains "$deps" "pipewire-pulse" "depends pipewire-pulse (M10 pactl volume)"
assert_contains "$deps" "xdg-utils" "depends xdg-utils (M10 clipboard-open launch closure)"

# M10: jq 는 hard depends 로 승격됐으므로 optdepends 에 남아 있으면 안 된다.
optdeps=$(sed -n '/^optdepends=(/,/^)/p' "$pkgbuild")
if [[ $optdeps == *"'jq:"* ]]; then
  printf 'FAIL: jq 가 optdepends 에 잔존 (M10 에서 hard depends 로 승격)\n'
  ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
fi
# AUR class 는 depends 에 들어가면 안 된다 — pacman -U 는 리포/설치된 패키지로만
# 의존을 해결하므로(bin/install-packages) 우리 패키지 자체가 설치 불가해진다.
for bad in tensaku ttfx xdg-terminal-exec dropbox-cli; do
  if [[ $deps == *"$bad"* ]]; then
    printf 'FAIL: AUR-only dependency %s in depends\n' "$bad"
    ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
  fi
done
# v0.12.1 정책 전환: 리포에 있는 메뉴/패널·하드웨어 제어 의존은 hard depends 다.
# 도달성 분류(OPT)는 그대로이고 바뀐 것은 선언 정책이다 — 큐레이팅된 데스크톱이
# 설치 직후 동작해야 한다. 승격된 것이 optdepends 에 잔존하면 안 된다.
for promoted in tmux foot brightnessctl ddcutil lsp-plugins-lv2 socat \
                bluez-utils desktop-file-utils gtk-update-icon-cache hyprpicker \
                iw mpv networkmanager pacman-contrib power-profiles-daemon usbutils; do
  assert_contains "$deps" "$promoted" "depends $promoted (v0.12.1 승격)"
  if [[ $optdeps == *"'$promoted:"* ]]; then
    printf 'FAIL: %s 가 optdepends 에 잔존 (v0.12.1 에서 hard depends 로 승격)\n' "$promoted"
    ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
  fi
done
printf 'ok:   P02-P04 unsafe deps absent (if no FAIL above)\n'

[[ $ASSERT_FAILURES -eq 0 ]]
