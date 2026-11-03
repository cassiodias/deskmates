-- The whole Spoon, with iTerm not running: sessions in other terminals leave when their terminal closes or
-- their agent quits, and a background session leaves once it rests. Every few seconds the Spoon takes one look
-- at what runs (ps, the agents' apps, iTerm's tabs when it runs) and applies it to every session alike.

local root = arg[0]:match("^(.*)/tests/") or "."
local stub = dofile(root .. "/tests/support/hs_stub.lua")
stub.spoonPath = root .. "/Deskmates.spoon/"
local check = dofile(root .. "/tests/support/check.lua")

local eventsFile = os.tmpname()
local function write(fields)
  local file = assert(io.open(eventsFile, "a"))
  file:write(os.time() .. "|" .. fields .. "\n")
  file:close()
end

local P = dofile(stub.spoonPath .. "init.lua")
P.eventsFile = eventsFile
P:start()
local function onStage(key) return P.stage.puppets[key] ~= nil and P.stage.puppets[key].canvas:isShowing() end

stub.itermRunning = false
stub.ps = "ttys004  -zsh\nttys004  codex\nttys005  -zsh\nttys005  cursor-agent\nttys006  -zsh\nttys006  claude\n"
write("UserPromptSubmit|owl||||/build|my-app|ghostty||/dev/ttys004|codex|")
write("UserPromptSubmit|rabbit||||/build|my-app|Apple_Terminal||/dev/ttys005|cursor|")
write("UserPromptSubmit|puppet||||/build|my-app|ghostty||/dev/ttys006|claude|")
write("UserPromptSubmit|bg||||/build|my-app|||||claude|")
stub.advance(3.1)
check("all four play", onStage("owl") and onStage("rabbit") and onStage("puppet") and onStage("bg"))
for _, key in ipairs({ "owl", "rabbit", "puppet", "bg" }) do
  write("Stop|" .. key .. "||||Done.|my-app||||" .. (key == "owl" and "codex" or key == "rabbit" and "cursor" or "claude") .. "|")
end
stub.advance(3.1)
check("each says what it did", onStage("owl") and onStage("bg"))

stub.advance(30)
check("a background session leaves once it rests, iTerm or not", not onStage("bg"))
check("sessions in live terminals stay at their desks", onStage("owl") and onStage("rabbit") and onStage("puppet"))

-- Codex quits in Ghostty; the tab stays open.
stub.ps = "ttys004  -zsh\nttys005  -zsh\nttys005  cursor-agent\nttys006  -zsh\nttys006  claude\n"
stub.advance(3.1)
check("the owl leaves a few seconds after Codex quits in Ghostty", not onStage("owl"))
check("the others stay", onStage("rabbit") and onStage("puppet"))

-- Cursor's agent quits in Terminal.app; Claude's Ghostty window closes (its terminal runs nothing any more).
stub.ps = "ttys005  -zsh\n??       launchd\n"
stub.advance(3.1)
check("the rabbit leaves when cursor-agent quits in Terminal.app", not onStage("rabbit"))
check("the puppet leaves when its Ghostty window closes", not onStage("puppet"))

-- ps failing says nothing about anyone: a new session stays.
stub.ps = nil
write("UserPromptSubmit|later||||/build|my-app|ghostty||/dev/ttys007|claude|")
stub.advance(3.1)
check("when ps fails, nothing is closed", onStage("later"))

-- The look itself: iTerm's tabs only while iTerm runs; the agents' apps by bundle id.
local Liveness = require("puppet.terminals.liveness")
local harnesses = require("puppet.harnesses")
stub.ps, stub.itermRunning, stub.tabs = "ttys004  -zsh\n", false, ""
local look = Liveness.look(harnesses.all, P.iterm)
check("the look: no iTerm, no tabs", look.tabs == nil)
check("the look: terminals from ps", assert(look.terminals)["/dev/ttys004"]["-zsh"] == true)
check("the look: Cursor's app, running", look.apps["com.todesktop.230313mzl4w4u92"] == true)
stub.itermRunning, stub.tabs = true, "/dev/ttys004=1/2;"
look = Liveness.look(harnesses.all, P.iterm)
check("the look: iTerm's tabs while it runs", assert(look.tabs)["/dev/ttys004"].tab == 2)

P:stop()
os.remove(eventsFile)
check.done("liveness")
