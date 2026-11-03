-- Draws one puppet: the scene Sessions.sceneFor picked for its session, as canvas elements. A scene is a module
-- with draw(buf, texts, session, ctx), listed in SCENES; CONTRIBUTING.md ("Add an animation") has every step.

local pixels = require("puppet.render.pixels")
local text = require("puppet.render.text")

local SCENES = {
  code = require("puppet.render.scenes.desk"),
  rest = require("puppet.render.scenes.desk"),
  pingpong = require("puppet.render.scenes.pingpong"),
  home = require("puppet.render.scenes.home"),
}

local scenes = {}

-- ctx: frame, pixel, now, lastEventAt, scene and screen (from Sessions.sceneFor), harness, colors, tag (the name
-- tag, or nil), status (the line under the name tag, or nil).
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
