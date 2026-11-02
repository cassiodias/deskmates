-- A puppet's drawing as a grid of colour keys, and how it becomes canvas rectangles.

local config = require("puppet.config")
local W, H = config.W, config.H

local pixels = {}

function pixels.bounce(n, span)
  if span <= 0 then return 0 end
  local p = n % (2 * span)
  return p < span and p or 2 * span - p
end

function pixels.newBuffer()
  local buf = {}
  for y = 0, H - 1 do buf[y] = {} end
  return buf
end

function pixels.fill(buf, x1, y1, x2, y2, key)
  for y = math.max(0, y1), math.min(H - 1, y2) do
    for x = math.max(0, x1), math.min(W - 1, x2) do buf[y][x] = key end
  end
end

-- Draws a sprite with its top left at x, y; `recolor` swaps the puppet's colour (a finished subagent).
function pixels.stamp(buf, sprite, x, y, recolor)
  for row, line in ipairs(sprite) do
    for col = 1, #line do
      local key = line:sub(col, col)
      if key ~= "." then
        if recolor and key == "c" then key = recolor end
        pixels.fill(buf, x + col - 1, y + row - 1, x + col - 1, y + row - 1, key)
      end
    end
  end
end

-- The colour table of a puppet wearing `hex`.
function pixels.colorsFor(hex)
  local colors = {}
  for key, color in pairs(config.COLORS) do colors[key] = color end
  colors.c = { hex = hex }
  return colors
end

-- Turns the buffer into canvas rectangles, one per run of a colour on a row, in a puppet's colours.
function pixels.toElements(buf, px, colors)
  local elements = {}
  for y = 0, H - 1 do
    local x = 0
    while x < W do
      local key = buf[y][x]
      if key then
        local run = x
        while run + 1 < W and buf[y][run + 1] == key do run = run + 1 end
        elements[#elements + 1] = {
          type = "rectangle", action = "fill", fillColor = colors[key],
          frame = { x = x * px, y = y * px, w = (run - x + 1) * px, h = px },
        }
        x = run + 1
      else
        x = x + 1
      end
    end
  end
  return elements
end

return pixels
