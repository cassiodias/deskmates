-- Drives the whole Spoon through every scene by writing events to its events file, and compares what the
-- puppets draw, frame by frame, with tests/snapshots/scenario.txt. Run with UPDATE=1 to record new snapshots.

local root = arg[0]:match("^(.*)/tests/") or "."
local stub = dofile(root .. "/tests/support/hs_stub.lua")
stub.spoonPath = root .. "/ClaudePuppet.spoon/"

local eventsFile = os.tmpname()
local out = {}

-- Colours as single letters, so a frame reads as text.
local LETTERS = {
  ["#D97757"] = "c", ["#5B8DEF"] = "u", ["#A06CD5"] = "p", ["#4FB286"] = "e", ["#E0A43B"] = "a",
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

local function draw(puppet, pixel)
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
      for y = math.floor(f.y / pixel), math.floor((f.y + f.h) / pixel) - 1 do
        for x = math.floor(f.x / pixel), math.floor((f.x + f.w) / pixel) - 1 do
          if grid[y] and x >= 0 and x < 48 then grid[y][x] = LETTERS[element.fillColor.hex] or "?" end
        end
      end
    end
  end
  for y = 0, 23 do line("  |" .. table.concat(grid[y], "", 0, 47) .. "|") end
  line("  texts: " .. table.concat(texts, " / "))
end

-- Writes down every puppet on stage: where it sits, its colour, its bubble and its drawing.
local function snapshot(P, title)
  line("== " .. title)
  for i, key in ipairs(P.stage.keys) do
    local puppet = P.stage.puppets[key]
    local at = puppet.canvas:topLeft()
    local bubble = puppet.bubble:isShowing() and puppet.bubble.elements[2] and puppet.bubble.elements[2].text or "-"
    bubble = bubble:gsub("\n", " / ")
    line(string.format("  puppet %d: %s at %d,%d colour %s bubble: %s", i, key, at.x, at.y, puppet.color, bubble))
    draw(puppet, P.pixel)
  end
end

-- The mouse comes to rest on a puppet, or leaves it; a missed exit is a move without the event.
local function hover(P, key)
  local f = P.stage.puppets[key].canvas:frame()
  stub.mouse = { x = f.x + f.w / 2, y = f.y + f.h / 2 }
  P.stage.puppets[key].canvas.onMouse(nil, "mouseEnter")
end

local function leave(P, key, isMissed)
  stub.mouse = { x = 0, y = 0 }
  if not isMissed then P.stage.puppets[key].canvas.onMouse(nil, "mouseExit") end
end

local function menu()
  line("== menu")
  for _, item in ipairs(stub.menu()) do line("  " .. (item.checked and "[x] " or "    ") .. item.title) end
end

local function load()
  for name in pairs(package.loaded) do
    if name:match("^puppet%.") then package.loaded[name] = nil end
  end
  local P = dofile(stub.spoonPath .. "init.lua")
  P.eventsFile = eventsFile
  P.coder, P.matrix, P.pingpong, P.conversation = { "dev-skill" }, { "rain" }, { "qa" }, "auto"
  return P
end

local P = load()
P:start()
stub.advance(0.2)
snapshot(P, "nothing yet: the home puppet")

write("UserPromptSubmit|tab1||||/dev-skill CON-1|app||iTerm.app||/dev/ttys001")
stub.advance(0.2)
snapshot(P, "tab1 thinks")

write("PreToolUse|tab1||Edit|||app|iTerm.app||/dev/ttys001")
stub.advance(0.3)
snapshot(P, "tab1 codes, a shot flies")
stub.advance(0.5)
snapshot(P, "tab1 codes, the invader explodes")

write("PreToolUse|tab1||Read|||app|iTerm.app||/dev/ttys001")
stub.advance(0.3)
snapshot(P, "tab1 reads")

write("PreToolUse|tab1||Bash|||app|iTerm.app|test|/dev/ttys001")
stub.advance(0.3)
snapshot(P, "tab1 runs tests")
write("PostToolUseFailure|tab1||Bash|||app|iTerm.app|test|/dev/ttys001")
stub.advance(0.3)
snapshot(P, "tab1 tests failed")

write("PermissionRequest|tab1||Bash|||app|iTerm.app||/dev/ttys001")
stub.advance(0.3)
snapshot(P, "tab1 asks permission")
write("PostToolUse|tab1||Bash|||app|iTerm.app||/dev/ttys001")
write("PreToolUse|tab1||AskUserQuestion|||app|iTerm.app||/dev/ttys001")
stub.advance(0.3)
snapshot(P, "tab1 has a question")

stub.tabs, stub.itermRunning = "/dev/ttys001=1/1;/dev/ttys002=1/2;", true
write("UserPromptSubmit|tab2||||/qa CON-1|app||iTerm.app||/dev/ttys002")
write("PreToolUse|tab2||Agent||Check the contract|app|iTerm.app||/dev/ttys002|claude|Shop-api PR 12 review")
write("SubagentStart|tab2|a1||contract||app|iTerm.app||/dev/ttys002")
write("SubagentStart|tab2|a2||break|Try to break it|app|iTerm.app||/dev/ttys002")
write("PreToolUse|tab2|a1|Read|||app|iTerm.app||/dev/ttys002")
write("PreToolUse|tab2|a2|Bash|||app|iTerm.app||/dev/ttys002")
stub.advance(3.1)
snapshot(P, "tab2 plays ping pong, tabs known")

write("UserPromptSubmit|tab3||||/rain|other||ghostty||")
write("PreToolUse|tab3||Edit|||other|ghostty||")
stub.advance(0.5)
snapshot(P, "tab3 watches the Matrix rain")

write("PostToolUse|tab1||AskUserQuestion|||app|iTerm.app||/dev/ttys001")
write("Stop|tab1||||Fixed the parser and added two tests.|app|iTerm.app||/dev/ttys001")
stub.advance(0.3)
snapshot(P, "tab1 done")

hover(P, "tab1")
stub.advance(0.2)
snapshot(P, "the mouse rests on tab1: its card covers the reply")
leave(P, "tab1")
stub.advance(0.2)
snapshot(P, "the mouse leaves tab1: the reply comes back")

write("SubagentStop|tab2|a1||contract||app|iTerm.app||/dev/ttys002")
stub.advance(0.3)
snapshot(P, "a lens is done")

hover(P, "tab2")
stub.advance(0.2)
snapshot(P, "the mouse rests on tab2: its subagents in the card")
leave(P, "tab2", true)
stub.advance(0.2)
snapshot(P, "the mouse left tab2 without a mouseExit: the card goes anyway")

stub.advance(40)
snapshot(P, "a while later: tab1 dozes at its desk")

P:focus("tab2")
line("== click on tab2 selects " .. tostring(stub.selected))
P:focus("tab3")
line("== click on tab3 brings forward " .. tostring(stub.focused))
menu()

write("SessionEnd|tab3||||||ghostty||")
stub.tabs = "/dev/ttys002=1/1;"
stub.advance(3.1)
snapshot(P, "tab3 ends and tab1's iTerm tab closes")

P:stop()
local again = load()
again:start()
stub.advance(0.2)
snapshot(again, "after a restart, replayed from the events file: tab1, whose tab closed, stays gone")

-- Hiding the puppets lasts across a restart, and the menu bar icon dims meanwhile.
local function iconLook()
  stub.styled = {}
  return stub.icon.text .. (stub.icon.style and " dimmed" or "")
end
local function shownPuppets(P)
  local n = 0
  for _, key in ipairs(P.stage.keys) do if P.stage.puppets[key].canvas:isShowing() then n = n + 1 end end
  return n
end
again:toggle()
line("== hidden: " .. shownPuppets(again) .. " puppets showing, icon " .. iconLook())
again:stop()
local hidden = load()
hidden:start()
stub.advance(0.2)
line("== hidden after a restart: " .. shownPuppets(hidden) .. " puppets showing, icon " .. iconLook())
hidden:toggle()
stub.advance(0.2)
line("== shown again: " .. shownPuppets(hidden) .. " puppets showing, icon " .. iconLook())

os.remove(eventsFile)

local result = table.concat(out, "\n") .. "\n"
local path = root .. "/tests/snapshots/scenario.txt"
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
if result == expected then
  print("scenario: ok")
  return
end
local got, want = {}, {}
for l in result:gmatch("[^\n]*\n") do got[#got + 1] = l end
for l in expected:gmatch("[^\n]*\n") do want[#want + 1] = l end
for i = 1, math.max(#got, #want) do
  if got[i] ~= want[i] then
    print(string.format("scenario: differs at line %d\n  want: %s  got:  %s", i, want[i] or "(nothing)\n", got[i] or "(nothing)\n"))
    break
  end
end
os.exit(1)
