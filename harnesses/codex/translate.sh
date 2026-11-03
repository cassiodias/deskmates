#!/bin/sh
# Codex's hook payload into the puppet's event line. Codex uses Claude Code's event names, except that a
# failed tool arrives as a PostToolUse and an interrupt has no Stop after it.

. "$(dirname "$0")/../../hook/puppet-lib.sh"
puppet_read_payload

# Codex runs hooks from a background process with no terminal: the terminal is the one of the codex process
# working in the session's folder.
puppet_tty_fallback() { tty_from_program codex; }

# A command's exit code, from the transcript's record of the call (the hook's result has only its output). Nothing
# without the call's id: every record would match an empty one.
exit_code() {
  [ -f "$1" ] && [ -n "$2" ] || return 0
  tail -c 2000000 "$1" | grep -F "\"id\":\"$2\"" | grep -o '"exit_code":-\{0,1\}[0-9]*' | tail -n 1 | cut -d: -f2
}

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
  Stop) respond '{}'; text=$(first_sentence last_assistant_message); title=$(session_title "$session") ;;
  SubagentStop) respond '{}' ;;
  Interrupt) respond '{}'; event=Stop; title=$(session_title "$session") ;;
  PostToolUse)
    # A failed command's output starts "Exit code: N"; plain output is a success.
    case "$(field tool_response)" in
      "Exit code: 0"*) ;;
      "Exit code: "[0-9]*|"Exit code: -"[0-9]*) event=PostToolUseFailure ;;
    esac
    if [ "$tool" = Bash ]; then
      code=$(exit_code "$(path_field transcript_path)" "$(field tool_use_id)")
      [ -n "$code" ] && [ "$code" != 0 ] && event=PostToolUseFailure
    fi ;;
  PreToolUse|PermissionRequest|SubagentStart|SessionEnd) ;;
  *) exit 0 ;;
esac
# The subagent's message is encrypted; its task name says what it is for.
case "$tool" in collaborationspawn_agent|spawn_agent) text=$(field tool_input.task_name) ;; esac
flag=""
[ "$tool" = "Bash" ] && is_test_command "$(payload_value tool_input.command)" && flag="test"

write_event codex "$event" "$session" "$(field agent_id)" "$tool" "$(field agent_type)" "$text" \
  "$(path_field cwd)" "$flag" "$title"
exit 0
