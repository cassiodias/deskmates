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

local function isAtRest(s)
  return not s.isWorking and s.mood == nil and liveAgents(s) == 0
end

-- A session playing now gets a puppet, which it keeps until it leaves the stage.
local function markPlayed(s)
  if s.isListed and (s.isWorking or s.mood ~= nil or liveAgents(s) > 0) then s.hasPlayed = true end
end

-- The scene for a session now: its command's animation while it works, its desk at rest otherwise.
function Sessions.sceneFor(s, mapping)
  local live = liveAgents(s)
  if not s.isListed then return "rest" end
  if s.mood == "asking" or s.mood == "permission" then return "code" end
  if not (s.isWorking or live > 0) then return "rest" end
  local choice = mapping:choiceFor(s.command)
  -- Once every subagent the turn started is done, the main conversation carries on at the laptop: no rally
  -- between players who have left the table.
  if choice == "pingpong" and (#s.order == 0 or live > 0) then return "pingpong" end
  if choice == "auto" and #s.order >= 2 and live > 0 then return "pingpong" end
  return "code"
end

-- The sessions with a puppet, oldest first: one that has played keeps it until it ends, its terminal tab
-- closes, it rests with no tab, or it has been silent for hours. With none, the home puppet.
function Sessions:stageKeys(now)
  local keys = {}
  for sid, s in pairs(self.all) do
    -- A session away from any tab first says what it did, then leaves.
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

-- Sessions iTerm should hold: those it ran in, and those with no terminal app at all (run in the background).
local function wantsItermTab(s)
  return s.app == nil or s.app == "" or s.app == "iTerm.app"
end

-- Given the terminal tabs iTerm holds now: a session whose tab was there and is gone was closed without saying
-- so. One never seen in a tab (closed before Hammerspoon started, or a background session) is away while it
-- rests: no tab to jump to, nothing to show; it comes back when it works again. With running (each terminal's
-- programs, terminals/programs.lua), a session whose harness names its program has ended once its terminal no
-- longer runs it.
function Sessions:closeMissing(tabs, running)
  for _, s in pairs(self.all) do
    local inTab = s.tty and tabs[s.tty]
    if inTab then s.wasInTab = true end
    if s.tty and s.wasInTab and not inTab then s.isClosed = true end
    if running and s.program and s.tty and not (running[s.tty] or {})[s.program] then s.isClosed = true end
    s.isAway = not inTab and not s.wasInTab and wantsItermTab(s)
  end
end

-- Ends the turn's show once the main thread and every subagent are done, saying what the agent did.
local function finish(intents, sid, s)
  if s.isListed and not s.isWorking and liveAgents(s) == 0 then
    intents[#intents + 1] = { key = sid, text = (s.summary ~= "" and s.summary or "Done") .. " ✓",
      seconds = config.DONE_SECONDS }
  end
end

-- Applies one event. ctx: mapping, harness (the event's), frame, replayFrom (skip older events).
function Sessions:apply(e, ctx)
  local intents = {}
  local sid, harness, mapping = e.session, ctx.harness, ctx.mapping
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
  if e.folder ~= "" then s.folder = e.folder end
  if e.app ~= "" then s.app = e.app end
  if e.tty:match("^/dev/ttys%d+$") then s.tty = e.tty end
  if s.tag == "" then s.tag = s.folder end
  if e.title and e.title ~= "" then s.title = e.title end
  local kind = harness.toolKind(e.tool)
  local function say(text, seconds) intents[#intents + 1] = { key = sid, text = text, seconds = seconds } end

  if e.name == "UserPromptSubmit" then
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
    s.mood, s.moodText = "permission", (e.tool ~= "" and e.tool or "OK")
    if s.isListed then say("May I use " .. s.moodText .. "?") end
  elseif e.name == "SubagentStart" and e.agentId ~= "" then
    local queued = table.remove(s.queued, 1)
    local label = e.text ~= "" and e.text or queued or (e.agentType ~= "" and e.agentType or "agent")
    s.agents[e.agentId] = { label = label, hits = 0, done = false }
    s.order[#s.order + 1] = e.agentId
  elseif e.name == "SubagentStop" and s.agents[e.agentId] then
    s.agents[e.agentId].done = true
    finish(intents, sid, s)
  elseif e.name == "Notification" then
    local isShown = s.mood == "permission" or s.mood == "asking"
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
