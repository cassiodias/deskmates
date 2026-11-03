-- The programs each terminal is running, from `ps -axo tty=,comm=`: { ["/dev/ttys004"] = { codex = true, … } }.
-- Processes with no terminal are left out. Output with no terminal at all (ps failed) gives nil: unknown.

local Programs = {}

function Programs.parse(text)
  local running
  for name, command in (text or ""):gmatch("([^%s\n]+)[ \t]+([^\n]+)") do
    if name ~= "??" then
      local tty = "/dev/" .. name
      running = running or {}
      running[tty] = running[tty] or {}
      running[tty][command:match("([^/%s]+)%s*$") or command] = true
    end
  end
  return running
end

return Programs
