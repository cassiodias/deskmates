-- A stand-in for the parts of Hammerspoon the Spoon uses: it records what would be drawn, opened or saved,
-- so the Spoon runs under plain Lua 5.4 with a clock and timers the test moves by hand.

local stub = { canvases = {}, timers = {}, settings = {}, focused = nil, selected = nil, clock = 1000000,
  mouse = { x = 0, y = 0 }, styled = {} }

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
      return { allWindows = function() return {} end }
    end,
    launchOrFocusByBundleID = function(id) stub.focused = id end,
  },
  osascript = {
    applescript = function(script)
      if script:find("set out to", 1, true) then return true, stub.tabs end
      local tty = script:match('tty of s is "([^"]+)"')
      stub.selected = tty
      return true, stub.tabs:find(tty .. "=", 1, true) ~= nil
    end,
  },
  styledtext = { new = function(text, style)
    stub.styled = { text = text, style = style }
    return text
  end },
  mouse = { absolutePosition = function() return { x = stub.mouse.x, y = stub.mouse.y } end },
  eventtap = {
    event = { types = { leftMouseDragged = 6, leftMouseUp = 2 } },
    checkKeyboardModifiers = function() return {} end,
    new = function() return { start = function() end, stop = function() end } end,
  },
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
