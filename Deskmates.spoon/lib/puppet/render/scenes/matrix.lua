-- The coder's monitor as Matrix rain: every other column falls at its own speed, a bright head over a fading
-- trail, with glyph-like gaps that flicker; it pours faster for a moment after each tool call.

local config = require("puppet.config")
local fill = require("puppet.render.pixels").fill

return {
  draw = function(buf, s, ctx)
    local frame, top, bottom = ctx.frame, 2, 17
    local rows = bottom - top + 1
    local surge = frame - s.tappedAt < 10 and 2 or 1
    for x = 18, config.W - 3, 2 do
      local seed = (x * 7919) % 97
      local speed, length = 1 + seed % 3, 5 + seed % 6
      local head = (frame * speed * surge // 2 + seed) % (rows + length)
      for back = 0, length - 1 do
        local y = top + head - back
        local isGlyph = (x * 31 + (y + frame // 3) * 17) % 5 ~= 0
        if y >= top and y <= bottom and (back == 0 or isGlyph) then
          local key = back == 0 and "m" or (back < length * 2 / 3 and "n" or "o")
          fill(buf, x, y, x, y, key)
        end
      end
    end
  end,
}
