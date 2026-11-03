-- The programs each terminal is running, from `ps -axo tty=,comm=`: { ["/dev/ttys004"] = { codex = true, … } }.
-- Processes with no terminal are left out.

local Programs = {}

function Programs.parse(text)
  local running = {}
  for name, command in (text or ""):gmatch("(%S+)%s+([^\n]+)") do
    if name ~= "??" then
      local tty = "/dev/" .. name
      running[tty] = running[tty] or {}
      running[tty][command:match("([^/%s]+)%s*$") or command] = true
    end
  end
  return running
end

return Programs
