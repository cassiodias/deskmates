-- Two puppets rally over a table; each seat is one of the turn's first two subagents, scoring its tool calls.

local config = require("puppet.config")
local pixels = require("puppet.render.pixels")
local sprites = require("puppet.render.sprites")
local label = require("puppet.render.text").label
local fill, stamp = pixels.fill, pixels.stamp

return {
  draw = function(buf, texts, s, ctx)
    local frame, px, W, H = ctx.frame, ctx.pixel, config.W, config.H
    -- Stand-ins hold the seats a command's turn has no subagent for.
    local left = s.agents[s.order[1]] or { label = s.tag, hits = s.score, done = false }
    local right = s.agents[s.order[2]] or { label = ctx.harness.id, hits = 0, done = false }
    local body = sprites.body(ctx.harness)
    fill(buf, 10, 17, W - 11, 18, "t")
    fill(buf, 12, 19, 12, H - 1, "g")
    fill(buf, W - 13, 19, W - 13, H - 1, "g")
    fill(buf, W // 2, 14, W // 2, 16, "w")
    -- Standing on the floor level with the table's top, however tall the body is.
    local top = 18 - #body.FRONT
    stamp(buf, body.FRONT, 0, top, left.done and "d" or nil)
    stamp(buf, body.FRONT, W - 9, top, right.done and "d" or nil)
    -- A player whose subagent is done lowers its bat to the floor, a small check above its head.
    for _, seat in ipairs({ { agent = left, bat = 9, x = 2 }, { agent = right, bat = W - 10, x = W - 7 } }) do
      if seat.agent.done then
        fill(buf, seat.bat, 15, seat.bat, 17, "w")
        stamp(buf, sprites.DONE, seat.x, top - 4)
      else
        fill(buf, seat.bat, 13, seat.bat, 15, "w")
      end
    end

    local span = W - 22
    local p = frame % (2 * span)
    local x = p < span and p or 2 * span - p
    local y = 15 - math.floor(7 * math.sin(math.pi * x / span) + 0.5)
    fill(buf, 11 + x, y, 11 + x, y, "w")

    -- The score first, so a long name is the part that gets cut.
    local function seat(agent) return (agent.done and "✓ " or "") .. agent.hits .. " " .. agent.label end
    texts[#texts + 1] = label(seat(left), 0, 2, 22, "left", px)
    texts[#texts + 1] = label(seat(right), W - 22, 2, 22, "right", px)
  end,
}
