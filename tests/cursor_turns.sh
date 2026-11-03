#!/bin/sh
# Cursor sends a turn's reply (afterAgentResponse) before or after its stop, and two stops on Ctrl-C. Replays
# its fixtures in the orders seen live, in one home, and checks the lines the translator writes.
cd "$(dirname "$0")/.."
f=harnesses/cursor/fixtures
failed=0

# play name… : the events lines (without time) after feeding these fixtures in order to a fresh home.
play() {
  work=$(mktemp -d)
  for name in "$@"; do
    HOME="$work" PUPPET_NOW=0 PUPPET_TTY=/dev/ttys009 TERM_PROGRAM=iTerm.app harnesses/cursor/translate.sh \
      < "$f/$name.json" > /dev/null
  done
  cut -d'|' -f2,7 "$work/.deskmates/events" 2>/dev/null | tr '\n' ' '
  rm -rf "$work"
}

expect() {
  got=$(play $2)
  if [ "$got" != "$3" ]; then
    echo "cursor turns: $1"
    echo "  got      '$got'"
    echo "  expected '$3'"
    failed=1
  fi
}

expect "reply, then stop: one Stop with the reply" \
  "prompt reply-first stop-first" "UserPromptSubmit| Stop|Fixed the typo. "
expect "stop, then reply: the stop ends the turn, the reply then fills its bubble" \
  "prompt stop-first reply-first" "UserPromptSubmit| Stop| Stop|Fixed the typo. "
expect "Ctrl-C: aborted, then error: one Stop" \
  "prompt stop-aborted stop-error" "UserPromptSubmit| Stop| "
expect "a reply arriving once the next turn has started is dropped" \
  "prompt stop-first prompt-next reply-first" "UserPromptSubmit| Stop| UserPromptSubmit| "
expect "a prompt queued while a turn runs: that turn's reply still goes with its stop" \
  "prompt prompt-next reply-first stop-first" "UserPromptSubmit| UserPromptSubmit| Stop|Fixed the typo. "
expect "an error alone ends the turn" \
  "prompt stop-error" "UserPromptSubmit| Stop| "
expect "a subagent's own events stay out of the main session" \
  "prompt subagent-start subagent-own-tool subagent-own-result subagent-stop" \
  "UserPromptSubmit| SubagentStart|List the files SubagentStop| "
expect "after the session ends, nothing is left behind" \
  "prompt reply-first stop-aborted session-end" "UserPromptSubmit| Stop| SessionEnd| "

# Cursor's own chat runs the hooks with no terminal and no TERM_PROGRAM: its lines name the app Cursor.
work=$(mktemp -d)
app=$(env -u TERM_PROGRAM HOME="$work" PUPPET_NOW=0 PUPPET_TTY= harnesses/cursor/translate.sh < "$f/prompt.json" > /dev/null;
  cut -d'|' -f9 "$work/.deskmates/events")
if [ "$app" != "Cursor" ]; then
  echo "cursor turns: a prompt from Cursor's chat names app '$app', expected 'Cursor'"
  failed=1
fi
rm -rf "$work"

work=$(mktemp -d)
for name in prompt reply-first stop-first stop-aborted session-end; do
  HOME="$work" PUPPET_NOW=0 PUPPET_TTY=/dev/ttys009 harnesses/cursor/translate.sh < "$f/$name.json" > /dev/null
done
if ls "$work/.deskmates" | grep -q '^cursor-'; then
  echo "cursor turns: state left after SessionEnd: $(ls "$work/.deskmates" | grep '^cursor-' | tr '\n' ' ')"
  failed=1
fi
rm -rf "$work"

[ "$failed" = 0 ] && echo "cursor turns: ok"
exit "$failed"
