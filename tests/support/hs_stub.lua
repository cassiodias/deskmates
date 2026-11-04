-- A stand-in for the parts of Hammerspoon the Spoon uses: it records what would be drawn, opened or saved,
-- so the Spoon runs under plain Lua 5.4 with a clock and timers the test moves by hand.

local stub = { canvases = {}, timers = {}, settings = {}, focused = nil, selected = nil, clock = 1000000,
  mouse = { x = 0, y = 0 }, styled = {}, taps = {} }

-- A mouse event of type `kind` (a name in hs.eventtap.event.types) at x, y, to every running tap.
function stub.fire(kind, x, y)
  local types = { leftMouseDragged = 6, leftMouseUp = 2 }
  local event = { getType = function() return types[kind] end, location = function() return { x = x, y = y } end }
  for _, tap in ipairs(stub.taps) do
    if tap.running then tap.fn(event) end
  end
end

local function canvas(frame)
  local c = { frame_ = frame, shown = false, elements = {}, deleted = false }
  function c:level() return self end
  function c:behavior() return self end
  function c:clickActivating() return self end
  function c:canvasMouseEvents() return self end
  function c:mouseCallback(fn) self.onMouse = fn return self end
  function c:replaceElements(elements) self.elements = elements return self end
  function c:show() self.shown = true return self end
  function c:hide() self.shown = false return self end
  function c:isShowing() return self.shown end
  function c:delete() self.deleted = true end
  function c:topLeft(point)
    if point then self.frame_ = { x = point.x, y = point.y, w = self.frame_.w, h = self.frame_.h } end
    return { x = self.frame_.x, y = self.frame_.y }
  end
  function c:frame(f)
    if f then self.frame_ = f end
    return self.frame_
  end
  stub.canvases[#stub.canvases + 1] = c
  return c
end

local function timer(seconds, fn, repeats)
  local t = { seconds = seconds, fn = fn, repeats = repeats, stopped = false, due = stub.clock + seconds }
  function t:stop() self.stopped = true end
  function t:cancel() self.stopped = true end
  stub.timers[#stub.timers + 1] = t
  return t
end

local screen = { x = 0, y = 0, w = 1440, h = 900 }
local mainScreen = { frame = function() return screen end, name = function() return "Built-in" end }

stub.tabs = ""         -- what iTerm answers to the tab listing, "tty=window/tab;..."
stub.itermRunning = false

hs = {
  canvas = { new = canvas, windowLevels = { floating = 3 } },
  settings = {
    get = function(key) return stub.settings[key] end,
    set = function(key, value) stub.settings[key] = value end,
    clear = function(key) stub.settings[key] = nil end,
  },
  screen = {
    mainScreen = function() return mainScreen end,
    allScreens = function() return { mainScreen } end,
    watcher = { new = function() return { start = function() end, stop = function() end } end },
  },
  menubar = {
    new = function()
      return {
        setTitle = function(_, title)
          stub.icon = { text = title, style = stub.styled.text == title and stub.styled.style or nil }
        end,
        setMenu = function(_, fn) stub.menu = fn end,
        popupMenu = function() end,
        delete = function() end,
      }
    end,
  },
  timer = {
    doEvery = function(seconds, fn) return timer(seconds, fn, true) end,
    doAfter = function(seconds, fn) return timer(seconds, fn, false) end,
  },
  fs = {
    mkdir = function(path) return os.execute("mkdir '" .. path:gsub("'", "'\\''") .. "' 2>/dev/null") end,
    attributes = function(path, field)
      local file = io.open(path, "r")
      if not file then return nil end
      local size = file:seek("end")
      file:close()
      if field == "size" then return size end
      return { size = size }
    end,
  },
  application = {
    get = function(bundle)
      if bundle == "com.googlecode.iterm2" and not stub.itermRunning then return nil end
      if stub.quitApps and stub.quitApps[bundle] then return nil end
      return { allWindows = function() return {} end }
    end,
    launchOrFocusByBundleID = function(id) stub.focused = id end,
  },
  osascript = {
    applescript = function(script)
      if script:find("set out to", 1, true) then return true, stub.tabs end
      -- Selecting a tab: iTerm answers the id of the window holding it (its window number + 100), or 0.
      local tty = script:match('tty of s is "([^"]+)"')
      stub.selected = tty
      local window = stub.tabs:match(tty:gsub("%p", "%%%0") .. "=(%d+)/")
      return true, window and 100 + tonumber(window) or 0
    end,
  },
  -- A window by id; focusing it records the id in stub.raised.
  window = { get = function(id) return { focus = function() stub.raised = id end } end },
  styledtext = { new = function(text, style)
    stub.styled = { text = text, style = style }
    return text
  end },
  mouse = { absolutePosition = function() return { x = stub.mouse.x, y = stub.mouse.y } end },
  -- Taps the Spoon starts are kept in stub.taps; stub.fire(type, x, y) hands each running one an event at x, y.
  eventtap = {
    event = { types = { leftMouseDragged = 6, leftMouseUp = 2 } },
    checkKeyboardModifiers = function() return {} end,
    new = function(_, fn)
      local tap = { fn = fn, running = false }
      function tap:start() self.running = true stub.taps[#stub.taps + 1] = self return self end
      function tap:stop() self.running = false return self end
      return tap
    end,
  },
  processInfo = { processID = 4242 },
  dialog = { textPrompt = function() return "Cancel", "" end },
  focus = function() end,
  -- A shell command's output: only `ps` is run; stub.ps holds what it prints (nil: it failed).
  execute = function() return stub.ps, stub.ps ~= nil end,
  spoons = {
    scriptPath = function() return stub.spoonPath end,
    resourcePath = function(name) return stub.spoonPath .. name end,
  },
}

os.time = function() return math.floor(stub.clock) end

-- Moves the clock and runs the timers that came due, oldest first.
function stub.advance(seconds)
  local target = stub.clock + seconds
  while true do
    local next
    for _, t in ipairs(stub.timers) do
      if not t.stopped and t.due <= target and (not next or t.due < next.due) then next = t end
    end
    if not next then break end
    stub.clock = math.max(stub.clock, next.due)
    if next.repeats then next.due = next.due + next.seconds else next.stopped = true end
    next.fn()
  end
  stub.clock = target
end

return stub
