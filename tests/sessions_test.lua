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

-- One place picks both what a puppet plays and, at its desk, its monitor's screen.
local screens = Mapping.new({ coder = { "build" }, matrix = { "rain" }, conversation = "auto" })
local shown = Sessions.new(100)
local function show(name, fields)
  return shown:apply(event(name, fields), { mapping = screens, harness = fake, frame = 1, now = 100 })
end
local function both(...) return table.concat({ ... }, " ") end
check("no session: the home puppet", both(Sessions.sceneFor(nil, screens)) == "home")
show("UserPromptSubmit", { text = "/rain" })
check("a Matrix command codes with rain on its monitor", both(Sessions.sceneFor(shown.all.s1, screens)) == "code matrix")
show("Stop", {})
check("at rest, its monitor keeps its screen (dark)", both(Sessions.sceneFor(shown.all.s1, screens)) == "rest matrix")
show("UserPromptSubmit", { text = "/build" })
check("a coder command shoots invaders", both(Sessions.sceneFor(shown.all.s1, screens)) == "code invaders")
show("UserPromptSubmit", { text = "/review" })
show("SubagentStart", { agentId = "a1" })
show("SubagentStart", { agentId = "a2" })
check("the main conversation's subagents play ping pong", both(Sessions.sceneFor(shown.all.s1, screens)) == "pingpong invaders")

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

-- Liveness: one look at what runs (terminals/liveness.lua), applied the same way whatever the terminal app.
-- A session whose terminal closed leaves; one with no terminal (run in the background) leaves once it rests.
local Programs = require("puppet.terminals.programs")
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
local function onStage(sid, now) return onStageOf(tabbed, sid, now) end
local function look(ps, apps) return { terminals = Programs.parse(ps), apps = apps or {} } end
tab("here", "UserPromptSubmit", { text = "/build", tty = "/dev/ttys002", app = "iTerm.app" })
tab("ghost", "UserPromptSubmit", { text = "/build" })
tab("other", "UserPromptSubmit", { text = "/build", tty = "/dev/ttys009", app = "Apple_Terminal" })
tab("ghostty", "UserPromptSubmit", { text = "/build", tty = "/dev/ttys010", app = "ghostty" })
local allOpen = "ttys002  -zsh\nttys009  -zsh\nttys010  -zsh\n??       launchd\n"
tabbed:applyLiveness(look(allOpen))
check("a working session with no terminal still plays", onStage("ghost"))
tab("ghost", "Stop", { text = "Done." })
tab("here", "Stop", { text = "Done." })
tab("other", "Stop", { text = "Done." })
tab("ghostty", "Stop", { text = "Done." })
tabbed:applyLiveness(look(allOpen))
check("a session with no terminal stays to say what it did", onStage("ghost", 100))
check("then, resting, leaves", not onStage("ghost"))
check("a resting session in its iTerm tab stays at its desk", onStage("here"))
check("so does one in Terminal.app", onStage("other"))
check("and one in Ghostty", onStage("ghostty"))
tab("ghost", "UserPromptSubmit", { text = "/build" })
check("the background session comes back when it works again", onStage("ghost"))
tabbed:applyLiveness(look("ttys002  -zsh\nttys010  -zsh\n"))
check("a session whose Terminal.app window closed leaves", not onStage("other"))
check("the others stay", onStage("here") and onStage("ghostty"))
tabbed:applyLiveness({ terminals = nil, apps = {} })
check("not knowing what runs closes nothing", onStage("here") and onStage("ghostty"))
tabbed:applyLiveness(look("??       launchd\n"))
check("with every terminal closed, each session in one leaves", not onStage("here") and not onStage("ghostty"))
tabbed:applyLiveness(look(allOpen))
check("and stays gone when another tab takes its terminal", not onStage("here"))

