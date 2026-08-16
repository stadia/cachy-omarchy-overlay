# v0.1 RC 갭 인벤토리 (M7)

이 문서는 SPEC §61 acceptance criteria의 현재 증거를 정직하게 구분한다. `측정됨`은
이 저장소의 테스트 또는 읽기 전용 호스트 관측으로 확인한 사실, `추론됨`은 코드/정적
패키지 검사로만 뒷받침되는 사실, `미검증`은 실제 승인된 설치·Wayland 세션에서 아직
관측하지 않은 사실이다. `추론됨`과 `미검증`은 RC 완료 판정이 아니다.

| §61 기준 | 상태 | 현재 증거 / 다음 갭 |
| --- | --- | --- |
| CachyOS에서 실행 | 미검증 | 호스트는 CachyOS 계열로 관측했지만 실제 패키지 설치·세션 실행은 하지 않았다. `docs/RUNTIME_STARTUP.md` §9.4 참조. |
| Omarchy OS 미설치 | 측정됨 | M6 종료 관측에서 `pacman -Q omarchy omarchy-settings`가 둘 다 없었다. M7 doctor는 두 package를 각각 read-only query하며, `tests/runtime/test_doctor.sh`의 controlled pacman fixture가 두 query와 present=FAIL을 검증한다. |
| 공식 `omarchy` 불필요 | 추론됨 | 두 PKGBUILD dependency와 M5/M6 audit에 공식 패키지가 없다. 실제 의존성 해석은 clean build에서 재확인한다. |
| 공식 `omarchy-settings` 불필요 | 추론됨 | 위와 동일. `packages/*/PKGBUILD`, `docs/PACKAGE_AUDIT.md` 참조. |
| Quickshell 사용 | 추론됨 | `cachy-omarchy-shell --run`이 `quickshell -n -p`를 실행한다. live process/IPC는 미검증이다. |
| upstream Quattro source 재사용 | 측정됨 | shell PKGBUILD/staging이 pin된 upstream `shell/`만 패키징한다. `docs/COMMAND_AUDIT.md` 참조. |
| upstream commit pin | 측정됨 | `upstream.lock`과 shell PKGBUILD `_commit` 정적 검사가 있다. |
| shell package build 성공 | 추론됨 | M6 fake-tool pipeline과 일반 `makepkg --nodeps` 경로는 검증됐지만 clean chroot RC build는 미완료다. |
| forbidden system path 미소유 | 측정됨 | M6 archive audit 및 `tests/package/test_forbidden.sh`가 금지 경로를 검사한다. |
| long-running shell user start | 미검증 | `graphical-session.target`이 inactive였고 enable/start하지 않았다. `RUNTIME_STARTUP.md` §9.4. |
| IPC 동작 | 미검증 | wrapper의 timeout/error path는 시험했지만 live Quickshell target으로 ping하지 않았다. |
| SUPER+SPACE launcher | 미검증 | binding/launcher 정적·추출 트리 검증만 했다. live key injection은 opt-in이다. |
| 일반 앱 launch | 미검증 | R runtime smoke가 환경에 따라 skip하며 실제 세션 입력은 승인 전 실행하지 않았다. |
| SUPER+K keybinding UI | 미검증 | wrapper/static 검증만 했고 live UI 호출은 미관측이다. |
| 기존 Hyprland config 보존 | 추론됨 | `cachy-omarchy-bindings`는 관리 source block만 추가하도록 시험했으나 실제 사용자 설정에는 실행하지 않았다. |
| 기존 Waybar 보존 | 미검증 | init는 Omarchy bar-off 토글만 만들며 기존 Waybar와 공존을 실측하지 않았다. `RUNTIME_STARTUP.md` §9.3. |
| 기존 notification daemon 보존 | 미검증 | `disabledPlugins`가 `omarchy.notifications`를 끄지만 dunst/mako 등과 중복·충돌을 실측하지 않았다. |
| 기존 lock setup 보존 | 미검증 | `disabledPlugins`가 `omarchy.lock`을 끄지만 hyprlock 등과 상호작용을 실측하지 않았다. |
| newer upstream rebuild 자동화 | 측정됨 | M6 U01–U08 fake git/makepkg/bsdtar 경로가 candidate 검증 후 metadata 발행을 검사한다. `tests/package/test_update_pipeline.sh`. |
| failed update 미설치 | 측정됨 | U05–U08은 pacman 호출 없이 원래 lock/PKGBUILD를 보존한다. |
| prior working package rollback | 측정됨 | U09–U10은 prior pair 보존 및 corrupt rollback fail-closed를 fake pacman으로 검사한다. |

## M7 doctor와 연결

`overlay/bin/cachy-omarchy-doctor`는 설치 또는 추출 트리에 대해 읽기 전용으로 다음을
보고한다: Arch-family/Hyprland/Quickshell 관측 가능성, package version, `OMARCHY_PATH`,
`shell.qml`, service, wrapper/menu/binding/keybinding reachability, process/IPC 관측
가능성이다. 다음은 특히 숨기지 않는다.

- `omarchy`와 `omarchy-settings`는 각각 read-only `pacman -Q`로 확인한다. 하나라도
  존재하면 **FAIL**, pacman query 자체를 할 수 없으면 **WARN**이며 doctor는 설치/제거하지
  않는다.
- `install-pending.manifest`는 **FAIL**이다. doctor는 recovery·install·reload를 시도하지
  않으며 operator recovery가 필요하다고만 보고한다.
- validated manifest와 immutable artifact checksum이 맞지 않으면 **FAIL**이다.
- `~/.config/cachy-omarchy/shell.json`은 init가 만드는 참조용 inert copy이고, 실제 shell은
  `~/.config/omarchy/shell.json`을 읽는다. 전자가 있으면 **WARN**이고 후자는 user override
  **WARN**이다. 자동 경로 bridge는 만들지 않는다.
- `graphical-session.target`의 자동 기동은 unit 의도만으로 증명되지 않아 **WARN**이다.

## 릴리스 전 남은 순서

1. 단일 정본을 유지한 clean chroot/container build와 archive audit을 실제로 재현한다.
   `bin/build-packages --clean`은 임시 package context에 `clean-omarchy.tar`와
   `clean-overlay*.tar`만 생성해 `makechrootpkg -r "$COO_CLEAN_CHROOT_DIR" -- --nodeps`로
   호출한다. tracked `packages/` 아래에는 overlay 사본을 만들지 않으며, source tar는
   종료 시 삭제된다. 사용 전 prepared chroot root와 `build/omarchy` pinned tree가 필요하다.
   현재 호스트에서는 `makechrootpkg`, `archbuild`, `devtools`가 PATH에 없고
   `pacman -Q devtools`도 package not found를 반환했다. sudo/host package 변경 없이
   실제 chroot를 만들 수 없어 fake makechrootpkg transport+archive audit만 측정됐다.
2. 승인된 격리 Wayland 세션에서 shell start, IPC, launcher, app/keybinding UI와 기존
   Waybar/notification/lock daemon 공존을 관측한다.
3. 실제 `pacman -U`는 별도 사용자 승인 후 격리 환경에서만 upgrade/rollback smoke로
   수행한다. 그 전에는 M6 fake lane을 release safety evidence로 유지한다.
4. 위 관측 결과로 이 표의 `추론됨`/`미검증`만 `측정됨`으로 변경한다.
