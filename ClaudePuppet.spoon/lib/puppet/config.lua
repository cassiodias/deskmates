-- Sizes, timings and colours shared by every part of the Spoon.

return {
  W = 48, -- a puppet's drawing, in puppet pixels
  H = 24,
  STATUS_H = 3, -- the status line under the drawing
  FPS = 10,
  IDLE_SLEEP_SECONDS = 30,
  DONE_SECONDS = 8,
  STALE_SECONDS = 2 * 60 * 60,
  GAP = 12,
  CLICK_DISTANCE = 4,
  TABS_SECONDS = 3,
  POSITION_KEY = "ClaudePuppet.position",
  CHOICE_KEY = "ClaudePuppet.choice",
  HIDDEN_KEY = "ClaudePuppet.hidden",
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
  },
}
