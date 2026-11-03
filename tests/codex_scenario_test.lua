-- A Codex session on stage: the owl in teal plays ping pong with its subagents, then shows its reply. Frames are
-- compared with tests/snapshots/codex.txt. Run with UPDATE=1 to record them.

local root = arg[0]:match("^(.*)/tests/") or "."
local stub = dofile(root .. "/tests/support/hs_stub.lua")
stub.spoonPath = root .. "/Deskmates.spoon/"
local check = dofile(root .. "/tests/support/check.lua")

local eventsFile = os.tmpname()
local out = {}

-- Colours as single letters, so a frame reads as text; the teal palette's own letters come first.
local LETTERS = {
  ["#2BB3A3"] = "l", ["#1F8A80"] = "m", ["#5FD4C4"] = "i", ["#147A8C"] = "o", ["#7FE0D0"] = "s",
  ["#8C8C8C"] = "d", ["#1E1E1E"] = "k", ["#D0D0D0"] = "g", ["#15181E"] = ":", ["#8FD18B"] = "v",
  ["#F2F2F2"] = "w", ["#F2C14E"] = "y", ["#8A6A4F"] = "b", ["#2E6B4F"] = "t", ["#6BBF59"] = "+",
  ["#E5534B"] = "x", ["#C8FFC0"] = "M", ["#3FB950"] = "n", ["#1B5E20"] = ".",
}

local function line(text) out[#out + 1] = text end

local function write(fields)
  local file = io.open(eventsFile, "a")
  file:write(os.time() .. "|" .. fields .. "\n")
  file:close()
end

local function snapshot(P, title)
  line("== " .. title)
  for i, key in ipairs(P.stage.keys) do
    local puppet = P.stage.puppets[key]
    local at = puppet.canvas:topLeft()
    local bubble = puppet.bubble:isShowing() and puppet.bubble.elements[2] and puppet.bubble.elements[2].text or "-"
    line(string.format("  puppet %d: %s at %d,%d colour %s bubble: %s", i, key, at.x, at.y, puppet.color, (bubble:gsub("\n", " / "))))
    local grid = {}
    for y = 0, 23 do
      grid[y] = {}
      for x = 0, 47 do grid[y][x] = " " end
    end
    local texts = {}
    for _, element in ipairs(puppet.canvas.elements) do
      if element.type == "text" then
        texts[#texts + 1] = tostring(element.text)
      elseif element.fillColor and element.fillColor.hex then
        local f = element.frame
        for y = math.floor(f.y / P.pixel), math.floor((f.y + f.h) / P.pixel) - 1 do
          for x = math.floor(f.x / P.pixel), math.floor((f.x + f.w) / P.pixel) - 1 do
            if grid[y] and x >= 0 and x < 48 then grid[y][x] = LETTERS[element.fillColor.hex] or "?" end
          end
        end
      end
    end
    for y = 0, 23 do line("  |" .. table.concat(grid[y], "", 0, 47) .. "|") end
    line("  texts: " .. table.concat(texts, " / "))
  end
end

local P = dofile(stub.spoonPath .. "init.lua")
P.eventsFile = eventsFile
P.coder, P.matrix, P.pingpong, P.conversation = { "dev-skill" }, { "rain" }, { "qa" }, "auto"
P:start()
stub.advance(0.2)

local tail = "|app|iTerm.app||/dev/ttys009|codex|"
write("UserPromptSubmit|s1||||/qa check|app|iTerm.app||/dev/ttys009|codex|")
write("PreToolUse|s1||spawn_agent||list_folder" .. tail)
write("SubagentStart|s1|a1||default||app|iTerm.app||/dev/ttys009|codex|")
write("SubagentStart|s1|a2||default||app|iTerm.app||/dev/ttys009|codex|")
stub.advance(3.1)
snapshot(P, "a codex session plays ping pong")
check("the codex puppet is teal", P.stage.puppets.s1.color == "#2BB3A3")

write("SubagentStop|s1|a1||default||app|iTerm.app||/dev/ttys009|codex|")
write("SubagentStop|s1|a2||default||app|iTerm.app||/dev/ttys009|codex|")
write("Stop|s1||||Fixed the parser.|app|iTerm.app||/dev/ttys009|codex|")
stub.advance(3.1)
snapshot(P, "the codex session is done")
check("its reply shows", P.stage.puppets.s1.bubble:isShowing())
P:stop()
os.remove(eventsFile)

local result = table.concat(out, "\n") .. "\n"
local path = root .. "/tests/snapshots/codex.txt"
if os.getenv("UPDATE") then
  local file = io.open(path, "w")
  file:write(result)
  file:close()
  print("recorded " .. path)
  return
end
local file = io.open(path, "r")
local expected = file and file:read("a") or ""
if file then file:close() end
check("the owl's frames match tests/snapshots/codex.txt", result == expected)
check.done("codex scenario")