-- An agent that names its program (and says late that it ended): its session ends when its terminal stops
-- running that program, even though the tab stays open; in any terminal app, iTerm running or not.
local running = assert(Programs.parse("ttys004  codex\nttys004  -zsh\n??       /Users/me/.codex/bin/codex\nttys005  /opt/bin/codex\n"))
check("programs: by terminal, by name", running["/dev/ttys004"].codex and running["/dev/ttys005"].codex)
check("programs: none without a terminal", running["??"] == nil and running["/dev/??"] == nil)
check("programs: a ps that printed nothing is unknown", Programs.parse("") == nil and Programs.parse(nil) == nil)
check("programs: a ps with no terminal at all knows there are none", next(assert(Programs.parse("??  launchd\n"))) == nil)
local owl = { id = "owl", name = "Owl", program = "codex", toolKind = function() return nil end }
local quit = Sessions.new(100)
quit:apply(event("UserPromptSubmit", { session = "o1", text = "/build", tty = "/dev/ttys004", app = "ghostty" }),
  { mapping = mapping, harness = owl, frame = 1, now = 100 })
quit:apply(event("Stop", { session = "o1", text = "Done." }), { mapping = mapping, harness = owl, frame = 1, now = 100 })
quit:applyLiveness({ terminals = running, apps = {} })
check("a session whose program still runs stays", onStageOf(quit, "o1"))
quit:applyLiveness({ terminals = nil, apps = {} })
check("an unknown program list closes nothing", onStageOf(quit, "o1"))
quit:applyLiveness(look("ttys004  -zsh\n"))
check("a session whose program left its terminal leaves", not onStageOf(quit, "o1"))
quit:apply(event("UserPromptSubmit", { session = "o1", text = "/build" }), { mapping = mapping, harness = owl, frame = 1, now = 100 })
check("a resumed session (a new prompt) comes back", onStageOf(quit, "o1"))
local plain = Sessions.new(100)
plain:apply(event("UserPromptSubmit", { session = "p1", text = "/build", tty = "/dev/ttys004", app = "iTerm.app" }),
  { mapping = mapping, harness = fake, frame = 1, now = 100 })
plain:applyLiveness(look("ttys004  -zsh\n"))
check("a harness with no program is judged by its terminal only", onStageOf(plain, "p1"))

-- An agent whose sessions also run inside its own app (no terminal): such a session ends once that app quits.
local rabbit = { id = "rabbit", name = "Rabbit", apps = { Burrow = "com.example.burrow" }, toolKind = function() return nil end }
local app = Sessions.new(100)
app:apply(event("UserPromptSubmit", { session = "r1", text = "/build", app = "Burrow" }),
  { mapping = mapping, harness = rabbit, frame = 1, now = 100 })
app:apply(event("Stop", { session = "r1", text = "Done." }), { mapping = mapping, harness = rabbit, frame = 1, now = 100 })
app:apply(event("UserPromptSubmit", { session = "r2", text = "/build", tty = "/dev/ttys004", app = "iTerm.app" }),
  { mapping = mapping, harness = rabbit, frame = 1, now = 100 })
local terminal = Programs.parse("ttys004  -zsh\n")
app:applyLiveness({ terminals = terminal, apps = {} })
check("apps: an unknown app closes nothing", onStageOf(app, "r1", 200))
app:applyLiveness({ terminals = terminal, apps = { ["com.example.burrow"] = true } })
check("apps: a session in its running app waits at its desk, not away", onStageOf(app, "r1", 200))
app:applyLiveness({ terminals = terminal, apps = { ["com.example.burrow"] = false } })
check("apps: a session whose app quit leaves", not onStageOf(app, "r1", 200))
check("apps: the agent's terminal sessions stay", onStageOf(app, "r2", 200))
app:apply(event("UserPromptSubmit", { session = "r3", text = "/build", tty = "/dev/ttys004", app = "Burrow" }),
  { mapping = mapping, harness = rabbit, frame = 1, now = 200 })
app:applyLiveness({ terminals = terminal, apps = { ["com.example.burrow"] = false } })
check("apps: a session with a terminal is judged by it, even when its line names the app", onStageOf(app, "r3", 200))
app:apply(event("UserPromptSubmit", { session = "r1", text = "/build", app = "Burrow" }),
  { mapping = mapping, harness = rabbit, frame = 1, now = 300 })
