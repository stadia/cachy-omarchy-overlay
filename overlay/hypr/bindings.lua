-- Milestone 3 Hyprland bindings (lua).
-- Loaded via a managed pcall(dofile) block. The helper must not hyprctl reload.
hl.unbind("SUPER + space")
hl.bind("SUPER + space", hl.dsp.exec_cmd("cachy-omarchy-launcher"))
-- SUPER+K is reserved for Milestone 4 (cachy-omarchy-keybindings).
