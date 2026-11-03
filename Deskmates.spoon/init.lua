--- === Deskmates ===
---
--- Puppets that float over your desktop, one per busy coding-agent session, acting out what it is doing:
--- it thinks, codes at its laptop (invaders or Matrix rain on its monitor), reads, runs tests, plays ping pong
--- while subagents run, shows a question mark when the agent asks you something, and says what it did when it is done.
--- Click a puppet to jump to its session's terminal.
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
local scenes = require("puppet.render.scenes")
local Stage = require("puppet.stage.stage")
local Iterm = require("puppet.terminals.iterm")
local Programs = require("puppet.terminals.programs")
local newTerminals = require("puppet.terminals.focus")
local menuItems = require("puppet.ui.menu")

local obj = {}
obj.__index = obj

obj.name = "Deskmates"
obj.version = "0.12.1"
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

-- Applies one events-file line; bubbles are skipped while replaying history.
function obj:handle(line)
  local event = parse.line(line)
  if not event then return end
  local intents = self.sessions:apply(event, {
    mapping = self.mapping, harness = harnesses.get(event.harness), frame = self.frame, now = os.time(),
    replayFrom = self.replayFrom,
  })
  if self.replayFrom then return end
  for _, intent in ipairs(intents) do self:say(intent.key, intent.text, intent.seconds) end
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
    local tab = s and self.iterm:label(s.tty)
    if s and key == self.hovered then self.stage:showCard(key, status.card(s, now, tab)) end
    puppet.canvas:replaceElements(scenes.elements(s, {
      frame = self.frame, pixel = self.pixel, now = now, lastEventAt = self.sessions.lastEventAt,
      scene = s and Sessions.sceneFor(s, self.mapping) or "home",
      monitor = s and self.mapping:choiceFor(s.command) == "matrix" and "matrix" or "invaders",
      harness = harnesses.get(s and s.harness), colors = puppet.colors,
      tag = s and (tab and (s.tag .. " · " .. tab) or s.tag),
      status = s and status.line(s, now),
    }))
  end
end

function obj:refreshTabs()
  -- Whether each app a harness runs sessions in is still running (checked even without iTerm).
  local apps = {}
  for _, harness in pairs(harnesses.all) do
    for _, bundle in pairs(harness.apps or {}) do apps[bundle] = hs.application.get(bundle) ~= nil end
  end
  self.sessions:closeQuitApps(apps)
  if not self.iterm:refresh() then return end
  local ps, ok = hs.execute("/bin/ps -axo tty=,comm=")
  self.sessions:closeMissing(self.iterm.tabs, ok and Programs.parse(ps) or nil)
end

--- Deskmates:focus(key)
--- Method
--- Brings forward the window running a session, as its harness knows how.
function obj:focus(key)
  local s = self.sessions.all[key]
  if s then harnesses.get(s.harness).focus(s, self.terminals) end
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
  hs.timer.doAfter(0, function() self:focus(key) end)
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
  local anchor = hs.settings.get(config.POSITION_KEY) or self:defaultPosition()
  if not self:isOnAScreen(anchor) then anchor = self:defaultPosition() end
  self.stage = Stage.new({
    pixel = self.pixel, anchor = anchor,
    onMouseDown = function(key) self:mouseDown(key) end,
    onMouseUp = function(key) self:mouseUp(key) end,
    onBubbleClick = function(key) self:focus(key) end,
    onHover = function(key, isInside) self:hover(key, isInside) end,
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

  if hs.settings.get(config.HIDDEN_KEY) then self.stage:toggle() end
  -- Named, so macOS keeps the place you ⌘-drag the icon to (out from behind the notch, say).
  self.menu = hs.menubar.new(true, "Deskmates")
  self:showIcon()
  self.menu:setMenu(function() return menuItems(self) end)

  self.timer = hs.timer.doEvery(1 / config.FPS, function()
    self.reader:read(function(line) self:handle(line) end)
    self:render()
  end)
  self.tabsTimer = hs.timer.doEvery(config.TABS_SECONDS, function() self:refreshTabs() end)
  self:refreshTabs()
  self:render()
  return self
end

--- Deskmates:stop()
--- Method
--- Hides the puppets and stops following events.
function obj:stop()
  if self.timer then self.timer:stop() end
  if self.tabsTimer then self.tabsTimer:stop() end
  if self.screenWatcher then self.screenWatcher:stop() end
  if self.dragTap then self.dragTap:stop() end
  if self.menu then self.menu:delete() end
  if self.stage then self.stage:removeAll() end
  self.timer, self.tabsTimer, self.dragTap, self.menu = nil, nil, nil, nil
  return self
end

return obj
