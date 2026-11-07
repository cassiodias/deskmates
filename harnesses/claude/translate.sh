#!/bin/sh
# Claude Code's hook payload into the puppet's event line. Claude Code's event names are the common
# vocabulary, so they pass through as they are.

. "$(dirname "$0")/../../hook/puppet-lib.sh"
. "$(dirname "$0")/../../hook/plan-lib.sh"
. "$(dirname "$0")/../../hook/facts-lib.sh"
puppet_read_payload

# Cursor runs Claude Code's hooks too, with its own payloads: its own harness writes those.
[ -n "$(field cursor_version)" ] && exit 0

# The session's title, as Claude Code last wrote it in the transcript at path $1; its lines repeat, so the
# end of the file is enough.
session_title() {
  [ -f "$1" ] || return 0
  tail -c 2000000 "$1" | grep '"type":"ai-title"' | tail -n 1 | json_value aiTitle
}

# A subagent's short description, from the file Claude Code keeps beside the transcript at path $1 for the
# subagent with id $2.
subagent_description() {
  meta="${1%.jsonl}/subagents/agent-$2.meta.json"
  [ -f "$meta" ] || return 0
  json_value description < "$meta"
}

event=$(field hook_event_name)
session=$(field session_id)
tool=$(field tool_name)
text=""
title=""
case "$event" in
  UserPromptSubmit) text=$(leading_command "$(field prompt)"); title=$(session_title "$(path_field transcript_path)") ;;
  Notification) text=$(field message) ;;
  Stop) text=$(first_sentence last_assistant_message); title=$(session_title "$(path_field transcript_path)") ;;
  SubagentStart) text=$(subagent_description "$(path_field transcript_path)" "$(field agent_id)") ;;
esac
[ "$tool" = "Skill" ] && text=$(field tool_input.skill)
case "$tool" in Agent|Task) text=$(field tool_input.description) ;; esac
flag=""
[ "$tool" = "Bash" ] && is_test_command "$(payload_value tool_input.command)" && flag="test"

# The plan (hook/plan-lib.sh): Claude Code's checklist (TodoWrite, or TaskCreate and TaskUpdate) and its plan
# document (ExitPlanMode, inline or in the plan file it names). One task list per session, subagents included.
PLAN_DEFS='def status: {"pending": "pending", "in_progress": "active", "completed": "done"}[. // ""] // "pending";
  def title: tostring | .[0:200];'
