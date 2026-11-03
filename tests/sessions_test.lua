-- The session model with a fake harness: proves the core asks the harness what tools mean and depends on
-- no real agent.

local root = arg[0]:match("^(.*)/tests/") or "."
package.path = root .. "/Deskmates.spoon/lib/?.lua;" .. root .. "/Deskmates.spoon/lib/?/init.lua;" .. package.path
local check = dofile(root .. "/tests/support/check.lua")
local Sessions = require("puppet.model.sessions")
local Mapping = require("puppet.model.mapping")

local fake = {
  id = "fake", name = "Fakebot",
  toolKind = function(tool)
    return ({ look = "reading", ask_human = "question", run_skill = "skill", spawn = "agent" })[tool]
  end,
}
local mapping = Mapping.new({ coder = { "build" }, pingpong = { "review" }, conversation = "off" })

local function event(name, fields)
  local e = { at = 100, name = name, session = "s1", agentId = "", tool = "", agentType = "", text = "",
    folder = "repo", app = "", flag = "", tty = "", harness = "fake", title = "" }
  for k, v in pairs(fields or {}) do e[k] = v end
  return e
end

local sessions = Sessions.new(100)
local function apply(name, fields) return sessions:apply(event(name, fields), { mapping = mapping, harness = fake, frame = 1, now = 100 }) end

