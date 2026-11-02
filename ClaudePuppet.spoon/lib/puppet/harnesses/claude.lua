-- Claude Code: the first harness, and the reference for the others (see docs/architecture.md, "Harnesses").
-- Its hook side is harnesses/claude/ at the repo root.

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
  -- The events this agent sends; a missing one only means that mood never shows.
  capabilities = {
    prompt = true, tools = true, toolFailure = true, subagents = true,
    permission = true, question = true, reply = true, sessionEnd = true,
  },
  -- Looks: the body it wears (render/sprites.lua's BODIES), and each session's puppet takes the first colour of
  -- this palette no other puppet wears.
  character = { body = "claude", palette = { "#D97757", "#5B8DEF", "#A06CD5", "#4FB286", "#E0A43B" } },
  -- What a tool means to the puppet: "reading", "question", "plan", "skill" (calls a command), "agent" (starts a
  -- subagent; its text is the subagent's description), or nil.
  toolKind = function(tool) return TOOL_KINDS[tool] end,
  -- A command-line agent: a click brings its terminal tab forward.
  focus = function(session, terminals) return terminals.focus(session) end,
}
