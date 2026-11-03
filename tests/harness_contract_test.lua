-- Every Spoon-side harness keeps this contract, and has a hook side with fixtures.

local root = arg[0]:match("^(.*)/tests/") or "."
package.path = root .. "/Deskmates.spoon/lib/?.lua;" .. root .. "/Deskmates.spoon/lib/?/init.lua;" .. package.path
local check = dofile(root .. "/tests/support/check.lua")
local harnesses = require("puppet.harnesses")

local CAPABILITIES = { "prompt", "tools", "toolFailure", "subagents", "permission", "question", "reply", "sessionEnd", "notification" }
local KINDS = { reading = true, question = true, plan = true, skill = true, agent = true }

for id, h in pairs(harnesses.all) do
  check(id .. ": id matches its registry key", h.id == id)
  check(id .. ": has a name", type(h.name) == "string" and h.name ~= "")
  for _, capability in ipairs(CAPABILITIES) do
    check(id .. ": says whether it has " .. capability, type(h.capabilities[capability]) == "boolean")
  end
  check(id .. ": has a palette", type(h.character.palette) == "table" and #h.character.palette > 0)
  check(id .. ": toolKind is a function", type(h.toolKind) == "function")
  local kind = h.toolKind("no-such-tool")
  check(id .. ": toolKind answers nil or a known kind", kind == nil or KINDS[kind])
  check(id .. ": focus is a function", type(h.focus) == "function")
  local translator = io.open(root .. "/harnesses/" .. id .. "/translate.sh", "r")
  check(id .. ": has harnesses/" .. id .. "/translate.sh", translator ~= nil)
  if translator then translator:close() end
  for _, script in ipairs({ "translate", "detect", "install", "uninstall" }) do
    local path = root .. "/harnesses/" .. id .. "/" .. script .. ".sh"
    check(id .. ": " .. script .. ".sh is executable", os.execute("test -x '" .. path .. "'"))
  end
  local hooks = io.open(root .. "/harnesses/" .. id .. "/hooks.json", "r")
  check(id .. ": has hooks.json", hooks ~= nil)
  if hooks then hooks:close() end
end
check("codex wears the owl", harnesses.get("codex").id == "codex" and harnesses.get("codex").character.body == "owl")
local codex = harnesses.get("codex")
check("codex: spawn_agent starts a subagent, update_plan is a plan",
  codex.toolKind("spawn_agent") == "agent" and codex.toolKind("collaborationspawn_agent") == "agent" and codex.toolKind("update_plan") == "plan")
check("codex: other tools mean nothing, so the wait is not a subagent", codex.toolKind("collaborationwait_agent") == nil and codex.toolKind("Bash") == nil)
check("unknown ids fall back to claude", harnesses.get("nope").id == "claude")

check.done("harness contract")
