#!/bin/sh
# Codex's hook payload into the puppet's event line. Codex uses Claude Code's event names, except that a
# failed tool arrives as a PostToolUse and an interrupt has no Stop after it.

. "$(dirname "$0")/../../hook/puppet-lib.sh"
puppet_read_payload

# The session's title, as Codex last named it in its session index (one JSON line per rename).
session_title() {
  [ -f "$HOME/.codex/session_index.jsonl" ] || return 0
  grep "\"id\":\"$1\"" "$HOME/.codex/session_index.jsonl" | tail -n 1 | json_value thread_name
}

event=$(field hook_event_name)
session=$(field session_id)
tool=$(field tool_name)
text=""
title=""
case "$event" in
  UserPromptSubmit) text=$(leading_command "$(field prompt)"); title=$(session_title "$session") ;;
  Stop) text=$(first_sentence last_assistant_message); title=$(session_title "$session"); echo '{}' ;;
  SubagentStop) echo '{}' ;;
  Interrupt) event=Stop; title=$(session_title "$session"); echo '{}' ;;
  PostToolUse)
    # A failed command's output starts "Exit code: N"; plain output is a success.
    case "$(field tool_response)" in
      "Exit code: 0"*) ;;
      "Exit code: "[0-9]*|"Exit code: -"[0-9]*) event=PostToolUseFailure ;;
    esac ;;
  PreToolUse|PermissionRequest|SubagentStart|SessionEnd) ;;
  *) exit 0 ;;
esac
# The subagent's message is encrypted; its task name says what it is for.
case "$tool" in collaborationspawn_agent|spawn_agent) text=$(field tool_input.task_name) ;; esac
flag=""
[ "$tool" = "Bash" ] && is_test_command "$(field tool_input.command)" && flag="test"

write_event codex "$event" "$session" "$(field agent_id)" "$tool" "$(field agent_type)" "$text" \
  "$(field cwd)" "$flag" "$title"
exit 0