plan_change() {
  filter=$1
  shift
  plan_update "$session" claude "$PLAN_DEFS $filter" "$@" 2>/dev/null && flag="plan"
}
case "$event:$tool" in
  PreToolUse:TodoWrite)
    plan_change '. as $p | $cur | .steps = [($p.tool_input.todos // []) | to_entries[]
      | {id: (.key + 1 | tostring), title: (.value.content | title), status: (.value.status | status)}]' ;;
  PostToolUse:TaskCreate)
    # The new task's id: in the response ("Task #4 created successfully: …", or a task object); else the next
    # number, as Claude Code counts them: it never reuses the id of a task it deleted, so the plan keeps the
    # next one (nextId, only for this translator).
    plan_change '. as $p | ($cur.nextId // 1) as $next
      | ($p.tool_response
        | if type == "string" then (capture("#(?<id>[0-9]+)").id // null)
          elif type == "object" then (.task.id // .id // .taskId) else null end
        // ([$next, (([$cur.steps[].id | tonumber?] | max // 0) + 1)] | max) | tostring) as $id
      | $cur | .steps = [.steps[] | select(.id != $id)]
        + [{id: $id, title: ($p.tool_input.subject | title), status: "pending"}]
      | .nextId = ([$next, (($id | tonumber?) // 0) + 1] | max)' ;;
  PreToolUse:TaskUpdate)
    plan_change '. as $p | ($p.tool_input.taskId | tostring) as $id | $cur
      | if $p.tool_input.status == "deleted" then .steps = [.steps[] | select(.id != $id)]
        else .steps = [.steps[] | if .id == $id then
          (if $p.tool_input.status then .status = ($p.tool_input.status | status) else . end)
          | (if $p.tool_input.subject then .title = ($p.tool_input.subject | title) else . end)
          else . end] end' ;;
  PreToolUse:ExitPlanMode)
    plan_file_path=$(path_field tool_input.planFilePath)
    if [ -n "$plan_file_path" ] && [ -f "$plan_file_path" ]; then set -- --rawfile md "$plan_file_path"
    else set -- --arg md ""; fi
    plan_change '. as $p | ($p.tool_input.plan | if type == "string" and . != "" then . else $md end) as $m
      | if $m == "" then error("no plan") else $cur | .plan = {markdown: $m[0:100000], at: $now} end' "$@" ;;
  SessionEnd:*) plan_delete "$session"; facts_delete "$session" ;;
esac

# The session's facts (hook/facts-lib.sh): its tickets, their phases and Jira status, and a short timeline, from
# skills, subagents, Jira calls, test runs and replies. A test line keeps its test flag; the Spoon reads the
# facts again on both.
facts_change() {
  facts_note "$session" "$@" 2>/dev/null && [ "$flag" != test ] && flag="facts"
}
case "$event:$tool" in
  PreToolUse:Skill) facts_change "$FACTS_CLAUDE_DEFS claude_skill_note" ;;
  UserPromptSubmit:*)
    # A /command typed by the user runs a skill too: the ticket from what follows it, the phase from its name.
    [ -n "$text" ] && facts_change "$FACTS_CLAUDE_DEFS claude_command_note(\$c)" --arg c "${text#/}" ;;
  PreToolUse:Agent|PreToolUse:Task) facts_change "$FACTS_CLAUDE_DEFS claude_agent_note" ;;
  PostToolUse:mcp__*Jira*) facts_change "$FACTS_CLAUDE_DEFS claude_jira_note" ;;
  # You approved the plan: Plan has ended.
  PostToolUse:ExitPlanMode) facts_change "$FACTS_CLAUDE_DEFS claude_plan_note" ;;
  PostToolUse:*|PostToolUseFailure:*)
    if [ "$flag" = test ]; then
      result=passed
      [ "$event" = PostToolUseFailure ] && result=failed
      facts_change "$FACTS_CLAUDE_DEFS claude_tests_note(\$result)" --arg result "$result"
    fi ;;
  Stop:*)
    [ -n "$text" ] && facts_change "$FACTS_CLAUDE_DEFS claude_reply_note(\$reply)" --arg reply "$text" ;;
  SubagentStop:*)
    # A subagent's end ends the lane its description names: its last message's first sentence, and a verdict
    # only when it wrote one ("Verdict: CHANGES_REQUESTED").
    description=$(subagent_description "$(path_field transcript_path)" "$(field agent_id)")
    [ -n "$description" ] && facts_change "$FACTS_CLAUDE_DEFS claude_done_note(\$d; \$s)" \
      --arg d "$description" --arg s "$(first_sentence last_assistant_message)" ;;
esac

# The session's git facts (hook/facts-lib.sh): facts_track handles the repo, the turns and the test runs for every
# agent; here only what is Claude Code's: the edit tools and the path each names. A subagent's events count in the
# session's open turn. A turn's start or end sets the facts flag (facts_track says when); an edit sets none (the
# card reads the file when it opens).
cwd=$(path_field cwd)
# Adds the path an edit names to the session's facts.
edited() {
  [ -n "$1" ] && facts_edit "$session" "$cwd" "$1" 2>/dev/null
}
facts_track "$session" "$cwd" "$event" "$flag" yes && flag="facts"
if [ -n "$cwd" ] && [ "$event" != SessionEnd ]; then
  case "$event:$tool" in
    PostToolUse:Edit|PostToolUse:Write|PostToolUse:MultiEdit) edited "$(path_field tool_input.file_path)" ;;
    PostToolUse:NotebookEdit) edited "$(path_field tool_input.notebook_path)" ;;
  esac
fi

write_event claude "$event" "$session" "$(field agent_id)" "$tool" "$(field agent_type)" "$text" \
  "$(path_field cwd)" "$flag" "$title"
exit 0
