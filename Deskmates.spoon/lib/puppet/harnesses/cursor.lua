-- Cursor's command-line agent: a rabbit in lavender. Its hook side is harnesses/cursor/ at the repo root.

-- Cursor's question tool never reaches its hooks, so only reading and subagents have a kind.
local TOOL_KINDS = {
  Read = "reading",
  Task = "agent",
}

-- Cursor's own app, for a session started in its built-in terminal.
local CURSOR_APP = "com.todesktop.230313mzl4w4u92"

return {
  id = "cursor",
  name = "Cursor",
  capabilities = {
    prompt = true, tools = true, toolFailure = true, subagents = true,
    permission = false, question = false, reply = true, sessionEnd = true,
    notification = false,
  },
  character = { body = "rabbit", palette = { "#A99BD6", "#8C7FC0", "#C3B6EA", "#6F63A8", "#B7A6E0" } },
  toolKind = function(tool) return TOOL_KINDS[tool] end,
  -- The CLI runs as agent or cursor-agent, by the name it was started with. Ends a session whose tab quit it.
  program = { "agent", "cursor-agent" },
  -- A click brings its terminal forward. In Cursor's own terminal TERM_PROGRAM is "vscode", like VS Code's: a
  -- Cursor session there is in Cursor, so Cursor comes forward.
  focus = function(session, terminals)
    if session.app == "vscode" then return terminals.app(CURSOR_APP, session.folder) end
    return terminals.focus(session)
  end,
}
