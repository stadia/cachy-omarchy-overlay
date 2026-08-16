-- Milestone 3 Hyprland bindings (lua).
-- Loaded via a managed pcall(dofile) block. The helper must not hyprctl reload.
hl.unbind("SUPER + space")
hl.bind("SUPER + space", hl.dsp.exec_cmd("cachy-omarchy-launcher"))
hl.unbind("SUPER + K")
hl.bind("SUPER + K", hl.dsp.exec_cmd("cachy-omarchy-keybindings"))
