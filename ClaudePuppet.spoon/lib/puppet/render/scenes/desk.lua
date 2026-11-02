-- The puppet at its desk: a small `_|` laptop under its paws and a monitor. Its pose shows the session's mood:
-- typing, thinking, a question mark, a permission sign, now and then a smile; resting, it dozes off after a while.

local config = require("puppet.config")
local pixels = require("puppet.render.pixels")
local sprites = require("puppet.render.sprites")
local label = require("puppet.render.text").label
local monitor = require("puppet.render.scenes.monitor")
local fill, stamp = pixels.fill, pixels.stamp

local function drawPuppet(buf, texts, s, ctx)
  local frame, px = ctx.frame, ctx.pixel
  local body = sprites.body(ctx.harness)
  if ctx.isResting then
    stamp(buf, body.SIDE, 1, 10)
    if ctx.now - s.seenAt > config.IDLE_SLEEP_SECONDS then
      local rise = (frame // 5) % 4
      texts[#texts + 1] = label("z", 9 + rise, 6 - rise, 4, "left", px)
    end
    return
  end
  local isSmiling = s.mood == nil and frame % 80 >= 68
  stamp(buf, isSmiling and body.SMILE or body.SIDE, 1, 10)
  if s.mood == "thinking" then
    fill(buf, 9, 14, 9, 15, "c")
    fill(buf, 10, 8, 10, 8, "w")
    fill(buf, 11, 6, 12, 6, "w")
    texts[#texts + 1] = label(string.rep(".", frame // 4 % 3 + 1), 11, 1, 8, "left", px)
  elseif s.mood == "asking" then
    stamp(buf, sprites.QUESTION, 9, 2)
  elseif s.mood == "permission" then
    fill(buf, 9, 7, 9, 11, "b")
    fill(buf, 1, 1, 15, 6, "w")
    texts[#texts + 1] = label(s.moodText .. "?", 1, 1.5, 15, "center", px, true)
  elseif not isSmiling and frame // 2 % 2 == 0 then
    fill(buf, 9, 16, 10, 16, "c")
  end
end

return {
  draw = function(buf, texts, s, ctx)
    local W, H = config.W, config.H
    fill(buf, 0, 19, W - 1, 20, "b")
    fill(buf, 2, 21, 3, H - 1, "b")
    fill(buf, W - 4, 21, W - 3, H - 1, "b")
    fill(buf, 9, 17, 14, 17, "g")
    fill(buf, 14, 11, 14, 17, "g")
    drawPuppet(buf, texts, s, ctx)
    monitor.draw(buf, texts, s, ctx)
  end,
}
