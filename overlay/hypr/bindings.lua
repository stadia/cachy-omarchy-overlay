-- Milestone 3 Hyprland bindings (lua).
-- Loaded via a managed pcall(dofile) block. The helper must not hyprctl reload.
--
-- The description strings are a contract, not decoration: the keybindings sheet
-- displays them instead of the raw command, and upstream prioritize_entries
-- ranks rows by matching this exact English text (Keybindings=0, Launch apps=5).
hl.unbind("SUPER + space")
hl.bind("SUPER + space", hl.dsp.exec_cmd("omarchy-menu toggle"), { description = "Launch apps" })
hl.unbind("SUPER + K")
hl.bind("SUPER + K", hl.dsp.exec_cmd("omarchy-menu-keybindings"), { description = "Keybindings" })

-- Quattro shell autostart: 세션 시작 1회 발화(hyprland.start). 리로드로는
-- 재기동하지 않는다 — 복구는 수동 `omarchy-restart-shell`. 업스트림
-- omarchy shell/README.md 193–198행 모델을 따른다(SPEC §16 참조).
hl.on("hyprland.start", function()
  hl.exec_cmd("omarchy-launch-shell")
end)

-- Theme palette (M9 D5): 테마가 생성한 hyprland.lua(테두리 색/그라디언트)를
-- 있을 때만 로드한다. 관리 블록의 pcall(dofile, bindings.lua) 안에서 한 번 더
-- pcall 로 감싼다 — 테마 파일이 깨져도 사용자 설정 전체가 죽지 않는다.
-- 테마 파일 부재(시드 전/사용자 삭제)는 정상 경로이므로 조용히 지나간다.
do
  local theme_hypr = os.getenv("HOME")
    .. "/.local/state/omarchy/current/theme/hyprland.lua"
  local f = io.open(theme_hypr, "r")
  if f then
    f:close()
    pcall(dofile, theme_hypr)
  end
end

-- Omarchy toggles seam (#12): 업스트림 config/hypr/hyprland.lua 의
-- require("default.hypr.toggles") 를 그대로 부른다.
-- omarchy-hyprland-monitor-clamshell / -internal / -internal-mirror 이
-- ~/.local/state/omarchy/toggles/hypr/*.lua 를 쓰고 hyprctl reload 하는데,
-- 그것을 읽는 쪽이 없으면 아무도 안 보는 dead file 만 남는다.
--
-- 관리 블록은 pcall(dofile) 로 진입하므로 package.path 를 직접 세워야 한다.
-- package.path 에 $OMARCHY_PATH/?.lua 만 붙이면 부족하다 — 워크스페이스
-- 레이아웃 파일이 있을 때 omarchy.workspace-layouts.* 를 못 찾아 config 에러가
-- 난다(Hyprland 0.56.2 중첩 인스턴스 실측, 2026-10-19). 그래서 업스트림
-- bootstrap.lua 를 부른다: ~/.local/state/?.lua 와 ~/.config/?.lua 와
-- $OMARCHY_PATH/?.lua 를 path 에 올리고 default.hypr.* 모듈 캐시를 비워
-- 리로드마다 toggle 이 다시 실행되게 한다.
--
-- 4.0.1 (보안) 계약은 업스트림 toggles.lua 가 진다: 레거시 touchpad-disabled.lua /
-- touchscreen-disabled.lua 는 코드로 로드하지 않고(exclude), 장치 이름은
-- <kind>-disabled-name 데이터 파일에서 읽어 hl.device 로만 전달한다.
-- tests/runtime/test_toggles_seam.sh 가 이 두 가지를 고정한다.
--
-- pcall 안에서 부른다: OMARCHY_PATH 가 없는 환경(uwsm 드롭인 미적용)이나
-- 업스트림 트리가 없는 구버전 shell 패키지에서는 조용히 지나간다. toggle
-- 파일 하나가 깨져도 Hyprland 의 require 가 에러를 config 에러로 보고만 하고
-- 뒤의 toggle 은 계속 로드된다(같은 실측).
do
  local root = os.getenv("OMARCHY_PATH")
  if root and root ~= "" then
    pcall(function()
      dofile(root .. "/default/hypr/bootstrap.lua")
      require("default.hypr.toggles")
    end)
  end
end
