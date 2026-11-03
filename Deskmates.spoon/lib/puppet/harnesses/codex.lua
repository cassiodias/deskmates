-- Codex: an owl in teal. Its hook side is harnesses/codex/ at the repo root.

-- Codex reads files through Bash and has no question tool, so only planning and subagents have a kind.
local TOOL_KINDS = {
  update_plan = "plan",
  spawn_agent = "agent", collaborationspawn_agent = "agent",
}

return {
  id = "codex",
  name = "Codex",
  capabilities = {
    prompt = true, tools = true, toolFailure = true, subagents = true,
    permission = true, question = false, reply = true, sessionEnd = true,
    notification = false,
  },
  character = { body = "owl", palette = { "#2BB3A3", "#1F8A80", "#5FD4C4", "#147A8C", "#7FE0D0" } },
  toolKind = function(tool) return TOOL_KINDS[tool] end,
  -- The program its sessions run in their terminal. Codex says a session ended only later, so the session ends
  -- when its terminal stops running codex.
  program = "codex",
  -- A command-line agent: a click brings its terminal tab forward.
  focus = function(session, terminals) return terminals.focus(session) end,
}
