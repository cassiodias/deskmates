-- Draws one puppet: picks the scene for its session and returns the canvas elements.
-- A scene is a module with draw(buf, texts, session, ctx); adding an animation is one file and one line here.

local pixels = require("puppet.render.pixels")
local text = require("puppet.render.text")

local SCENES = {
  code = require("puppet.render.scenes.desk"),
  rest = require("puppet.render.scenes.desk"),
  pingpong = require("puppet.render.scenes.pingpong"),
  home = require("puppet.render.scenes.home"),
}

local scenes = {}

-- ctx: frame, pixel, now, lastEventAt, scene, monitor, harness, colors, tag (the name tag, or nil),
-- status (the line under the name tag, or nil).
function scenes.elements(s, ctx)
  local buf, texts = pixels.newBuffer(), {}
  ctx.isResting = ctx.scene == "rest"
  SCENES[ctx.scene].draw(buf, texts, s, ctx)
  if ctx.tag then
    for _, element in ipairs(text.pill(ctx.tag, ctx.pixel)) do texts[#texts + 1] = element end
  end
  if ctx.status then texts[#texts + 1] = text.status(ctx.status, ctx.pixel) end
  local elements = pixels.toElements(buf, ctx.pixel, ctx.colors)
  for _, element in ipairs(texts) do elements[#elements + 1] = element end
  return elements
end

return scenes
