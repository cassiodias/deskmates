-- Text drawn on a puppet: labels on the drawing and the name tag under the table.

local config = require("puppet.config")
local W = config.W

local text = {}

-- White with a black outline, readable on dark and light desktops alike; dark on the permission sign.
-- One line: a text too long for it ends in "…".
function text.label(value, x, y, w, align, px, isDark)
  local style = {
    font = { name = "Menlo-Bold", size = 2.5 * px },
    color = { white = isDark and 0.1 or 1 },
    paragraphStyle = { alignment = align, lineBreak = "truncateTail" },
  }
  if not isDark then style.strokeColor, style.strokeWidth = { white = 0 }, -3 end
  return {
    type = "text", text = hs.styledtext.new(value, style),
    frame = { x = x * px, y = y * px, w = w * px, h = 4 * px },
  }
end

-- The name tag under the table: white text on a dark pill, clear on any desktop.
function text.pill(value, px)
  local size = 2.3 * px
  local width = math.min(W * px, (utf8.len(value) or #value) * size * 0.62 + 3 * px)
  local frame = { x = (W * px - width) / 2, y = 20.8 * px, w = width, h = 3.2 * px }
  return {
    { type = "rectangle", action = "fill", fillColor = { white = 0.08, alpha = 0.85 },
      roundedRectRadii = { xRadius = 1.6 * px, yRadius = 1.6 * px }, frame = frame },
    { type = "text", frame = { x = frame.x, y = frame.y + 0.25 * px, w = width, h = frame.h },
      text = hs.styledtext.new(value, { font = { name = "Menlo-Bold", size = size }, color = { white = 1 },
        paragraphStyle = { alignment = "center", lineBreak = "truncateTail" } }) },
  }
end

-- The status line under the name tag: smaller and light grey, outlined like the labels.
function text.status(value, px)
  return {
    type = "text", frame = { x = 0, y = config.H * px, w = W * px, h = config.STATUS_H * px },
    text = hs.styledtext.new(value, { font = { name = "Menlo-Bold", size = 2.1 * px }, color = { white = 0.85 },
      strokeColor = { white = 0 }, strokeWidth = -3,
      paragraphStyle = { alignment = "center", lineBreak = "truncateTail" } }),
  }
end

return text
