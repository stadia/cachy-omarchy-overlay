-- Milestone 3 Hyprland bindings (lua).
-- Loaded via a managed pcall(dofile) block. The helper must not hyprctl reload.
--
-- The description strings are a contract, not decoration: the keybindings sheet
-- displays them instead of the raw command, and upstream prioritize_entries
-- ranks rows by matching this exact English text (Keybindings=0, Launch apps=5).
hl.unbind("SUPER + space")
hl.bind("SUPER + space", hl.dsp.exec_cmd("cachy-omarchy-launcher"), { description = "Launch apps" })
hl.unbind("SUPER + K")
hl.bind("SUPER + K", hl.dsp.exec_cmd("cachy-omarchy-keybindings"), { description = "Keybindings" })

-- Quattro shell autostart: 세션 시작 1회 발화(hyprland.start). 리로드로는
-- 재기동하지 않는다 — 복구는 수동 `cachy-omarchy-shell --restart`. 업스트림
-- omarchy shell/README.md 193–198행 모델을 따른다(SPEC §16 참조).
hl.on("hyprland.start", function()
  hl.exec_cmd("cachy-omarchy-shell --run")
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
