-- The harnesses the Spoon knows, by the id each writes on its event lines. Adding an agent is one module next
-- to claude.lua, one line here, and its hook side under harnesses/<id>/ at the repo root.

local harnesses = {
  claude = require("puppet.harnesses.claude"),
}

return {
  all = harnesses,
  -- The harness for an id; lines from before harnesses existed are Claude Code's.
  get = function(id) return harnesses[id] or harnesses.claude end,
}