apply("UserPromptSubmit", { text = "hello" })
check("an unlisted turn with the conversation off does not play", sessions.all.s1.isListed == false)
apply("PreToolUse", { tool = "run_skill", text = "build" })
check("the harness's skill tool starts a listed command mid-turn", sessions.all.s1.isListed and sessions.all.s1.command == "build")
check("that command codes", Sessions.sceneFor(sessions.all.s1, mapping) == "code")
apply("PreToolUse", { tool = "look" })
check("the harness's reading tool shows the lens", sessions.all.s1.readingUntil == 21)
local intents = apply("PreToolUse", { tool = "ask_human" })
check("the harness's question tool raises a hand", sessions.all.s1.mood == "asking")
check("and says so", intents[1] and intents[1].text == "I have a question for you")
intents = apply("Notification", {})
check("a notification without text names the harness", #intents == 0)
apply("PostToolUse", { tool = "ask_human" })
intents = apply("Notification", {})
check("a notification without text names the harness", intents[1] and intents[1].text == "Fakebot needs you")
intents = apply("Stop", { text = "Built it." })
check("done says the reply", intents[1] and intents[1].text == "Built it. ✓")
check("the puppet stays on stage", sessions:stageKeys(100)[1] == "s1")
check("and leaves after hours of silence", sessions:stageKeys(100 + 3 * 60 * 60)[1] == "home")

-- A message sent while a command's turn runs belongs to that work.
local busy = Sessions.new(100)
local function on(name, fields) return busy:apply(event(name, fields), { mapping = mapping, harness = fake, frame = 1, now = 100 }) end
on("UserPromptSubmit", { text = "/build" })
on("PreToolUse", { tool = "edit" })
on("UserPromptSubmit", { text = "also rename the file" })
check("a message during a running command keeps the command", busy.all.s1.command == "build")
check("and its animation", Sessions.sceneFor(busy.all.s1, mapping) == "code")
on("Stop", { text = "Built." })
on("UserPromptSubmit", { text = "thanks" })
check("once the session is idle, a message is the main conversation", busy.all.s1.command == nil)

-- Wake-up prompts while background subagents of a command still work keep it too.
on("UserPromptSubmit", { text = "/review" })
on("SubagentStart", { agentId = "a1", agentType = "lens" })
on("SubagentStart", { agentId = "a2", agentType = "lens" })
on("Stop", { text = "Both reviewers are running." })
on("UserPromptSubmit", { text = "" })
on("SubagentStop", { agentId = "a1" })
check("a prompt while subagents run keeps the command", busy.all.s1.command == "review")
check("and its subagents", #busy.all.s1.order == 2)
check("so ping pong goes on", Sessions.sceneFor(busy.all.s1, mapping) == "pingpong")
on("SubagentStop", { agentId = "a2" })
check("once every subagent is done, the main conversation codes", Sessions.sceneFor(busy.all.s1, mapping) == "code")
on("UserPromptSubmit", { text = "/review" })
check("a ping pong turn plays before its first subagent starts", Sessions.sceneFor(busy.all.s1, mapping) == "pingpong")
on("SubagentStart", { agentId = "a3", agentType = "lens" })
on("SubagentStop", { agentId = "a3" })
check("and goes back to coding when its only subagent is done", Sessions.sceneFor(busy.all.s1, mapping) == "code")
on("UserPromptSubmit", { text = "/build" })
check("a new /command always wins", busy.all.s1.command == "build" and #busy.all.s1.order == 0)

-- What the status line and card need: when the turn started, and its tool calls.
local timed = Sessions.new(100)
local function at(time, name, fields)
  fields = fields or {}
  fields.at = time
  return timed:apply(event(name, fields), { mapping = mapping, harness = fake, frame = 1, now = time })
end
at(100, "UserPromptSubmit", { text = "/review" })
at(110, "PreToolUse", { tool = "look" })
at(120, "PreToolUse", { tool = "Bash", agentId = "a1" })
check("a turn remembers when it started", timed.all.s1.turnAt == 100)
check("every tool call counts, the subagents' too", timed.all.s1.tools == 2)
check("and the last tool is kept", timed.all.s1.lastTool == "Bash")
at(130, "UserPromptSubmit", { text = "and the docs too" })
check("a message during the turn keeps its start", timed.all.s1.turnAt == 100 and timed.all.s1.tools == 2)
at(140, "Stop", {})
at(200, "UserPromptSubmit", { text = "/build" })
check("a new turn starts the clock and the count again", timed.all.s1.turnAt == 200 and timed.all.s1.tools == 0)


-- The session's title, and what each subagent is for.
local named = Sessions.new(100)
local function said(name, fields)
  return named:apply(event(name, fields), { mapping = mapping, harness = fake, frame = 1, now = 100 })
end
said("UserPromptSubmit", { text = "/review", title = "PR 12 review" })
check("the title is kept", named.all.s1.title == "PR 12 review")
said("PreToolUse", { tool = "spawn", text = "QA lens contract T-42" })
said("PreToolUse", { tool = "spawn", text = "QA lens break T-42" })
said("SubagentStart", { agentId = "a1", agentType = "general-purpose" })
said("SubagentStart", { agentId = "a2", agentType = "general-purpose", text = "Break it, from the meta file" })
check("a subagent without its own description takes the first one called", named.all.s1.agents.a1.label == "QA lens contract T-42")
check("a description sent with the start wins", named.all.s1.agents.a2.label == "Break it, from the meta file")
said("SubagentStart", { agentId = "a3", agentType = "general-purpose" })
check("with nothing queued, the agent type", named.all.s1.agents.a3.label == "general-purpose")
said("Stop", { title = "" })
check("an event without a title keeps the last one", named.all.s1.title == "PR 12 review")
said("PreToolUse", { tool = "spawn", text = "left over" })
said("UserPromptSubmit", { text = "/build" })
said("SubagentStart", { agentId = "a4", agentType = "lens" })
check("a new turn forgets descriptions queued in the last one", named.all.s1.agents.a4.label == "lens")

-- Terminal tabs: a closed tab takes its puppet away, and so does having no tab at all while resting.
local tabbed = Sessions.new(100)
local function tab(sid, name, fields)
  fields = fields or {}
  fields.session = sid
  return tabbed:apply(event(name, fields), { mapping = mapping, harness = fake, frame = 1, now = 100 })
end
local function onStageOf(model, sid, now)
  for _, key in ipairs(model:stageKeys(now or 160)) do if key == sid then return true end end
  return false
end
local function onStage(sid, now)
  for _, key in ipairs(tabbed:stageKeys(now or 160)) do if key == sid then return true end end
  return false
end
tab("here", "UserPromptSubmit", { text = "/build", tty = "/dev/ttys002", app = "iTerm.app" })
tab("ghost", "UserPromptSubmit", { text = "/build", tty = "/dev/ttys001" })
tab("other", "UserPromptSubmit", { text = "/build", tty = "/dev/ttys009", app = "Apple_Terminal" })
tabbed:closeMissing({ ["/dev/ttys002"] = { window = 1, tab = 1 } })
check("a working session with no tab still plays", onStage("ghost"))
tab("ghost", "Stop", { text = "Done." })
tab("here", "Stop", { text = "Done." })
tab("other", "Stop", { text = "Done." })
tabbed:closeMissing({ ["/dev/ttys002"] = { window = 1, tab = 1 } })
check("a session with no tab stays to say what it did", onStage("ghost", 100))
check("then, resting, leaves", not onStage("ghost"))
check("a resting session in its tab stays at its desk", onStage("here"))
check("another terminal's session is not judged by iTerm's tabs", onStage("other"))
tab("ghost", "UserPromptSubmit", { text = "/build" })
check("the tabless session comes back when it works again", onStage("ghost"))
tabbed:closeMissing({})
check("a session whose tab closed leaves", not onStage("here"))
tabbed:closeMissing({ ["/dev/ttys002"] = { window = 1, tab = 1 } })
check("and stays gone when another tab takes its terminal", not onStage("here"))

-- An agent that names its program (and says late that it ended): its session ends when its terminal stops
-- running that program, even though the tab stays open.
local Programs = require("puppet.terminals.programs")
local running = Programs.parse("ttys004  codex\nttys004  -zsh\n??       /Users/me/.codex/bin/codex\nttys005  /opt/bin/codex\n")
check("programs: by terminal, by name", running["/dev/ttys004"].codex and running["/dev/ttys005"].codex)
check("programs: none without a terminal", running["??"] == nil and running["/dev/??"] == nil)
local owl = { id = "owl", name = "Owl", program = "codex", toolKind = function() return nil end }
local quit = Sessions.new(100)
local tabs = { ["/dev/ttys004"] = { window = 1, tab = 1 } }
quit:apply(event("UserPromptSubmit", { session = "o1", text = "/build", tty = "/dev/ttys004", app = "iTerm.app" }),
  { mapping = mapping, harness = owl, frame = 1, now = 100 })
quit:apply(event("Stop", { session = "o1", text = "Done." }), { mapping = mapping, harness = owl, frame = 1, now = 100 })
quit:closeMissing(tabs, running)
check("a session whose program still runs stays", onStageOf(quit, "o1"))
check("programs: a ps that printed nothing is unknown", Programs.parse("") == nil and Programs.parse(nil) == nil)
quit:closeMissing(tabs, Programs.parse(""))
check("an unknown program list closes nothing", onStageOf(quit, "o1"))
quit:closeMissing(tabs, Programs.parse("ttys004  -zsh\n"))
check("a session whose program left its terminal leaves", not onStageOf(quit, "o1"))
quit:apply(event("UserPromptSubmit", { session = "o1", text = "/build" }), { mapping = mapping, harness = owl, frame = 1, now = 100 })
check("a resumed session (a new prompt) comes back", onStageOf(quit, "o1"))
local plain = Sessions.new(100)
plain:apply(event("UserPromptSubmit", { session = "p1", text = "/build", tty = "/dev/ttys004", app = "iTerm.app" }),
  { mapping = mapping, harness = fake, frame = 1, now = 100 })
plain:closeMissing(tabs, Programs.parse(""))
check("a harness with no program is judged by its tab only", onStageOf(plain, "p1"))

-- An agent whose sessions also run inside its own app (no terminal): such a session ends once that app quits.
local rabbit = { id = "rabbit", name = "Rabbit", apps = { Burrow = "com.example.burrow" }, toolKind = function() return nil end }
local app = Sessions.new(100)
app:apply(event("UserPromptSubmit", { session = "r1", text = "/build", app = "Burrow" }),
  { mapping = mapping, harness = rabbit, frame = 1, now = 100 })
app:apply(event("Stop", { session = "r1", text = "Done." }), { mapping = mapping, harness = rabbit, frame = 1, now = 100 })
app:apply(event("UserPromptSubmit", { session = "r2", text = "/build", tty = "/dev/ttys004", app = "iTerm.app" }),
  { mapping = mapping, harness = rabbit, frame = 1, now = 100 })
app:closeQuitApps(nil)
check("apps: an unknown app list closes nothing", onStageOf(app, "r1", 200))
app:closeQuitApps({ ["com.example.burrow"] = true })
check("apps: a session in its running app waits at its desk", onStageOf(app, "r1", 200))
app:closeQuitApps({ ["com.example.burrow"] = false })
check("apps: a session whose app quit leaves", not onStageOf(app, "r1", 200))
check("apps: the agent's terminal sessions stay", onStageOf(app, "r2", 200))
app:apply(event("UserPromptSubmit", { session = "r1", text = "/build", app = "Burrow" }),
  { mapping = mapping, harness = rabbit, frame = 1, now = 300 })
check("apps: a new prompt from the app brings it back", onStageOf(app, "r1", 300))
-- A program given as a list (an agent that shows up under more than one name): any of them keeps it.
local hare = { id = "hare", name = "Hare", program = { "hare", "hare-agent" }, toolKind = function() return nil end }
local listed = Sessions.new(100)
listed:apply(event("UserPromptSubmit", { session = "h1", text = "/build", tty = "/dev/ttys004", app = "iTerm.app" }),
  { mapping = mapping, harness = hare, frame = 1, now = 100 })
listed:closeMissing(tabs, Programs.parse("ttys004  /opt/bin/hare-agent\n"))
check("a program list: any name in it keeps the session", onStageOf(listed, "h1"))
listed:closeMissing(tabs, Programs.parse("ttys004  -zsh\n"))
check("a program list: none of them running ends it", not onStageOf(listed, "h1"))

check.done("sessions")
