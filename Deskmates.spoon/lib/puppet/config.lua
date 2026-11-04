-- Sizes, timings and colours shared by every part of the Spoon.

local config = {
  W = 48, -- a puppet's drawing, in puppet pixels
  H = 24,
  STATUS_H = 3, -- the status line under the drawing
  FPS = 10,
  IDLE_SLEEP_SECONDS = 30,
  DONE_SECONDS = 8,
  STEP_DONE_SECONDS = 4, -- how long a plan's step done is said
  STALE_SECONDS = 2 * 60 * 60,
  GAP = 12,
  CLICK_DISTANCE = 4,
  TABS_SECONDS = 3,
  POSITION_KEY = "Deskmates.position",
  CHOICE_KEY = "Deskmates.choice",
  HIDDEN_KEY = "Deskmates.hidden",
  CARD_SIZE_KEY = "Deskmates.cardSize",
  COLORS = {
    c = { hex = "#D97757" }, -- the puppet; replaced by each puppet's own colour
    d = { hex = "#8C8C8C" }, -- a puppet whose subagent is done
    k = { hex = "#1E1E1E" }, -- eyes
    g = { hex = "#D0D0D0" }, -- laptop and monitor
    s = { hex = "#15181E" }, -- monitor screen
    v = { hex = "#8FD18B" }, -- invaders
    w = { hex = "#F2F2F2" }, -- shot, ball, net
    y = { hex = "#F2C14E" }, -- explosion
    b = { hex = "#8A6A4F" }, -- desk
    t = { hex = "#2E6B4F" }, -- ping pong table
    p = { hex = "#6BBF59" }, -- tests passed
    m = { hex = "#C8FFC0" }, -- Matrix rain, the falling head
    n = { hex = "#3FB950" }, -- Matrix rain, the trail
    o = { hex = "#1B5E20" }, -- Matrix rain, the fading end
    r = { hex = "#E5534B" }, -- tests failed
    i = { hex = "#F29CB4" }, -- the rabbit's nose and inner ears
  },
}

-- Settings saved under the old name move to the new one once; a value already saved under the new name wins.
function config.carryOverSettings(settings)
  for _, name in ipairs({ "choice", "position", "hidden" }) do
    local old, new = "ClaudePuppet." .. name, "Deskmates." .. name
    local value = settings.get(old)
    if value ~= nil then
      if settings.get(new) == nil then settings.set(new, value) end
      settings.clear(old)
    end
  end
end

return config
