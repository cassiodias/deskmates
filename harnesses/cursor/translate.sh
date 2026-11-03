#!/bin/sh
# Cursor CLI's hook payload into the puppet's event line. Cursor has its own event names (camelCase), no
# subagent events (a subagent is a Task tool call), and sends a turn's reply on its own event, before or after
# the turn's stop. It waits for no answer: a hook that prints nothing lets everything through.

. "$(dirname "$0")/../../hook/puppet-lib.sh"
puppet_read_payload

event=$(field hook_event_name)
session=$(field session_id)
tool=$(field tool_name)
state="$PUPPET_DIR/cursor-$session"

# The session's title, as Cursor named it in the chat's meta.json (~/.cursor/chats/<md5 of folder>/<id>/).
session_title() {
  for meta in "$HOME"/.cursor/chats/*/"$session"/meta.json; do
    [ -f "$meta" ] && json_value title < "$meta"
    return 0
  done
}

# A subagent's own events come with its own session id, which is also its generation id; the main session's
# turn events have a generation id of their own. Its transcript sits under the parent's subagents/ folder.
case "$event" in sessionStart|sessionEnd) ;; *)
  [ "$(field generation_id)" = "$session" ] && exit 0
  case "$(path_field transcript_path)" in */subagents/*) exit 0 ;; esac ;;
esac

text=""
title=""
agent_id=""
agent_type=""
case "$event" in
  beforeSubmitPrompt)
    # A new turn: a stop still waiting for its reply belongs to the turn before.
    rm -f "$state.stopped" "$state.aborted"
    event=UserPromptSubmit; text=$(leading_command "$(field prompt)"); title=$(session_title) ;;
  preToolUse) event=PreToolUse ;;
  postToolUse) event=PostToolUse ;;
  postToolUseFailure) event=PostToolUseFailure ;;
  afterAgentResponse)
    reply=$(first_sentence text)
    if [ -f "$state.stopped" ]; then
      rm -f "$state.stopped"
      event=Stop; text=$reply; title=$(session_title)
    else
      mkdir -p "$PUPPET_DIR" && printf '%s' "$reply" > "$state.reply"
      exit 0
    fi ;;
  stop)
    case "$(field status)" in
      completed)
        # The reply may come after the stop: the stop then waits for it.
        if [ ! -f "$state.reply" ]; then
          mkdir -p "$PUPPET_DIR" && : > "$state.stopped"
          exit 0
        fi
        text=$(cat "$state.reply") ;;
      aborted)
        # Ctrl-C: an "error" stop follows this one.
        mkdir -p "$PUPPET_DIR" && : > "$state.aborted" ;;
      *)
        if [ -f "$state.aborted" ]; then
          rm -f "$state.aborted"
          exit 0
        fi ;;
    esac
    rm -f "$state.reply" "$state.stopped"
    event=Stop; title=$(session_title) ;;
  sessionEnd) event=SessionEnd; rm -f "$state".* ;;
  *) exit 0 ;;
esac

# A subagent is a Task call: its start and its result frame it, by the call's id.
if [ "$tool" = Task ]; then
  agent_id=$(field tool_use_id); agent_type=$(field tool_input.subagent_type)
  case "$event" in
    PreToolUse) event=SubagentStart; text=$(field tool_input.description) ;;
    *) event=SubagentStop ;;
  esac
fi
flag=""
[ "$tool" = Shell ] && is_test_command "$(field tool_input.command)" && flag="test"

write_event cursor "$event" "$session" "$agent_id" "$tool" "$agent_type" "$text" \
  "$(path_field workspace_roots.0)" "$flag" "$title"
exit 0
