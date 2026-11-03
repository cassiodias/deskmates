-- The programs each terminal is running, from `ps -axo tty=,comm=`: { ["/dev/ttys004"] = { codex = true, … } }.
-- Processes with no terminal are left out, so a terminal missing here runs nothing: its tab or window closed.
-- No output at all (ps failed) gives nil: unknown.

local Programs = {}

function Programs.parse(text)
  if not text or not text:find("%S") then return nil end
  local running = {}
  for name, command in text:gmatch("([^%s\n]+)[ \t]+([^\n]+)") do
    if name ~= "??" then
      local tty = "/dev/" .. name
      running[tty] = running[tty] or {}
      running[tty][command:match("([^/%s]+)%s*$") or command] = true
    end
  end
  return running
end

return Programs
