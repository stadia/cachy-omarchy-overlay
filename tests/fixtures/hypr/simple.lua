-- Fixture for the Milestone 6 Hyprland `.lua` binding parser.
-- Not loaded by a live compositor -- it exists only as parser input, so `hl`
-- is never defined here. The file is still valid Lua 5.5 syntax (`luac -p`).
--
-- Every shape below is copied from the real ~/.config/hypr/hyprland.lua on the
-- reference machine (lines 289-322), because `hyprctl binds -j` reports
-- dispatcher "__lua" with an opaque numeric arg for a Lua config and therefore
-- cannot explain what any of these bindings actually do.

------------------------------------------------------------------
-- Single-level local string variables the parser must resolve.
------------------------------------------------------------------
local mainMod = "SUPER" -- Sets "Windows" key as main modifier
local terminal = "ghostty"
local fileManager = "nautilus"
local menu = "walker"

------------------------------------------------------------------
-- Plain binds: "<VAR> .. \" + <KEY>\"" with an hl.dsp.* dispatcher.
------------------------------------------------------------------
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))

-- A namespaced dispatcher with no arguments.
hl.bind(mainMod .. " + C", hl.dsp.window.close())

-- The SUPER+SPACE conflict this project has to detect: the action is behind
-- the `menu` variable, so the parser must resolve it to "walker".
hl.bind(mainMod .. " + space", hl.dsp.exec_cmd(menu))

-- A dispatcher taking a bare string argument.
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))

-- A dispatcher taking a table argument.
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))

-- A bind whose return value is captured in a local. The binding still counts.
local closeWindowBind = hl.bind(mainMod .. " + Q", hl.dsp.window.close())

------------------------------------------------------------------
-- Loop-generated bindings. Ten workspaces, twenty bindings, from four
-- source lines. A line-oriented parser will get this wrong; whatever it
-- reports must still not contradict `hyprctl binds -j`.
------------------------------------------------------------------
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

------------------------------------------------------------------
-- Mouse bindings: third argument is an options table.
------------------------------------------------------------------
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))

------------------------------------------------------------------
-- Options tables: locked / repeating, and an explicit description.
-- `description` is the Lua equivalent of `.conf`'s bindd and wins over
-- anything the parser infers.
------------------------------------------------------------------
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind(mainMod .. " + K", hl.dsp.exec_cmd("coo-keybindings"), { description = "Show keybindings" })

------------------------------------------------------------------
-- A bind whose action is an inline function, not an hl.dsp.* dispatcher.
-- The parser cannot describe this; per docs/HYPRLAND_INTEGRATION.md it must
-- still list the binding with an empty description rather than drop it.
------------------------------------------------------------------
hl.bind(mainMod .. " + F1", function()
    hl.notification.create({ text = "hello" })
end)

------------------------------------------------------------------
-- Not a binding. Must not be mistaken for one.
------------------------------------------------------------------
-- hl.bind(mainMod .. " + Z", hl.dsp.exec_cmd("commented out"))
hl.unbind(mainMod .. " + P")
