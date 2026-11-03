-- Every Spoon-side harness keeps this contract, and has a hook side with fixtures.

local root = arg[0]:match("^(.*)/tests/") or "."
package.path = root .. "/Deskmates.spoon/lib/?.lua;" .. root .. "/Deskmates.spoon/lib/?/init.lua;" .. package.path
local check = dofile(root .. "/tests/support/check.lua")
local harnesses = require("puppet.harnesses")
local sprites = require("puppet.render.sprites")
local config = require("puppet.config")
local parse = require("puppet.events.parse")
local Sessions = require("puppet.model.sessions")
local Mapping = require("puppet.model.mapping")

local CAPABILITIES = { "prompt", "tools", "toolFailure", "subagents", "permission", "question", "reply", "sessionEnd", "notification" }
local KINDS = { reading = true, question = true, plan = true, skill = true, agent = true }

-- The event names the Spoon reads: Claude Code's, the common vocabulary every translator maps to.
local EVENTS = { UserPromptSubmit = true, PreToolUse = true, PostToolUse = true, PostToolUseFailure = true,
  PermissionRequest = true, SubagentStart = true, SubagentStop = true, Notification = true, Stop = true,
  SessionEnd = true }

-- What backs each capability: a fixture line it shows in.
local SHOWN_BY = {
  prompt = function(e) return e.name == "UserPromptSubmit" end,
  tools = function(e) return e.name == "PreToolUse" end,
  toolFailure = function(e) return e.name == "PostToolUseFailure" end,
  subagents = function(e) return e.name == "SubagentStart" and e.agentId ~= "" end,
  permission = function(e) return e.name == "PermissionRequest" end,
  question = function(e, h) return e.name == "PreToolUse" and h.toolKind(e.tool) == "question" end,
  reply = function(e) return e.name == "Stop" and e.text ~= "" end,
  sessionEnd = function(e) return e.name == "SessionEnd" end,
  notification = function(e) return e.name == "Notification" end,
}

