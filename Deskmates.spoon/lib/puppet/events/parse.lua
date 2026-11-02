-- One line of the events file into an event. The line format lives here and in hook/puppet-lib.sh only:
-- time|event|session|agent id|tool|agent type|text|folder|terminal app|flag|tty|harness|title
-- A line without the 12th field was written before harnesses existed, so it is Claude Code's.

local parse = {}

function parse.line(line)
  local f = {}
  for value in (line .. "|"):gmatch("([^|]*)|") do f[#f + 1] = value end
  if not f[2] or f[2] == "" or not f[3] or f[3] == "" then return nil end
  return {
    at = tonumber(f[1]),
    name = f[2],
    session = f[3],
    agentId = f[4] or "",
    tool = f[5] or "",
    agentType = f[6] or "",
    text = f[7] or "",
    folder = f[8] or "",
    app = f[9] or "",
    flag = f[10] or "",
    tty = f[11] or "",
    harness = (f[12] and f[12] ~= "") and f[12] or "claude",
    title = f[13] or "",
  }
end

return parse
