-- A puppet's speech bubble: no wider than the puppet, so neighbours' bubbles never overlap; long text wraps
-- onto a few lines. It sits above the puppet, right edges lined up, inside the screen the puppet is on
-- (below the puppet when there is no room above).

local config = require("puppet.config")

local HEIGHT, GAP, SCREEN_MARGIN, MAX_LINES = 34, 6, 8, 4
local CARD_CHAR, CARD_LINE = 6.7, 14 -- Menlo 11: the width of a character, the height of a line

local bubble = { HEIGHT = HEIGHT }

function bubble.frame(top, pixel, width, height)
  local puppetWidth, puppetHeight = config.W * pixel, (config.H + config.STATUS_H) * pixel
  local center = { x = top.x + puppetWidth / 2, y = top.y + puppetHeight / 2 }
  local screen = hs.screen.mainScreen():frame()
  for _, each in ipairs(hs.screen.allScreens()) do
    local f = each:frame()
    if center.x >= f.x and center.x < f.x + f.w and center.y >= f.y and center.y < f.y + f.h then screen = f end
  end
  local x = top.x + puppetWidth - width
  x = math.max(screen.x + SCREEN_MARGIN, math.min(x, screen.x + screen.w - width - SCREEN_MARGIN))
  local y = top.y - height - GAP
  if y < screen.y + SCREEN_MARGIN then y = top.y + puppetHeight + GAP end
  return { x = x, y = y, w = width, h = height }
end

-- How wide `text` draws at the bubble's size; an estimate where it cannot be measured.
local function measure(text)
  local size = hs.drawing and hs.drawing.getTextDrawingSize and hs.drawing.getTextDrawingSize(text, { size = 12 })
  if size and size.w then return math.ceil(size.w) + 2 end
  return 7 * (utf8.len(text) or #text)
end

-- Draws `text` into a puppet's bubble canvas, sized and placed for it.
function bubble.show(puppet, text, pixel)
  local textWidth = measure(text)
  local width = math.min(config.W * pixel, textWidth + 24)
  local lines = math.min(MAX_LINES, math.ceil(textWidth / (width - 24)))
  local height = HEIGHT + (lines - 1) * 15
  puppet.bubble:frame(bubble.frame(puppet.canvas:topLeft(), pixel, width, height))
  puppet.bubble:replaceElements({
    { type = "rectangle", action = "strokeAndFill", fillColor = { white = 1, alpha = 0.95 },
      strokeColor = { hex = puppet.color }, strokeWidth = 2, roundedRectRadii = { xRadius = 10, yRadius = 10 } },
    { type = "text", text = text, textColor = { white = 0.1 }, textSize = 12,
      textLineBreak = "wordWrap", frame = { x = 12, y = 8, w = width - 24, h = height - 14 } },
  })
end

-- Draws a card of `lines` into a puppet's bubble canvas: one line each, in a fixed-width font, as wide as the
-- longest line. Only one card shows at a time, so it may be wider than the puppet.
function bubble.card(puppet, lines, pixel)
  local longest = 0
  for _, line in ipairs(lines) do longest = math.max(longest, utf8.len(line) or #line) end
  local width, height = math.ceil(longest * CARD_CHAR) + 24, #lines * CARD_LINE + 16
  puppet.bubble:frame(bubble.frame(puppet.canvas:topLeft(), pixel, width, height))
  puppet.bubble:replaceElements({
    { type = "rectangle", action = "strokeAndFill", fillColor = { white = 1, alpha = 0.95 },
      strokeColor = { hex = puppet.color }, strokeWidth = 2, roundedRectRadii = { xRadius = 10, yRadius = 10 } },
    { type = "text", text = table.concat(lines, "\n"), textColor = { white = 0.1 }, textFont = "Menlo",
      textSize = 11, frame = { x = 12, y = 8, w = width - 20, h = height - 12 } },
  })
end

return bubble
