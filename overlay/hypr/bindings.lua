-- Milestone 3 Hyprland bindings (lua).
-- Loaded via a managed pcall(dofile) block. The helper must not hyprctl reload.
hl.unbind("SUPER + space")
hl.bind("SUPER + space", hl.dsp.exec_cmd("cachy-omarchy-launcher"))
hl.unbind("SUPER + K")
hl.bind("SUPER + K", hl.dsp.exec_cmd("cachy-omarchy-keybindings"))

-- Quattro shell autostart: 세션 시작 1회 발화(hyprland.start). 리로드로는
-- 재기동하지 않는다 — 복구는 수동 `cachy-omarchy-shell --restart`. 업스트림
-- omarchy shell/README.md 193–198행 모델을 따른다(SPEC §16 참조).
hl.on("hyprland.start", function()
  hl.exec_cmd("cachy-omarchy-shell --run")
end)