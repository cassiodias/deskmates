-- The state of every agent session, changed one event at a time. It knows nothing of Hammerspoon or of a
-- particular agent: the session's harness says what its tools mean, and bubbles come back as intents
-- ({ key, text, seconds }; no text hides the bubble) for the caller to show.

local config = require("puppet.config")

local Sessions = {}
Sessions.__index = Sessions

local QUESTION_TEXT, PLAN_TEXT = "I have a question for you", "Plan ready for you"

function Sessions.new(now)
  return setmetatable({ all = {}, joined = 0, lastEventAt = now }, Sessions)
end

local function liveAgents(s)
  local live = 0
  for _, id in ipairs(s.order) do
    if not s.agents[id].done then live = live + 1 end
  end
  return live
end

-- The session that started subagent `agentId`: the event's own session `sid` when it did, else the one that did
-- (a background subagent outlives its session's id: its events and its stop come under the next one); nil for none.
-- Should two sessions hold the id, the one that started it last has it (then the smaller key), so the answer never
-- depends on the order the table is walked in.
local function ownerOf(all, sid, agentId)
  if agentId == "" then return nil end
  if all[sid] and all[sid].agents[agentId] then return sid end
  local owner, startedAt
  for key, s in pairs(all) do
    local agent = s.agents[agentId]
    if agent then
      local at = agent.at or 0
      if not owner or at > startedAt or (at == startedAt and key < owner) then owner, startedAt = key, at end
    end
  end
  return owner
end

-- The events of a subagent that go to the session that started it: its tools, its stop, and what it asks of you
-- (an event with no agent id stays where it came).
local ROUTED = {
  PreToolUse = true, PostToolUse = true, PostToolUseFailure = true, SubagentStop = true,
  PermissionRequest = true, Notification = true,
}

local function isAtRest(s)
  return not s.isWorking and s.mood == nil and liveAgents(s) == 0
end

-- A session playing now gets a puppet, which it keeps until it leaves the stage.
local function markPlayed(s)
  if s.isListed and (s.isWorking or s.mood ~= nil or liveAgents(s) > 0) then s.hasPlayed = true end
end

-- What a puppet shows now, in the two words render/scenes takes: the scene ("home" with no session; "code",
-- "rest" or "pingpong") and, at the desk, the monitor's screen ("matrix" or "invaders"). The menu's choice for the
-- turn's command (model/mapping.lua: "coder", "matrix", "pingpong", "auto" or "off") decides both, here only.
function Sessions.sceneFor(s, mapping)
  if not s then return "home" end
  local choice = mapping:choiceFor(s.command)
  local screen = choice == "matrix" and "matrix" or "invaders"
  local live = liveAgents(s)
  if not s.isListed then return "rest", screen end
  if s.mood == "asking" or s.mood == "permission" then return "code", screen end
  if not (s.isWorking or live > 0) then return "rest", screen end
  -- Once every subagent the turn started is done, the main conversation carries on at the laptop: no rally
  -- between players who have left the table.
  if choice == "pingpong" and (#s.order == 0 or live > 0) then return "pingpong", screen end
  if choice == "auto" and #s.order >= 2 and live > 0 then return "pingpong", screen end
  return "code", screen
end

-- The sessions with a puppet, oldest first: one that has played keeps it until it ends, it is closed or away
-- and resting (applyLiveness), or it has been silent for hours. With none, the home puppet.
function Sessions:stageKeys(now)
  local keys = {}
  for sid, s in pairs(self.all) do
    -- A session away (no terminal) first says what it did, then leaves.
    local isResting = isAtRest(s) and now - s.seenAt >= config.DONE_SECONDS
    local isGone = s.isClosed or (s.isAway and isResting) or now - s.seenAt >= config.STALE_SECONDS
    if s.hasPlayed and not isGone then keys[#keys + 1] = sid end
  end
  table.sort(keys, function(a, b) return self.all[a].joinedAt < self.all[b].joinedAt end)
  if #keys == 0 then keys = { "home" } end
  return keys
end

-- After the mapping changed: each session plays if its current turn's command now does.
function Sessions:remap(mapping)
  for _, s in pairs(self.all) do
    s.isListed = mapping:choiceFor(s.command) ~= "off"
    markPlayed(s)
  end
end

-- Whether a terminal's programs include the harness's program: one name, or any of a list.
local function runs(programs, program)
  if type(program) == "string" then return programs[program] == true end
  for _, name in ipairs(program) do
    if programs[name] then return true end
  end
  return false
end

-- Applies one look at what runs (terminals/liveness.lua): live.terminals ({ [tty] = { [program] = true } }, nil
-- when unknown) and live.apps ({ [bundle id] = running? }). The same for every terminal app:
--   closed: its terminal is gone (nothing runs in its tty: the tab or window closed), its terminal no longer
--     runs the harness's program, or, having no terminal, the app it runs inside (harness.apps) quit. It leaves
--     at once, and comes back with its next prompt.
--   away: it has no terminal and no app to watch (run in the background). It leaves once it rests, after saying
--     what it did, and comes back when it works again.
function Sessions:applyLiveness(live)
  for _, s in pairs(self.all) do
    local programs = s.tty and live.terminals and live.terminals[s.tty]
    local bundle = s.apps and s.app and s.apps[s.app]
    if s.tty and live.terminals and not programs then s.isClosed = true end
    if programs and s.program and not runs(programs, s.program) then s.isClosed = true end
    if bundle and not s.tty and live.apps and live.apps[bundle] == false then s.isClosed = true end
    s.isAway = not s.tty and not bundle
  end
end

-- Ends the turn's show once the main thread and every subagent are done, saying what the agent did.
local function finish(intents, sid, s)
  if s.isListed and not s.isWorking and liveAgents(s) == 0 then
    intents[#intents + 1] = { key = sid, text = (s.summary ~= "" and s.summary or "Done") .. " ✓",
      seconds = config.DONE_SECONDS }
  end
end

-- Keeps session `sid`'s facts (model/facts.lua's shape, or nil), for the whole session. An unknown session is
-- left alone.
function Sessions:setFacts(sid, facts)
  local s = self.all[sid]
  if s then s.facts = facts end
end

-- Keeps session `sid`'s plan (model/plans.lua's shape, or nil), for the whole session. A step that became done
-- since the last plan is said for a moment, as intents like apply's. An unknown session is left alone.
function Sessions:setPlan(sid, plan)
  local s = self.all[sid]
  if not s then return {} end
  local was = {}
  for _, step in ipairs(s.plan and s.plan.steps or {}) do was[step.id] = step.status end
  local first = s.plan == nil
  s.plan = plan
  if first or not plan or not s.isListed then return {} end
  for _, step in ipairs(plan.steps) do
    if step.status == "done" and was[step.id] ~= "done" then
      return { { key = sid, text = "✓ " .. step.title, seconds = config.STEP_DONE_SECONDS } }
    end
  end
  return {}
end

-- Applies one event. ctx: mapping, harness (the event's), frame, replayFrom (skip older events).
function Sessions:apply(e, ctx)
  local intents = {}
  local sid, harness, mapping = e.session, ctx.harness, ctx.mapping
  -- A subagent's tools, its stop and its prompts belong to the session that started it, whichever id they come
  -- under: its puppet taps while the subagent works, asks when it asks and rests when it stops; the session they
  -- came under is left alone.
  if ROUTED[e.name] then sid = ownerOf(self.all, sid, e.agentId) or sid end
  local at = e.at or ctx.now
  if ctx.replayFrom and at < ctx.replayFrom then return intents end
  if e.name == "SessionEnd" then
    self.all[sid] = nil
    return intents
  end
  local s = self.all[sid]
  if not s then
    self.joined = self.joined + 1
    s = {
      agents = {}, order = {}, queued = {}, score = 0, tools = 0, isWorking = false, readingUntil = 0, summary = "",
      tappedAt = -100,
      joinedAt = self.joined, folder = "", tag = "", turnAt = at,
      -- A session first seen mid-turn has no prompt to judge by: it plays as the main conversation would.
      isListed = mapping.conversation ~= "off",
    }
    self.all[sid] = s
  end
  self.lastEventAt = at
  s.seenAt = at
  s.harness = harness.id
  s.program = harness.program
  s.apps = harness.apps
  if e.folder ~= "" then s.folder = e.folder end
  if e.app ~= "" then s.app = e.app end
  if e.tty:match("^/dev/ttys%d+$") then s.tty = e.tty end
  if s.tag == "" then s.tag = s.folder end
  -- One puppet per terminal: a session whose own main thread works in it (a prompt, a tool) closes the others there
  -- that rest, as a closed tab would (a tab can go on in another session: Claude Code's daemon forks one), and
  -- comes back itself if it was closed (a background task ended); applyLiveness closes it again if its tab is gone.
  local isOwnWork = sid == e.session and e.agentId == "" and (e.name == "UserPromptSubmit" or e.name == "PreToolUse")
  if isOwnWork then s.isClosed = false end
  if isOwnWork and s.tty then
    for key, other in pairs(self.all) do
      if key ~= sid and other.tty == s.tty and isAtRest(other) then other.isClosed = true end
    end
  end
  if e.title and e.title ~= "" then s.title = e.title end
  local kind = harness.toolKind(e.tool)
  local function say(text, seconds) intents[#intents + 1] = { key = sid, text = text, seconds = seconds } end

  if e.name == "UserPromptSubmit" then
    -- Someone typed into it, so it runs (a session resumed after it was judged closed).
    s.isClosed = false
    local command = e.text:match("^/(%S+)")
    -- A message without a /command while the session is still busy (its turn running, or subagents it
    -- started still working) belongs to that work: it keeps the command, its animation and its subagents.
    -- Otherwise it starts a new turn.
    if command or not (s.isWorking or liveAgents(s) > 0) then
      s.agents, s.order, s.queued, s.score, s.test, s.summary = {}, {}, {}, 0, nil, ""
      s.turnAt, s.tools, s.lastTool = at, 0, nil
      s.command = command
      s.isListed = mapping:choiceFor(s.command) ~= "off"
      s.tag = e.text ~= "" and e.text:gsub("^/", "") or s.folder
    end
    s.isWorking = true
    s.mood = "thinking"
    say(nil)
  elseif e.name == "PreToolUse" then
    s.tools = s.tools + 1
    if e.tool ~= "" then s.lastTool = e.tool end
    if e.agentId ~= "" and s.agents[e.agentId] then s.agents[e.agentId].hits = s.agents[e.agentId].hits + 1 end
    -- Starting a subagent names its job; the subagent it starts takes the name, in the order they were called.
    if kind == "agent" and e.agentId == "" and e.text ~= "" then s.queued[#s.queued + 1] = e.text end
    -- The agent calling a listed skill starts the show mid-turn, as typing its /command does.
    if kind == "skill" and mapping:mappedScene(e.text) then
      s.isListed, s.tag, s.command = true, e.text, e.text
    end
    -- A subagent that moves on to its next tool had its prompt answered (or denied).
    if e.agentId ~= "" and s.mood == "permission" and s.moodAgent == e.agentId then s.mood = nil end
    if e.agentId == "" then
      s.isWorking = true
      s.mood = nil
      if kind == "question" then s.mood, s.moodText = "asking", QUESTION_TEXT end
      if kind == "plan" then s.mood, s.moodText = "asking", PLAN_TEXT end
    end
    if s.mood == "asking" and s.isListed then say(s.moodText) else say(nil) end
    if kind == "reading" then
      s.readingUntil = ctx.frame + 20
    elseif e.flag == "test" then
      s.test = { state = "running" }
    else
      s.score = s.score + 1
      s.tappedAt = ctx.frame
    end
  elseif e.name == "PostToolUse" or e.name == "PostToolUseFailure" then
    if e.flag == "test" and s.test then
      s.test = { state = e.name == "PostToolUse" and "pass" or "fail", untilFrame = ctx.frame + 30 }
    end
    if s.mood == "permission" or s.mood == "asking" then
      s.mood = nil
      say(nil)
    end
  elseif e.name == "PermissionRequest" then
    s.mood, s.moodText, s.moodAgent = "permission", (e.tool ~= "" and e.tool or "OK"), e.agentId
    -- Moved here from the tab's new session: that session's notification for it (no agent id) is said already.
    if sid ~= e.session and self.all[e.session] then self.all[e.session].askedVia = sid end
    if s.isListed then say("May I use " .. s.moodText .. "?") end
  elseif e.name == "SubagentStart" and e.agentId ~= "" then
    local queued = table.remove(s.queued, 1)
    local label = e.text ~= "" and e.text or queued or (e.agentType ~= "" and e.agentType or "agent")
    s.agents[e.agentId] = { label = label, hits = 0, done = false, at = at }
    s.order[#s.order + 1] = e.agentId
  elseif e.name == "SubagentStop" and s.agents[e.agentId] then
    s.agents[e.agentId].done = true
    -- A prompt you denied gets no tool result: the subagent's stop ends it, or the puppet would ask for hours.
    if s.mood == "permission" and s.moodAgent == e.agentId then s.mood = nil end
    finish(intents, sid, s)
  elseif e.name == "Notification" then
    local isShown = s.mood == "permission" or s.mood == "asking"
    local via = s.askedVia and self.all[s.askedVia]
    if e.agentId == "" and via and via.mood == "permission" then isShown = true end
    if s.isListed and not isShown then say(e.text ~= "" and e.text or (harness.name .. " needs you")) end
  elseif e.name == "Stop" then
    s.isWorking, s.mood, s.summary = false, nil, e.text
    -- Background subagents may still be working; the last one to stop says it then.
    finish(intents, sid, s)
  end
  markPlayed(s)
  return intents
end

return Sessions
