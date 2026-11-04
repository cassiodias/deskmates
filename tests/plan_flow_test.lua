-- A plan from the events file to the puppet: the Spoon marks that it runs (the hooks keep plans only then),
-- reloads a session's plan on a line with the plan flag, and says when a step is done.

local root = arg[0]:match("^(.*)/tests/") or "."
local stub = dofile(root .. "/tests/support/hs_stub.lua")
stub.spoonPath = root .. "/Deskmates.spoon/"
local check = dofile(root .. "/tests/support/check.lua")

local dir = os.tmpname()
os.remove(dir)
os.execute("mkdir -p '" .. dir .. "/plans'")
local eventsFile = dir .. "/events"
local function append(path, text, mode)
  local file = io.open(path, mode or "a")
  file:write(text)
  file:close()
end
local function read(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local text = file:read("a")
  file:close()
  return text
end
local function write(fields) append(eventsFile, os.time() .. "|" .. fields .. "\n") end
local function plan(...)
  local steps = {}
  for i, status in ipairs({ ... }) do
    steps[i] = string.format('{"id": "%d", "title": "Step %d", "status": "%s"}', i, i, status)
  end
  append(dir .. "/plans/s1.json", '{"steps": [' .. table.concat(steps, ", ") .. '], "updatedAt": ' .. os.time() .. "}", "w")
end
append(eventsFile, "")

local P = dofile(stub.spoonPath .. "init.lua")
P.eventsFile = eventsFile
P.plansDir = dir .. "/plans"
P.onFile = dir .. "/on"
P:start()
check("start marks that Deskmates runs, with Hammerspoon's process id", read(dir .. "/on") == "4242\n")

write("UserPromptSubmit|s1||||hello|app|iTerm.app||/dev/ttys001|claude|")
stub.advance(0.2)
plan("active", "pending")
write("PreToolUse|s1||TodoWrite|||app|iTerm.app|plan|/dev/ttys001|claude|")
stub.advance(0.2)
local s = P.sessions.all.s1
check("a plan line loads the session's plan", s.plan and #s.plan.steps == 2)

plan("done", "active")
write("PreToolUse|s1||TaskUpdate|||app|iTerm.app|plan|/dev/ttys001|claude|")
stub.advance(0.2)
local bubble = P.stage.puppets.s1 and P.stage.puppets.s1.bubble
local said = bubble and bubble.elements[2] and bubble.elements[2].text
check("a step done is said on the puppet", said == "✓ Step 1")

write("PreToolUse|s1||Edit|||app|iTerm.app||/dev/ttys001|claude|")
stub.advance(0.2)
check("a line without the flag keeps the plan", P.sessions.all.s1.plan and P.sessions.all.s1.plan.steps[1].status == "done")

os.remove(dir .. "/plans/s1.json")
write("PreToolUse|s1||TaskUpdate|||app|iTerm.app|plan|/dev/ttys001|claude|")
stub.advance(0.2)
check("a plan line with no file clears it", P.sessions.all.s1.plan == nil)

P:stop()
check("stop removes the marker", read(dir .. "/on") == nil)

-- A restart replays the events: the plan comes back from its file, without bubbles.
plan("done", "done")
local Q = dofile(stub.spoonPath .. "init.lua")
Q.eventsFile = eventsFile
Q.plansDir = dir .. "/plans"
Q.onFile = dir .. "/on"
Q:start()
check("a restart finds the plan again", Q.sessions.all.s1 and Q.sessions.all.s1.plan
  and Q.sessions.all.s1.plan.steps[2].status == "done")
Q:stop()

-- A first start, before any hook made the folder: the marker is still written.
local R = dofile(stub.spoonPath .. "init.lua")
R.eventsFile = eventsFile
R.plansDir = dir .. "/plans"
R.onFile = dir .. "/fresh/on"
R:start()
check("the marker's folder is made when missing", read(dir .. "/fresh/on") == "4242\n")
R:stop()

os.execute("rm -rf '" .. dir .. "'")
check.done("plan flow")