check("apps: a new prompt from the app brings it back", onStageOf(app, "r1", 300))
-- A program given as a list (an agent that shows up under more than one name): any of them keeps it.
local hare = { id = "hare", name = "Hare", program = { "hare", "hare-agent" }, toolKind = function() return nil end }
local listed = Sessions.new(100)
listed:apply(event("UserPromptSubmit", { session = "h1", text = "/build", tty = "/dev/ttys004", app = "iTerm.app" }),
  { mapping = mapping, harness = hare, frame = 1, now = 100 })
listed:applyLiveness(look("ttys004  /opt/bin/hare-agent\n"))
check("a program list: any name in it keeps the session", onStageOf(listed, "h1"))
listed:applyLiveness(look("ttys004  -zsh\n"))
check("a program list: none of them running ends it", not onStageOf(listed, "h1"))

-- A plan: setPlan keeps it for the whole session, and a step that becomes done says so.
local planned = Sessions.new(100)
local planMapping = Mapping.new({ conversation = "auto" })
local function planApply(name, fields)
  return planned:apply(event(name, fields), { mapping = planMapping, harness = fake, frame = 1, now = 100 })
end
planApply("UserPromptSubmit", { text = "hello" })
local function steps(...)
  local list = {}
  for i, status in ipairs({ ... }) do list[i] = { id = tostring(i), title = "Step " .. i, status = status } end
  return { steps = list }
