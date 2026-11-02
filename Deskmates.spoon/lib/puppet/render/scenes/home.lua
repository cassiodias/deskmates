-- The home puppet waits when no session has a puppet, and dozes off after a while.

local config = require("puppet.config")
local pixels = require("puppet.render.pixels")
local sprites = require("puppet.render.sprites")
local label = require("puppet.render.text").label
local fill, stamp = pixels.fill, pixels.stamp

return {
  draw = function(buf, texts, _, ctx)
    local W, H = config.W, config.H
    fill(buf, 0, 19, W - 1, 20, "b")
    fill(buf, 2, 21, 3, H - 1, "b")
    fill(buf, W - 4, 21, W - 3, H - 1, "b")
    local body = sprites.body(ctx.harness)
    local isAsleep = ctx.now - ctx.lastEventAt > config.IDLE_SLEEP_SECONDS
    -- Standing on the desk, however tall the body is.
    local top = 19 - #body.FRONT
    stamp(buf, isAsleep and body.FRONT_ASLEEP or body.FRONT, 19, top)
    if isAsleep then
      local rise = (ctx.frame // 5) % 4
      texts[#texts + 1] = label("z", 29 + rise, top - 3 - rise, 4, "left", ctx.pixel)
    end
  end,
}
