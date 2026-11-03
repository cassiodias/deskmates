-- One look at what runs on this Mac, taken every few seconds, for Sessions:applyLiveness to judge which
-- sessions are still there. The same for every terminal app; iTerm, when it runs, only adds its tabs (for the
-- tab label under a puppet and for selecting a session's tab).
--   terminals  { [tty] = { [program] = true } }, from ps: every terminal something runs in. nil when ps failed.
--   apps       { [bundle id] = running? }, for each app a harness names in `apps`.
--   tabs       iTerm's { [tty] = { window, tab } } when iTerm runs and answered, else nil.

local Programs = require("puppet.terminals.programs")

local Liveness = {}

-- harnesses: the harness modules by id; iterm: terminals/iterm.lua's object, refreshed here.
function Liveness.look(harnesses, iterm)
  local apps = {}
  for _, harness in pairs(harnesses) do
    for _, bundle in pairs(harness.apps or {}) do apps[bundle] = hs.application.get(bundle) ~= nil end
  end
  local ps, ok = hs.execute("/bin/ps -axo tty=,comm=")
  return {
    terminals = ok and Programs.parse(ps) or nil,
    apps = apps,
    tabs = iterm:refresh() and iterm.tabs or nil,
  }
end

return Liveness
