--- === Deskmates ===
---
--- Puppets that float over your desktop, one per busy coding-agent session, acting out what it is doing:
--- it thinks, codes at its laptop (invaders or Matrix rain on its monitor), reads, runs tests, plays ping pong
--- while subagents run, shows a question mark when the agent asks you something, and says what it did when it is done.
--- Click a puppet to jump to its session's terminal; double-click it to read its card, when its agent made a plan, works on a ticket
--- or works in a git repo (plan vs actual and its turns).
---
--- Agent hooks append one line per event to `~/.deskmates/events`; this Spoon reads it. This file is the
--- Spoon's public surface and its wiring; the parts (events, model, render, stage, terminals, ui and one
--- module per agent) live in lib/puppet/.

local root = hs.spoons.scriptPath()
if not package.path:find(root .. "lib/?.lua", 1, true) then
  package.path = root .. "lib/?.lua;" .. root .. "lib/?/init.lua;" .. package.path
end

local config = require("puppet.config")
local parse = require("puppet.events.parse")
local Reader = require("puppet.events.reader")
local Mapping = require("puppet.model.mapping")
local Sessions = require("puppet.model.sessions")
local status = require("puppet.model.status")
local harnesses = require("puppet.harnesses")
local plans = require("puppet.model.plans")
local facts = require("puppet.model.facts")
local scenes = require("puppet.render.scenes")
local Stage = require("puppet.stage.stage")
local git = require("puppet.terminals.git")
local backfill = require("puppet.terminals.backfill")
local Iterm = require("puppet.terminals.iterm")
local Liveness = require("puppet.terminals.liveness")
local newTerminals = require("puppet.terminals.focus")
local menuItems = require("puppet.ui.menu")
local plancard = require("puppet.ui.plancard")
local sessioncard = require("puppet.ui.sessioncard")
local story = require("puppet.ui.story")
local workcard = require("puppet.ui.workcard")
local bubble = require("puppet.stage.bubble")

local obj = {}
obj.__index = obj

obj.name = "Deskmates"
obj.version = "0.14.0"
obj.author = "Cassio Dias"
obj.license = "MIT - https://opensource.org/licenses/MIT"
obj.homepage = "https://github.com/cassiodias/deskmates"

--- Deskmates.coder
--- Variable
--- Slash commands or skills whose turns show the coder, without the slash.
obj.coder = {}

--- Deskmates.matrix
--- Variable
--- Slash commands or skills whose turns show the coder with Matrix rain on its monitor, without the slash.
obj.matrix = {}

--- Deskmates.pingpong
--- Variable
--- Slash commands or skills whose turns show ping pong, without the slash.
obj.pingpong = {}

--- Deskmates.conversation
--- Variable
--- What the main conversation shows (any turn whose command is on no list):
--- "coder", "matrix", "auto" (ping pong while subagents run, coder otherwise) or "off".
--- These four are the starting choice; once you change them in the menu bar, that choice is kept instead.
obj.conversation = "auto"

--- Deskmates.pixel
--- Variable
--- Size of one puppet pixel, in screen points.
obj.pixel = 4

--- Deskmates.eventsFile
--- Variable
--- The file the agent hooks append events to.
obj.eventsFile = os.getenv("HOME") .. "/.deskmates/events"

--- Deskmates.plansDir
--- Variable
--- The folder the hooks keep each session's plan in (hook/plan-lib.sh).
obj.plansDir = os.getenv("HOME") .. "/.deskmates/plans"

--- Deskmates.factsDir
--- Variable
--- The folder the hooks keep each session's facts in: its tickets, phases and timeline (hook/facts-lib.sh).
obj.factsDir = os.getenv("HOME") .. "/.deskmates/facts"

--- Deskmates.backfillScript
--- Variable
--- The script that fills a Claude session's facts from its transcript when its card opens (beside the hooks).
obj.backfillScript = root .. "../hook/backfill.sh"

--- Deskmates.onFile
--- Variable
--- The marker that says Deskmates runs: it holds Hammerspoon's process id, and the hooks keep plans only while
--- it names a running process.
obj.onFile = os.getenv("HOME") .. "/.deskmates/on"

