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

-- Omarchy toggles seam (v0.11): 업스트림 config/hypr/hyprland.lua 의
-- require("default.hypr.toggles") 가 하던 일을 우리 관리 블록 안에서 한다.
-- omarchy-hyprland-monitor-clamshell / -internal / -internal-mirror 이
-- ~/.local/state/omarchy/toggles/hypr/*.lua 를 쓰고 hyprctl reload 하는데,
-- 그것을 읽는 쪽이 없으면 아무도 안 보는 dead file 만 남는다.
-- 업스트림의 require 체인(default.hypr.paths / require_all)은 끌어오지 않는다
-- — 관리 블록은 pcall(dofile) 로 진입하므로 그 package.path 루트가 성립하지
-- 않는다. dofile 은 모듈 캐시가 없어 업스트림 { reload = true } 의 의미가
-- 그대로 따라온다. 디렉터리 부재는 정상 경로다.
do
  local dir = os.getenv("HOME") .. "/.local/state/omarchy/toggles/hypr"
  local quoted = "'" .. dir:gsub("'", "'\\''") .. "'"
  -- -print0 + NUL 분리: 줄 단위로 읽으면 파일명에 든 개행에서 경로가 잘려
  -- 그 toggle 이 조용히 로드되지 않는다. 정렬은 셸 `sort` 대신 table.sort 로
  -- 옮긴다 — NUL 스트림을 파이프로 한 번 더 넘기지 않기 위해서다.
  local pipe = io.popen(
    "find " .. quoted .. " -maxdepth 1 -type f -name '*.lua' -print0 2>/dev/null"
  )
  if pipe then
    local blob = pipe:read("*a") or ""
    pipe:close()

    -- 평문 find 로 자른다. Lua 패턴의 %z 는 5.1 에만 있고 5.2+ 에서 빠졌는데,
    -- Hyprland 가 임베드한 버전을 전제하지 않기 위해 패턴을 쓰지 않는다.
    local paths, start = {}, 1
    while true do
      local stop = blob:find("\0", start, true)
      if not stop then break end
      if stop > start then paths[#paths + 1] = blob:sub(start, stop - 1) end
      start = stop + 1
    end
    table.sort(paths)

    for _, path in ipairs(paths) do
      -- toggle 파일 하나가 깨져도 사용자 설정 전체가 죽지 않는다(SPEC §5.1).
      pcall(dofile, path)
    end
  end
end