end
local said = planned:setPlan("s1", steps("active", "pending"))
check("setPlan: kept on the session", planned.all.s1.plan and #planned.all.s1.plan.steps == 2)
check("setPlan: a first plan says nothing", #said == 0)
said = planned:setPlan("s1", steps("done", "active"))
check("setPlan: a step done says which", said[1] and said[1].key == "s1" and said[1].text == "✓ Step 1"
  and said[1].seconds == 4)
said = planned:setPlan("s1", steps("done", "active"))
check("setPlan: the same plan again says nothing", #said == 0)
planApply("Stop", { text = "Fixed the typo." })
planApply("UserPromptSubmit", { text = "next" })
check("setPlan: the plan outlives the turn", planned.all.s1.plan ~= nil)
said = planned:setPlan("s1", nil)
check("setPlan: nil clears it", planned.all.s1.plan == nil and #said == 0)
check("setPlan: an unknown session is ignored", #planned:setPlan("nope", steps("done")) == 0)
check("setPlan: and gets no session", planned.all.nope == nil)
local quiet = Sessions.new(100)
quiet:apply(event("UserPromptSubmit", { text = "hello" }), { mapping = mapping, harness = fake, frame = 1, now = 100 })
quiet:setPlan("s1", steps("active"))
check("setPlan: an unlisted session says nothing", #quiet:setPlan("s1", steps("done")) == 0)

-- Facts: setFacts keeps them on the session.
planned:setFacts("s1", { tickets = { ["ABC-12"] = { seen = 1 } }, timeline = {} })
check("setFacts: kept on the session", planned.all.s1.facts and planned.all.s1.facts.tickets["ABC-12"] ~= nil)
planned:setFacts("s1", nil)
check("setFacts: nil clears them", planned.all.s1.facts == nil)
planned:setFacts("nope", { tickets = {}, timeline = {} })
check("setFacts: an unknown session gets none", planned.all.nope == nil)

-- Seen 5 Nov: a background subagent started in session s1; the tab went on as session s2, and the subagent's own
-- events and its stop came under s2. An agent id belongs to the session that started it: its stop closes it
-- there, so s1's puppet rests instead of coding for hours.
local moved = Sessions.new(100)
local function under(name, fields) return moved:apply(event(name, fields), { mapping = mapping, harness = fake, frame = 1, now = 100 }) end
under("UserPromptSubmit", { text = "/build" })
under("PreToolUse", { tool = "spawn", text = "Build it in the background" })
under("SubagentStart", { agentId = "bg1", agentType = "general-purpose" })
under("Stop", { text = "Started it." })
check("moved: the subagent works in s1", Sessions.sceneFor(moved.all.s1, mapping) ~= "rest")
under("UserPromptSubmit", { session = "s2", text = "something else" })
under("PreToolUse", { session = "s2", agentId = "bg1", tool = "edit" })
check("moved: the subagent's tools still count for s1", moved.all.s1.agents.bg1.hits == 1)
local said = under("SubagentStop", { session = "s2", agentId = "bg1" })
check("moved: its stop under s2 closes it in s1", moved.all.s1.agents.bg1.done == true)
check("moved: s1 rests", Sessions.sceneFor(moved.all.s1, mapping) == "rest")
check("moved: s1 says what it did", said[1] and said[1].key == "s1")
check("moved: s2 has no stray subagent", next(moved.all.s2.agents) == nil and moved.all.s2.isWorking == true)
-- Final review: the moved subagent's tools play on the puppet that started it, and leave s2's bubble alone.
local tapped = Sessions.new(100)
local function tap(name, fields) return tapped:apply(event(name, fields), { mapping = mapping, harness = fake, frame = 1, now = 100 }) end
tap("UserPromptSubmit", { text = "/build" })
tap("SubagentStart", { agentId = "bg4", agentType = "general-purpose" })
tap("Stop", { text = "Started it." })
tap("UserPromptSubmit", { session = "s2", text = "/build" })
tap("Stop", { session = "s2", text = "Answered." })
local before = tapped.all.s1.score
local bubbles = tap("PreToolUse", { session = "s2", agentId = "bg4", tool = "edit" })
check("moved: its tools tap on s1's puppet", tapped.all.s1.score == before + 1 and tapped.all.s2.score == 0)
check("moved: s2's done bubble stays", #bubbles == 0 or bubbles[1].key ~= "s2")
check("moved: an unknown agent's stop is ignored", #under("SubagentStop", { session = "s2", agentId = "nobody" }) == 0
  and moved.all.s1.agents.nobody == nil and moved.all.s2.agents.nobody == nil)
under("SubagentStart", { agentId = "bg2", agentType = "general-purpose" })
under("SessionEnd", {})
check("moved: a stop after its session ended is ignored", pcall(under, "SubagentStop", { session = "s2", agentId = "bg2" })
  and moved.all.s1 == nil and next(moved.all.s2.agents) == nil)
local seen = Sessions.new(100)
local function via(name, fields) return seen:apply(event(name, fields), { mapping = mapping, harness = fake, frame = 1, now = 100 }) end
via("UserPromptSubmit", { text = "/build" })
via("SubagentStart", { agentId = "bg3", agentType = "general-purpose" })
via("PreToolUse", { session = "s3", agentId = "bg3", tool = "edit" })
local onStage = false
for _, key in ipairs(seen:stageKeys(100)) do onStage = onStage or key == "s3" end
check("moved: a session seen only through a subagent gets no puppet", (seen.all.s3 == nil or seen.all.s3.hasPlayed ~= true) and not onStage
  and seen.all.s1.agents.bg3.hits == 1)

-- Two sessions hold one agent id (it started under each): it belongs to the one that started it last, whatever
-- order the table walks in.
for _, order in ipairs({ { "s1", "s2" }, { "s2", "s1" } }) do
  for _, last in ipairs({ "s1", "s2" }) do
    local twice = Sessions.new(100)
    local function at(name, t, fields) return twice:apply(event(name, fields), { mapping = mapping, harness = fake, frame = 1, now = t }) end
    for _, key in ipairs(order) do
      at("SubagentStart", 0, { at = key == last and 200 or 100, session = key, agentId = "dup", agentType = "general-purpose" })
    end
    at("PreToolUse", 300, { at = 300, session = "s3", agentId = "dup", tool = "edit" })
    local other = last == "s1" and "s2" or "s1"
    check("twice: started last in " .. last .. " (order " .. order[1] .. "," .. order[2] .. ") takes the tool",
      twice.all[last].agents.dup.hits == 1 and twice.all[other].agents.dup.hits == 0)
  end
end


check.done("sessions")