-- Applies one events-file line; bubbles are skipped while replaying history.
function obj:handle(line)
  local event = parse.line(line)
  if not event then return end
  local intents = self.sessions:apply(event, {
    mapping = self.mapping, harness = harnesses.get(event.harness), frame = self.frame, now = os.time(),
    replayFrom = self.replayFrom,
  })
  -- A line that changed the session's plan: read it again from its file.
  if event.flag == "plan" and self.sessions.all[event.session] then
    local path = plans.path(self.plansDir, event.session)
    for _, intent in ipairs(self.sessions:setPlan(event.session, path and plans.load(path))) do
      intents[#intents + 1] = intent
    end
  end
  -- A line that changed the session's facts (a test line may have): read them again from their file.
  if (event.flag == "facts" or event.flag == "test") and self.sessions.all[event.session] then
    local path = facts.path(self.factsDir, event.session)
    self.sessions:setFacts(event.session, path and facts.load(path))
  end
  if self.replayFrom then return end
  -- The card open on this session shows the change at once, and what git says now.
  if (event.flag == "plan" or event.flag == "facts" or event.flag == "test") and self.planCard.key == event.session then
    self:refreshCard(event.session)
    self:readGit(event.session)
  end
  for _, intent in ipairs(intents) do self:say(intent.key, intent.text, intent.seconds) end
end

-- Deletes the plans and facts no session needs: those of sessions it no longer knows, once they are hours old.
function obj:sweepPlans()
  local keep = {}
  for sid in pairs(self.sessions.all) do keep[sid] = true end
  plans.sweep(self.plansDir, keep, os.time(), config.STALE_SECONDS)
  facts.sweep(self.factsDir, keep, os.time(), config.STALE_SECONDS)
end

-- Marks that Deskmates runs, or no longer does.
function obj:markOn(isOn)
  if not isOn then
    os.remove(self.onFile)
    return
  end
  hs.fs.mkdir(self.onFile:match("^(.*)/[^/]*$") or ".")
  local file = io.open(self.onFile, "w")
  if not file then return end
  file:write(tostring(hs.processInfo.processID) .. "\n")
  file:close()
end

--- Deskmates:say(key, text, seconds)
--- Method
--- Shows a speech bubble above a session's puppet; it stays until the next event, or for `seconds` when given.
function obj:say(key, text, seconds)
  if not self.stage.puppets[key] and text and text ~= "" then self:layout() end
  self.stage:say(key, text, seconds)
end

function obj:layout()
  self.stage:sync(self.sessions:stageKeys(os.time()), function(key)
    local s = self.sessions.all[key]
    return harnesses.get(s and s.harness).character.palette
  end)
end

function obj:render()
  self.frame = self.frame + 1
  self:layout()
  local now = os.time()
  -- A missed mouseExit must not leave a card behind.
  if self.hovered and not self:isUnderMouse(self.hovered) then self:hover(self.hovered, false) end
  for _, key in ipairs(self.stage.keys) do
    local puppet, s = self.stage.puppets[key], self.sessions.all[key]
    local scene, screen = Sessions.sceneFor(s, self.mapping)
    local tab = s and self.iterm:label(s.tty)
    if s and key == self.hovered then self.stage:showCard(key, status.card(s, now, tab)) end
    puppet.canvas:replaceElements(scenes.elements(s, {
      frame = self.frame, pixel = self.pixel, now = now, lastEventAt = self.sessions.lastEventAt,
      scene = scene, screen = screen,
      harness = harnesses.get(s and s.harness), colors = puppet.colors,
      tag = s and (tab and (s.tag .. " · " .. tab) or s.tag),
      status = s and status.line(s, now),
    }))
  end
end

-- Takes one look at what runs (terminals, their programs, the agents' apps, iTerm's tabs) and lets the sessions
-- judge which are still there: the same for every terminal app.
function obj:refreshLiveness()
  self.sessions:applyLiveness(Liveness.look(harnesses.all, self.iterm))
end

--- Deskmates:focus(key)
--- Method
--- Brings forward the window running a session, as its harness knows how.
function obj:focus(key)
  local s = self.sessions.all[key]
  if s then harnesses.get(s.harness).focus(s, self.terminals) end
end

-- What git said for session `key`'s card: { reading = true } until it answers, then { error = text } or
-- git.read's result.
function obj:gitState(key)
  local kept = self.cardGit
  return kept and kept.key == key and kept.state or { reading = true }
end

-- The part of a card's version that git's answer `state` gives: its raw texts, so the same answer twice is the
-- same version.
local function gitVersion(state)
  if state.reading then return "reading" end
  if state.error then return "error " .. state.error end
  return table.concat({ tostring(state.commits), tostring(state.diff), tostring(state.uncommitted),
    tostring(state.untracked) }, "\0|\0")
end

-- What session `key`'s card shows: its plan (nil when it has none to show), the card's meta, with the session's
-- facts, in a git repo plan vs actual (meta.work), and the story of both (meta.story), and which version of the files and of git's
-- answer it shows (nil when a file does not say); nil when there is no plan, no facts and no git.
function obj:cardContent(key)
  local s, puppet = self.sessions.all[key], self.stage.puppets[key]
  if not (s and puppet) then return nil end
  local plan = plans.hasContent(s.plan) and s.plan or nil
  local now = os.time()
  local session = facts.hasContent(s.facts) and sessioncard.view(s.facts, now, s.isWorking) or nil
  local state = self:gitState(key)
  local work = workcard.view(s.facts, state, s.plan, s.isWorking)
  local told = story.view(session, work, now)
  if not plan and not session and not work then
    -- Nothing yet, but the transcript is being read (or could not be): the card says so.
    local filling = self:backfillState(key)
    if not filling then return nil end
    local line = filling.reading and "Reading the transcript…" or filling.error or "Nothing more in the transcript"
    return nil, { title = (s.title and s.title ~= "") and s.title or s.tag, color = puppet.color,
      story = story.lineHtml(line) }, "backfill|" .. line
  end
  local version
  if (not plan or plan.updatedAt) and (not (session or work) or s.facts.updatedAt) then
    version = tostring(plan and plan.updatedAt) .. "|" .. tostring((session or work) and s.facts.updatedAt)
      .. (work and "|" .. tostring(s.isWorking) .. "|" .. gitVersion(state) or "")
  end
  return plan, { title = (s.title and s.title ~= "") and s.title or s.tag, color = puppet.color, session = session,
    work = work and workcard.html(work), story = told and story.html(told) }, version
end

-- Shows the card open on session `key` again, only when what it shows changed: a new page loses the reader's
-- place.
function obj:refreshCard(key)
  local plan, meta, version = self:cardContent(key)
  if meta and (version == nil or version ~= self.cardVersion) then
    self.cardVersion = version
    self.planCard:update(key, plan, meta)
  end
end

-- Asks git, off the main thread, what changed in session `key`'s repo since its base, for the card open on it;
-- the answer is kept in self.cardGit and shown, unless the card no longer shows that session (a card opened again
-- starts afresh). One read at a time per card. Nothing for a session not in a git repo.
function obj:readGit(key)
  local s = self.sessions.all[key]
  if not (s and facts.hasGit(s.facts)) then return end
  local kept = self.cardGit
  if not (kept and kept.key == key) then
    kept = { key = key, state = { reading = true } }
    self.cardGit = kept
  end
  -- One read at a time: a change while git reads asks for one more read, after it, which sees them all.
  if kept.busy then
    kept.again = true
    return
  end
  kept.busy = true
  git.read(s.facts.git.root, s.facts.git.base, function(result, message)
    kept.busy = false
    if self.cardGit ~= kept or self.planCard.key ~= key then return end
    kept.state = result or { error = message }
    self:refreshCard(key)
    if kept.again then
      kept.again = false
      self:readGit(key)
    end
  end)
end

-- What the transcript backfill of session `key`'s card is doing: { reading = true }, { error = why },
-- { done = true }, or nil when none ran for it.
function obj:backfillState(key)
  local kept = self.cardBackfill
  return kept and kept.key == key and kept.state or nil
end

-- Starts filling session `key`'s facts from its transcript, for the card opening on it: only for Claude sessions
-- with a transcript, one run at a time per card. The answer reloads the facts and redraws the card, unless the card
-- no longer shows that session. Returns at once; false when nothing started.
function obj:backfill(key)
  local s = self.sessions.all[key]
  if not (s and s.harness == "claude") then return false end
  local kept = self.cardBackfill
  if kept and kept.key == key and kept.busy then return false end
  local home = os.getenv("HOME") or ""
  if not backfill.find(home, key, hs.fs.dir, function(p) return hs.fs.attributes(p, "mode") ~= nil end) then
    return false
  end
  kept = { key = key, busy = true, state = { reading = true } }
  self.cardBackfill = kept
  return true
end

-- Runs the backfill started for the card on `key` (obj:backfill), once the card shows.
function obj:runBackfill(key)
  local kept = self.cardBackfill
  if not (kept and kept.key == key and kept.busy and not kept.running) then return end
  kept.running = true
  backfill.run(self.backfillScript, key, function(status, detail)
    kept.busy, kept.running = false, false
    if self.cardBackfill ~= kept or self.planCard.key ~= key then return end
    if status == "error" then
      kept.state = { error = detail }
    else
      kept.state = { done = true }
      if status == "ok" then
        local path = facts.path(self.factsDir, key)
        self.sessions:setFacts(key, path and facts.load(path))
      end
    end
    self:refreshCard(key)
    if status == "ok" then self:readGit(key) end
  end)
end

--- Deskmates:click(key)
--- Method
--- A click on a session's puppet goes to its terminal; the second click of a double click opens its card when its
--- session has a plan, facts or a git repo to show (the terminal is already in front, the card opens beside it).
--- The card opens at once; what git says fills it when git answers.
function obj:click(key)
  local now = hs.timer.secondsSinceEpoch()
  local last = self.lastClick
  local isDouble = last and last.key == key and now - last.at <= hs.eventtap.doubleClickInterval()
  -- A third click starts again: it goes to the terminal, as a first one.
  self.lastClick = not isDouble and { key = key, at = now } or nil
  local plan, meta, version
  if isDouble then
    -- The facts as they are now, the hooks may have written them since the last line said so; git not read yet.
    local path = facts.path(self.factsDir, key)
    self.sessions:setFacts(key, path and facts.load(path))
    self.cardGit = nil
    self:backfill(key)
    plan, meta, version = self:cardContent(key)
  end
  if meta then
    self.cardVersion = version
    self.planCard:show(key, plan, meta)
    self:readGit(key)
    self:runBackfill(key)
  else
    self:focus(key)
    -- The gap to a second click counts from here: a click waiting while the terminal came forward is still the
    -- second click of a double click.
    if self.lastClick then self.lastClick.at = hs.timer.secondsSinceEpoch() end
  end
end

-- Where a plan card of w by h goes: beside its puppet, as its bubble would, and whole on the puppet's screen
-- (smaller, when it is bigger than the screen).
function obj:cardFrame(key, w, h)
  local puppet = self.stage.puppets[key]
  local screen = hs.screen.mainScreen():frame()
  local f = puppet and bubble.frame(puppet.canvas:topLeft(), self.pixel, w, h)
    or { x = screen.x + screen.w - w, y = screen.y + screen.h - h, w = w, h = h }
  for _, each in ipairs(hs.screen.allScreens()) do
    local s = each:frame()
    if f.x + w / 2 >= s.x and f.x + w / 2 < s.x + s.w then screen = s end
  end
  w, h = math.min(w, screen.w), math.min(h, screen.h)
  f.w, f.h = w, h
  f.y = math.max(screen.y, math.min(f.y, screen.y + screen.h - h))
  f.x = math.max(screen.x, math.min(f.x, screen.x + screen.w - w))
  return f
end

-- Keeps the menu's choice and applies it at once to every session's current turn.
function obj:saveChoice()
  hs.settings.set(config.CHOICE_KEY, self.mapping:toSaved())
  self.sessions:remap(self.mapping)
end

-- Edits one animation's commands as text in a dialog.
function obj:editScene(scene, name)
  hs.focus()
  local button, typed = hs.dialog.textPrompt(name,
    "Commands or skills whose turns show " .. name .. ", comma separated, like my-coding-skill",
    table.concat(self.mapping[scene], ", "), "Save", "Cancel")
  if button ~= "Save" then return end
  self.mapping:setList(scene, typed)
  self:saveChoice()
end

-- The menu's saved choice, else the variables above; a choice saved by an older version is carried over.
function obj:loadChoice()
  local saved = hs.settings.get(config.CHOICE_KEY)
  local mapping = Mapping.fromSaved(saved, hs.settings.get("ClaudePuppet.commands"), hs.settings.get("ClaudePuppet.scenes"))
  if not saved then
    for _, key in ipairs({ "ClaudePuppet.commands", "ClaudePuppet.scenes", "ClaudePuppet.seenCommands" }) do
      hs.settings.clear(key)
    end
  end
  self.mapping = mapping or Mapping.new({
    coder = self.coder, matrix = self.matrix, pingpong = self.pingpong, conversation = self.conversation,
  })
  if mapping then hs.settings.set(config.CHOICE_KEY, mapping:toSaved()) end
end

-- Dragging any puppet moves the whole row, and the place is remembered; a click without a drag is a focus.
-- The press starts a mouse tap that follows the drag, judged only by the drag events' own positions (the
-- mouse's position when a busy Hammerspoon gets to it can be off). The click itself is the release the puppet's
-- canvas reports: a quick click's release comes before the tap has started, and the tap never sees it.
function obj:startDrag(key)
  -- A press whose release Hammerspoon missed leaves its tap running: only the last press is followed.
  if self.dragTap then self.dragTap:stop() end
  local press = { key = key, isDrag = false }
  self.press = press
  local origin = { x = self.stage.anchor.x, y = self.stage.anchor.y }
  local types = hs.eventtap.event.types
  local first
  local tap
  tap = hs.eventtap.new({ types.leftMouseDragged, types.leftMouseUp }, function(e)
    local now = e:location()
    if e:getType() == types.leftMouseDragged then
      first = first or now
      press.isDrag = press.isDrag or math.abs(now.x - first.x) + math.abs(now.y - first.y) >= config.CLICK_DISTANCE
      -- Until it is a drag, the row stays exactly where it was, so clicks do not make it creep.
      self.stage.anchor = press.isDrag and { x = origin.x + now.x - first.x, y = origin.y + now.y - first.y } or origin
      self:layout()
      return false
    end
    tap:stop()
    if self.dragTap == tap then self.dragTap = nil end
    if press.isDrag then hs.settings.set(config.POSITION_KEY, self.stage.anchor) end
    return false
  end)
  self.dragTap = tap
  tap:start()
end

-- The release on a puppet: a click, unless the press became a drag.
function obj:mouseUp(key)
  local press = self.press
  self.press = nil
  if self.dragTap and not (press and press.isDrag) then
    self.dragTap:stop()
    self.dragTap = nil
  end
  if not press or press.isDrag or press.key ~= key then return end
  -- Bringing a terminal forward can take a moment (iTerm's AppleScript); not inside the mouse's handling.
  -- A double click opens the session's card (obj:click).
  hs.timer.doAfter(0, function() self:click(key) end)
end

-- Resting the mouse on a puppet shows its card: where it is and what it is doing; render keeps it current.
function obj:hover(key, isInside)
  if isInside then
    self.hovered = key
    self:render()
  else
    if self.hovered == key then self.hovered = nil end
    self.stage:hideCard(key)
  end
end

function obj:isUnderMouse(key)
  local puppet = self.stage.puppets[key]
  if not puppet then return false end
  local f, at = puppet.canvas:frame(), hs.mouse.absolutePosition()
  return at.x >= f.x and at.x < f.x + f.w and at.y >= f.y and at.y < f.y + f.h
end

-- Option-click opens the menu bar menu at the puppet, for when the menu bar icon is hidden behind the notch.
function obj:mouseDown(key)
  if hs.eventtap.checkKeyboardModifiers().alt then
    self.menu:popupMenu(hs.mouse.absolutePosition())
  else
    self:startDrag(key)
  end
end

-- The bottom right corner of a screen, the main one when none is given.
function obj:defaultPosition(screen)
  local frame = (screen or hs.screen.mainScreen()):frame()
  return { x = frame.x + frame.w - config.W * self.pixel - 40, y = frame.y + frame.h - (config.H + config.STATUS_H) * self.pixel - 40 }
end

-- Puppets left on a screen that is no longer connected come back to the main screen's corner.
function obj:isOnAScreen(point)
  local center = { x = point.x + config.W * self.pixel / 2, y = point.y + config.H * self.pixel / 2 }
  for _, screen in ipairs(hs.screen.allScreens()) do
    local f = screen:frame()
    if center.x >= f.x and center.x < f.x + f.w and center.y >= f.y and center.y < f.y + f.h then return true end
  end
  return false
end

function obj:moveToCorner(screen)
  self.stage.anchor = self:defaultPosition(screen)
  hs.settings.set(config.POSITION_KEY, self.stage.anchor)
  self:layout()
end

-- The menu bar icon, dimmed while the puppets are hidden.
function obj:showIcon()
  local icon = "▟▙"
  if not self.stage.isShown then icon = hs.styledtext.new(icon, { color = { white = 0.5, alpha = 0.5 } }) end
  self.menu:setTitle(icon)
end

--- Deskmates:toggle()
--- Method
--- Hides the puppets, or shows them again; Hammerspoon remembers which across restarts.
function obj:toggle()
  self.stage:toggle()
  hs.settings.set(config.HIDDEN_KEY, not self.stage.isShown)
  self:showIcon()
end

--- Deskmates:bindHotkeys(mapping)
--- Method
--- Binds keys to the Spoon's actions; `toggle` hides or shows the puppets.
--- Example: `spoon.Deskmates:bindHotkeys({ toggle = { { "ctrl", "alt", "cmd" }, "p" } })`
function obj:bindHotkeys(mapping)
  hs.spoons.bindHotkeysToSpec({ toggle = function() self:toggle() end }, mapping)
  return self
end

--- Deskmates:start()
--- Method
--- Shows the puppets and starts following the agents' events.
function obj:start()
  config.carryOverSettings(hs.settings)
  self:markOn(true)
  local anchor = hs.settings.get(config.POSITION_KEY) or self:defaultPosition()
  if not self:isOnAScreen(anchor) then anchor = self:defaultPosition() end
  self.stage = Stage.new({
    pixel = self.pixel, anchor = anchor,
    onMouseDown = function(key) self:mouseDown(key) end,
    onMouseUp = function(key) self:mouseUp(key) end,
    onBubbleClick = function(key) self:focus(key) end,
    onHover = function(key, isInside) self:hover(key, isInside) end,
  })
  self.planCard = plancard.new({
    onFocus = function(key) self:focus(key) end,
    frameFor = function(key, w, h) return self:cardFrame(key, w, h) end,
    loadSize = function() return hs.settings.get(config.CARD_SIZE_KEY) end,
    saveSize = function(size) hs.settings.set(config.CARD_SIZE_KEY, size) end,
  })
  self.screenWatcher = hs.screen.watcher.new(function()
    if not self:isOnAScreen(self.stage.anchor) then self:moveToCorner() end
  end)
  self.screenWatcher:start()
  self.frame = 0
  self:loadChoice()
  self.sessions = Sessions.new(os.time())
  self.iterm = Iterm.new()
  self.terminals = newTerminals(self.iterm)
  -- Replays the last hours of events, without bubbles, so a restart finds every session as it was.
  self.reader = Reader.new(self.eventsFile)
  self.replayFrom = os.time() - config.STALE_SECONDS
  self.reader:read(function(line) self:handle(line) end)
  self.replayFrom = nil
  self:sweepPlans()

  if hs.settings.get(config.HIDDEN_KEY) then self.stage:toggle() end
  -- Named, so macOS keeps the place you ⌘-drag the icon to (out from behind the notch, say).
  self.menu = hs.menubar.new(true, "Deskmates")
  self:showIcon()
  self.menu:setMenu(function() return menuItems(self) end)

  self.timer = hs.timer.doEvery(1 / config.FPS, function()
    self.reader:read(function(line) self:handle(line) end)
    self:render()
  end)
  self.tabsTimer = hs.timer.doEvery(config.TABS_SECONDS, function() self:refreshLiveness() end)
  self.sweepTimer = hs.timer.doEvery(3600, function() self:sweepPlans() end)
  self:refreshLiveness()
  self:render()
  return self
end

--- Deskmates:stop()
--- Method
--- Hides the puppets and stops following events.
function obj:stop()
  self:markOn(false)
  if self.timer then self.timer:stop() end
  if self.tabsTimer then self.tabsTimer:stop() end
  if self.sweepTimer then self.sweepTimer:stop() end
  if self.screenWatcher then self.screenWatcher:stop() end
  if self.dragTap then self.dragTap:stop() end
  if self.menu then self.menu:delete() end
  if self.stage then self.stage:removeAll() end
  if self.planCard then self.planCard:hide() end
  self.timer, self.tabsTimer, self.sweepTimer, self.dragTap, self.menu = nil, nil, nil, nil, nil
  return self
end

return obj
