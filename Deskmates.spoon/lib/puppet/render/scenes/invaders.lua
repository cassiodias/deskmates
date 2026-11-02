-- The coder's monitor: a row of invaders, one shot down with each tool call.

local pixels = require("puppet.render.pixels")
local sprites = require("puppet.render.sprites")
local fill, stamp, bounce = pixels.fill, pixels.stamp, pixels.bounce

-- The order the invaders fall in, so a wave does not empty from one side.
local WAVE_ORDER = { 3, 1, 4, 2 }

return {
  draw = function(buf, s, ctx)
    local frame = ctx.frame
    local march = bounce(frame // 5, 3)
    local at = function(slot) return 19 + march + (slot - 1) * 6 end
    local killed = s.score % #WAVE_ORDER
    local target = s.score > 0 and WAVE_ORDER[(s.score - 1) % #WAVE_ORDER + 1] or nil
    local age = frame - s.tappedAt
    local isShooting = target ~= nil and age < 8
    local legs = sprites.INVADER[(frame // 3) % 2 + 1]
    for i = killed + 1, #WAVE_ORDER do stamp(buf, legs, at(WAVE_ORDER[i]), 5) end
    if isShooting and age < 4 then stamp(buf, legs, at(target), 5) end
    if isShooting and age >= 4 then stamp(buf, sprites.BOOM, at(target), 5) end
    local ship = isShooting and at(target) or 19 + bounce(frame // 2, 21)
    if isShooting and age < 4 then fill(buf, ship + 2, 13 - age * 2, ship + 2, 14 - age * 2, "w") end
    stamp(buf, sprites.SHIP, ship, 15)
  end,
}
