-- The bodies drawn for agents still to come, in a few poses, through the real scenes, as one PNG. Run inside
-- Hammerspoon: dofile(this file)(outPath)
return function(out)
  local scenes = require("puppet.render.scenes")
  local pixels = require("puppet.render.pixels")
  local config = require("puppet.config")
  local px, now = 4, os.time()
  local cellW, cellH = config.W * px + 16, (config.H + 4) * px + 16
  local bodies = {
    { "owl", "#3FA7A0" }, { "cat", "#A06CD5" },
  }
  local function session(fields)
    local s = { agents = {}, order = {}, queued = {}, score = 3, tools = 0, isWorking = true, readingUntil = 0,
      summary = "", tappedAt = -100, joinedAt = 1, folder = "shop-api", tag = "my-skill", turnAt = now,
      seenAt = now, isListed = true }
    for k, v in pairs(fields) do s[k] = v end
    return s
  end
  local poses = {
    { "coding", "code", session({}), 2 },
    { "question", "code", session({ mood = "asking" }), 2 },
    { "ping pong", "pingpong", session({ order = { "a", "b" }, agents = {
        a = { label = "contract", hits = 4, done = false }, b = { label = "break it", hits = 2, done = false } } }), 6 },
    { "home", "home", nil, 2 },
  }
  local sheet = hs.canvas.new({ x = 0, y = 0, w = cellW * #poses, h = cellH * #bodies + 20 })
  sheet[1] = { type = "rectangle", action = "fill", fillColor = { hex = "#1E2228" } }
  for row, body in ipairs(bodies) do
    local harness = { id = body[1], character = { body = body[1] } }
    for col, pose in ipairs(poses) do
      local elements = scenes.elements(pose[3], {
        frame = pose[4], pixel = px, now = now, lastEventAt = now - (pose[1] == "home" and 0 or 60),
        scene = pose[2], monitor = "invaders", harness = harness, colors = pixels.colorsFor(body[2]),
        tag = body[1] .. " · " .. pose[1],
      })
      local ox, oy = (col - 1) * cellW + 8, (row - 1) * cellH + 28
      for _, e in ipairs(elements) do
        if e.frame then
          local f = e.frame
          e.frame = { x = f.x + ox, y = f.y + oy, w = f.w, h = f.h }
          sheet:appendElements(e)
        end
      end
    end
  end
  sheet:imageFromCanvas():saveToFile(out)
  sheet:delete()
  return "saved"
end
