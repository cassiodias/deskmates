#!/bin/sh
# Claude Code's hook payload into the puppet's event line. Claude Code's event names are the common
# vocabulary, so they pass through as they are.

. "$(dirname "$0")/../../hook/puppet-lib.sh"
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
[ "$tool" = "Bash" ] && is_test_command "$(field tool_input.command)" && flag="test"

write_event claude "$event" "$(field session_id)" "$(field agent_id)" "$tool" "$(field agent_type)" "$text" \
  "$(path_field cwd)" "$flag" "$title"
exit 0
