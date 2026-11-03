-- Claude Code's harness, and the reference for the others (a harness is one module like this, one line in
-- harnesses/init.lua, and a hook side). Its hook side is harnesses/claude/ at the repo root.

local TOOL_KINDS = {
  Read = "reading", Grep = "reading", Glob = "reading", LSP = "reading", WebFetch = "reading", WebSearch = "reading",
  AskUserQuestion = "question",
  ExitPlanMode = "plan",
  Skill = "skill",
  Agent = "agent", Task = "agent",
}

return {
  id = "claude",
  name = "Claude",
  -- What this agent's hooks report, for people reading the code and the README's agents table; the contract test
  -- checks each true one against a fixture (prompt: UserPromptSubmit, tools: PreToolUse, toolFailure:
  -- PostToolUseFailure, subagents: SubagentStart, permission: PermissionRequest, question: a "question" tool,
  -- reply: Stop with text, sessionEnd: SessionEnd, notification: Notification). A false one means that mood
  -- never shows.
  capabilities = {
    prompt = true, tools = true, toolFailure = true, subagents = true,
    permission = true, question = true, reply = true, sessionEnd = true,
    notification = true,
  },
  -- Looks: the body it wears (render/sprites.lua's BODIES), and each session's puppet takes the first colour of
  -- this palette no other puppet wears.
  character = { body = "claude", palette = { "#D97757", "#5B8DEF", "#A06CD5", "#4FB286", "#E0A43B" } },
  -- What a tool means to the puppet: "reading", "question", "plan", "skill" (calls a command), "agent" (starts a
  -- subagent; its text is the subagent's description), or nil.
  toolKind = function(tool) return TOOL_KINDS[tool] end,
  -- Optional: program = "name" or { "name", … }, the program its sessions run in their terminal (`ps -o comm`'s
  -- last part). A session then ends once its terminal no longer runs it; for agents that report the end late.
  -- Optional: apps = { [app on its lines] = bundle id }, the apps its sessions run inside with no terminal. Such a
  -- session ends once its app no longer runs; for agents whose app says nothing when it quits (Cursor's chat).
  -- A click on the puppet. A command-line agent brings its terminal tab forward; an agent that runs in its own
  -- app would call terminals.app(bundleId, session.folder) instead (terminals/focus.lua).
  focus = function(session, terminals) return terminals.focus(session) end,
}
