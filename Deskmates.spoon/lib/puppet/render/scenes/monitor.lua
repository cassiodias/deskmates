-- The monitor on the desk: a progress bar while tests run, their result, a lens while the agent reads,
-- otherwise the session's screen (invaders or Matrix rain); dark while the puppet rests.

local config = require("puppet.config")
local pixels = require("puppet.render.pixels")
local sprites = require("puppet.render.sprites")
local label = require("puppet.render.text").label
local fill, stamp, bounce = pixels.fill, pixels.stamp, pixels.bounce

local SCREENS = {
  invaders = require("puppet.render.scenes.invaders"),
  matrix = require("puppet.render.scenes.matrix"),
}

return {
  draw = function(buf, texts, s, ctx)
    local frame, px, W = ctx.frame, ctx.pixel, config.W
    fill(buf, 17, 1, W - 2, 18, "g")
    fill(buf, 18, 2, W - 3, 17, "s")
    if ctx.isResting then return end
    texts[#texts + 1] = label(string.format("%05d", s.score), 30, 1.5, 15, "right", px)
    if s.test and s.test.state == "running" then
      fill(buf, 21, 9, 42, 10, "g")
      fill(buf, 21, 9, 21 + frame // 2 % 22, 10, "y")
      texts[#texts + 1] = label("tests", 18, 11.5, 28, "center", px)
      return
    end
    if s.test and frame < s.test.untilFrame then
      stamp(buf, s.test.state == "pass" and sprites.CHECK or sprites.CROSS, 29, 7)
      return
    end
    if frame < s.readingUntil then
      stamp(buf, sprites.LENS, 19 + bounce(frame, 20), 6)
      return
    end
    SCREENS[ctx.monitor].draw(buf, s, ctx)
  end,
}
