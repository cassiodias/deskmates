-- Staged demo helpers, run inside Hammerspoon: local D = dofile(this file).
-- D.begin(eventsFile): the Spoon reads a scratch events file, with neutral menu lists and fake iTerm tabs.
-- D.snap(path): composites every shown puppet and bubble over a dark background into one PNG.
-- D.finish(): back to the real events file and the saved menu choice.
local D = {}
local P = spoon.ClaudePuppet

function D.begin(eventsFile)
  P:stop()
  P.eventsFile = eventsFile
  P:start()
  P.mapping = require("puppet.model.mapping").new({
    coder = { "my-coding-skill" }, matrix = { "my-planner" }, pingpong = { "my-reviewer" }, conversation = "auto",
  })
  P.iterm.refresh = function(self)
    self.tabs = { ["/dev/ttys101"] = { window = 1, tab = 1 }, ["/dev/ttys102"] = { window = 1, tab = 2 },
      ["/dev/ttys103"] = { window = 1, tab = 3 } }
    self.windows = 1
    return true
  end
  P:refreshTabs()
  return "staged"
end

function D.snap(path)
  local parts = {}
  for _, key in ipairs(P.stage.keys) do
    local puppet = P.stage.puppets[key]
    parts[#parts + 1] = puppet.canvas
    if puppet.bubble:isShowing() then parts[#parts + 1] = puppet.bubble end
  end
  local x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
  for _, c in ipairs(parts) do
    local f = c:frame()
    x1, y1 = math.min(x1, f.x), math.min(y1, f.y)
    x2, y2 = math.max(x2, f.x + f.w), math.max(y2, f.y + f.h)
  end
  local pad = 12
  local sheet = hs.canvas.new({ x = 0, y = 0, w = x2 - x1 + 2 * pad, h = y2 - y1 + 2 * pad })
  sheet[1] = { type = "rectangle", action = "fill", fillColor = { hex = "#1E2228" } }
  for _, c in ipairs(parts) do
    local f = c:frame()
    sheet:appendElements({ type = "image", image = c:imageFromCanvas(),
      frame = { x = f.x - x1 + pad, y = f.y - y1 + pad, w = f.w, h = f.h } })
  end
  sheet:imageFromCanvas():saveToFile(path)
  sheet:delete()
  return "saved " .. path
end

-- Rests the mouse on a session's puppet, so its card shows.
function D.hover(key)
  local f = P.stage.puppets[key].canvas:frame()
  D.mouse = D.mouse or hs.mouse.absolutePosition()
  hs.mouse.absolutePosition({ x = f.x + f.w / 4, y = f.y + f.h / 2 })
  return "hovering"
end

function D.finish()
  if D.mouse then hs.mouse.absolutePosition(D.mouse) end
  P:stop()
  P.eventsFile = os.getenv("HOME") .. "/.claude-puppet/events"
  P:start()
  return "restored"
end

return D