local function lines(command)
  local out, pipe = {}, io.popen(command)
  for line in pipe:lines() do out[#out + 1] = line end
  pipe:close()
  return out
end

-- Every body has the four poses on the shared grid, in colours config.COLORS has.
for name, body in pairs(sprites.BODIES) do
  for _, pose in ipairs({ "SIDE", "SMILE", "FRONT", "FRONT_ASLEEP" }) do
    local rows = body[pose]
    check(name .. ": has " .. pose, type(rows) == "table")
    rows = rows or {}
    local tall
    if pose:match("^FRONT") then tall = #rows >= 1 and #rows <= 8 else tall = #rows == 9 end
    check(name .. ": " .. pose .. " is the right height", tall)
    for i, row in ipairs(rows) do
      check(name .. ": " .. pose .. " row " .. i .. " is 9 wide", #row == 9)
      for key in row:gmatch("[^.]") do
        check(name .. ": " .. pose .. " colour " .. key .. " is in config.COLORS", config.COLORS[key] ~= nil)
      end
    end
  end
end

for id, h in pairs(harnesses.all) do
  check(id .. ": id matches its registry key", h.id == id)
  check(id .. ": has a name", type(h.name) == "string" and h.name ~= "")
  for _, capability in ipairs(CAPABILITIES) do
    check(id .. ": says whether it has " .. capability, type(h.capabilities[capability]) == "boolean")
  end
  check(id .. ": wears a body sprites.lua has", sprites.BODIES[h.character.body] ~= nil)
  local names = type(h.program) == "table" and #h.program > 0
  for _, name in ipairs(type(h.program) == "table" and h.program or {}) do names = names and type(name) == "string" end
  check(id .. ": program is nil, a name or a list of names", h.program == nil or type(h.program) == "string" or names)
  check(id .. ": has a palette", type(h.character.palette) == "table" and #h.character.palette > 0)
  check(id .. ": toolKind is a function", type(h.toolKind) == "function")
  local kind = h.toolKind("no-such-tool")
  check(id .. ": toolKind answers nil or a known kind", kind == nil or KINDS[kind])
  check(id .. ": focus is a function", type(h.focus) == "function")
  local translator = io.open(root .. "/harnesses/" .. id .. "/translate.sh", "r")
  check(id .. ": has harnesses/" .. id .. "/translate.sh", translator ~= nil)
  if translator then translator:close() end
  for _, script in ipairs({ "translate", "detect", "config", "install", "uninstall" }) do
    local path = root .. "/harnesses/" .. id .. "/" .. script .. ".sh"
    check(id .. ": " .. script .. ".sh is executable", os.execute("test -x '" .. path .. "'"))
  end
  local hooks = io.open(root .. "/harnesses/" .. id .. "/hooks.json", "r")
  check(id .. ": has hooks.json", hooks ~= nil)
  if hooks then hooks:close() end

  -- Its fixtures: each line names this harness and a known event, and the Spoon takes the lot without error.
  local shown, events = {}, {}
  local sessions = Sessions.new(0)
  local ctx = { mapping = Mapping.new({ conversation = "auto" }), harness = h, frame = 1, now = 0 }
  for _, path in ipairs(lines("ls '" .. root .. "/harnesses/" .. id .. "/fixtures/'*.line 2>/dev/null")) do
    local file = io.open(path, "r")
    local line = file:read("l")
    file:close()
    if line and line ~= "" then
      local name = path:match("([^/]+)$")
      local e = parse.line("0|" .. line)
      check(id .. ": " .. name .. " parses", e ~= nil)
      if e then
        check(id .. ": " .. name .. " names harness " .. id, line:match("|([^|]*)|[^|]*$") == id)
        check(id .. ": " .. name .. " is a known event, not " .. e.name, EVENTS[e.name])
        events[e.name] = true
        for capability, test in pairs(SHOWN_BY) do
          if test(e, h) then shown[capability] = true end
        end
        check(id .. ": the Spoon takes " .. name, pcall(sessions.apply, sessions, e, ctx))
      end
    end
  end
  -- Without Stop the puppet never finishes a turn.
  check(id .. ": a fixture sends Stop", events.Stop)
  for capability, test in pairs(SHOWN_BY) do
    if h.capabilities[capability] then
      check(id .. ": capability " .. capability .. " has a fixture that shows it", shown[capability])
    end
  end
end
check("codex wears the owl", harnesses.get("codex").id == "codex" and harnesses.get("codex").character.body == "owl")
local codex = harnesses.get("codex")
check("codex: spawn_agent starts a subagent, update_plan is a plan",
  codex.toolKind("spawn_agent") == "agent" and codex.toolKind("collaborationspawn_agent") == "agent" and codex.toolKind("update_plan") == "plan")
check("codex: other tools mean nothing, so the wait is not a subagent", codex.toolKind("collaborationwait_agent") == nil and codex.toolKind("Bash") == nil)
local cursor = harnesses.get("cursor")
check("cursor wears the rabbit", cursor.id == "cursor" and cursor.character.body == "rabbit")
check("cursor: Task starts a subagent, Read reads", cursor.toolKind("Task") == "agent" and cursor.toolKind("Read") == "reading")
check("cursor: its sessions run agent or cursor-agent",
  type(cursor.program) == "table" and cursor.program[1] == "agent" and cursor.program[2] == "cursor-agent")
-- A click: the session's terminal; in Cursor's own terminal (TERM_PROGRAM=vscode), Cursor's window.
local asked = {}
local fake = {
  focus = function(s) asked[#asked + 1] = "focus " .. s.app end,
  app = function(bundle, folder) asked[#asked + 1] = bundle .. " " .. folder end,
}
cursor.focus({ app = "iTerm.app", folder = "my-app" }, fake)
cursor.focus({ app = "vscode", folder = "my-app" }, fake)
check("cursor: a click brings its terminal forward, or Cursor itself",
  asked[1] == "focus iTerm.app" and asked[2] == "com.todesktop.230313mzl4w4u92 my-app")
check("unknown ids fall back to claude", harnesses.get("nope").id == "claude")

check.done("harness contract")
