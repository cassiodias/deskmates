#!/bin/sh
# Cursor CLI's hook payload into the puppet's event line. Cursor has its own event names (camelCase), no
# subagent events (a subagent is a Task tool call), and sends a turn's reply on its own event, before or after
# the turn's stop. It waits for no answer: a hook that prints nothing lets everything through.

. "$(dirname "$0")/../../hook/puppet-lib.sh"
. "$(dirname "$0")/../../hook/plan-lib.sh"
. "$(dirname "$0")/../../hook/facts-lib.sh"
puppet_read_payload
puppet_exit_if_off

# Its CLI runs as agent or cursor-agent: a terminal remembered for a session counts while it runs one of them.
puppet_program agent cursor-agent

event=$(field hook_event_name)
session=$(field session_id)
tool=$(field tool_name)
# A turn's prompt, tools, reply and stop share a generation id. What one of its events leaves for another is
# kept in ~/.deskmates/cursor-<session>.<generation>.<what>; cursor-<session>.turn holds the latest turn's id.
turn=$(field generation_id)
state="$PUPPET_DIR/cursor-$session"
mkdir -p "$PUPPET_DIR"

# The session's title, as Cursor named it in the chat's meta.json (~/.cursor/chats/<md5 of folder>/<id>/).
session_title() {
  for meta in "$HOME"/.cursor/chats/*/"$session"/meta.json; do
    [ -f "$meta" ] && json_value title < "$meta"
    return 0
  done
}

# A subagent's own events come with its own session id, which is also its generation id; the main session's
# turn events have a generation id of their own. Its transcript sits under the parent's subagents/ folder.
case "$event" in sessionEnd) ;; *)
  [ "$turn" = "$session" ] && exit 0
  case "$(path_field transcript_path)" in */subagents/*) exit 0 ;; esac ;;
esac

# The session's git facts (hook/facts-lib.sh): facts_track handles the repo, the turns and the test runs for every
# agent; here only what is Cursor's. Cursor's postToolUseFailure is a real failure, so its exit codes count. A
# turn's start or end sets the facts flag (facts_track says when). track $1: what the common event $1 does.
folder=$(path_field workspace_roots.0)
flag=""
track() {
  facts_track "$session" "$folder" "$1" "$flag" yes && flag="facts"
}
hook=$event

text=""
title=""
agent_id=""
agent_type=""
case "$event" in
  beforeSubmitPrompt)
    printf '%s' "$turn" > "$state.turn"
    event=UserPromptSubmit; text=$(leading_command "$(field prompt)"); title=$(session_title) ;;
  preToolUse) event=PreToolUse ;;
  postToolUse) event=PostToolUse ;;
  postToolUseFailure) event=PostToolUseFailure ;;
  afterAgentResponse)
    # Cursor joins the reply's parts without a space ("Listed them.Quick look next", "Which one?the app"): cut
    # there too, at a "?" or "!" right before a letter, or a "." right before a capital.
    reply=$(first_sentence text | sed -e 's/\([[:alnum:]][!?]\)[[:alpha:]].*/\1/' -e 's/\([[:alnum:]]\.\)[A-Z].*/\1/')
    if [ ! -f "$state.$turn.stopped" ]; then
      # Before its stop: the stop says it.
      printf '%s' "$reply" > "$state.$turn.reply"
      exit 0
    fi
    rm -f "$state.$turn.stopped"
    # After its stop, which already ended the turn: the reply fills that turn's bubble, unless the next turn
    # has started.
    [ -f "$state.turn" ] && [ "$(cat "$state.turn")" != "$turn" ] && exit 0
    event=Stop; text=$reply; title=$(session_title) ;;
  afterFileEdit)
    # Cursor's own edit event duplicates postToolUse: no line, only the path (its content and edits hold the
    # file, and are never read).
    facts_edit "$session" "$folder" "$(path_field file_path)" 2>/dev/null
    exit 0 ;;
  stop)
    # Whatever its status, the first stop of a turn ends it, before any of the exits below (a second "error"
    # stop finds no open turn and does nothing). The stop alone ends it: a reply after it changes nothing.
    track Stop
    case "$(field status)" in
      completed)
        if [ -f "$state.$turn.reply" ]; then
          text=$(cat "$state.$turn.reply")
          rm -f "$state.$turn.reply"
        else
          : > "$state.$turn.stopped"
        fi ;;
      aborted)
        # Ctrl-C: an "error" stop follows this one.
        : > "$state.$turn.aborted" ;;
      *)
        if [ -f "$state.$turn.aborted" ]; then
          rm -f "$state.$turn.aborted"
          exit 0
        fi ;;
    esac
    event=Stop; title=$(session_title) ;;
  sessionEnd) event=SessionEnd; rm -f "$state".*; facts_delete "$session" ;;
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
# Cursor's own chat runs the hooks with no terminal: the line names the app, so its rabbit waits at its desk
# (a session with no terminal and no app to watch counts as a background one, which leaves once it rests).
puppet_app Cursor
[ "$tool" = Shell ] && is_test_command "$(payload_value tool_input.command)" && flag="test"
case "$hook" in stop|afterAgentResponse) ;; *) track "$event" ;; esac

write_event cursor "$event" "$session" "$agent_id" "$tool" "$agent_type" "$text" \
  "$folder" "$flag" "$title"
exit 0
