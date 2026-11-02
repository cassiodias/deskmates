#!/bin/sh
# Refreshes the README's screenshots in docs/images: stages each scene on a scratch events file (your real
# sessions and menu choice are left alone, and come back at the end) and saves what the puppets draw.
# Needs Hammerspoon running this Spoon with hs.ipc loaded (require("hs.ipc") in ~/.hammerspoon/init.lua).
# Usage: tools/screenshots/shoot.sh
cd "$(dirname "$0")/../.." || exit 1
S=$(pwd)/tools/screenshots
OUT=$(pwd)/docs/images
EV=$(mktemp -t puppet-events)

hsq() { perl -e 'alarm 20; exec @ARGV' hs -c "$1"; }
D="local D=dofile('$S/stage.lua')"
wait() { perl -e "select(undef,undef,undef,$1)"; }
# ev <seconds ago> <event> <session> <agent> <tool> <agent type> <text> <tty> [title]
ev() {
  echo "$(( $(date +%s) - $1 ))|$2|$3|$4|$5|$6|$7|shop-api|iTerm.app||/dev/ttys$8|claude|$9" >> "$EV"
}
fresh() { : > "$EV"; hsq "$D; return D.begin('$EV')"; wait 1; }
snap() { wait "${2:-0.4}"; hsq "$D; return D.snap('$OUT/$1.png')"; }
smile() {
  # Waits for the moment the puppets turn to smile (frames 68-79 of every 80).
  i=0
  while [ $i -lt 100 ]; do
    f=$(hsq 'return spoon.ClaudePuppet.frame % 80')
    [ "$f" -ge 70 ] && [ "$f" -le 75 ] && break
    wait 0.1; i=$((i + 1))
  done
}

# Coding: one puppet at its laptop, an invader hit.
fresh
ev 900 UserPromptSubmit s1 "" "" "" "/my-coding-skill" 101
for i in 1 2 3 4 5 6 7 8 9 10 11; do ev 0 PreToolUse s1 "" Edit "" "" 101; done
snap coding 0.3

# Matrix.
fresh
ev 600 UserPromptSubmit s1 "" "" "" "/my-planner" 101
for i in 1 2 3 4 5 6; do ev 0 PreToolUse s1 "" Edit "" "" 101; done
snap planning 1.5

# Ping pong.
fresh
ev 300 UserPromptSubmit s1 "" "" "" "/my-reviewer" 101 "PR 12 review"
ev 300 PreToolUse s1 "" Agent "" "Check the contract" 101
ev 300 PreToolUse s1 "" Agent "" "Try to break it" 101
ev 300 SubagentStart s1 a1 "" general-purpose "" 101
ev 300 SubagentStart s1 a2 "" general-purpose "" 101
for i in 1 2 3 4 5; do ev 0 PreToolUse s1 a1 Read "" "" 101; ev 0 PreToolUse s1 a2 Bash "" "" 101; done
ev 0 PreToolUse s1 a2 Bash "" "" 101
snap ping-pong 0.6

# Thinking and smiling: left smiles at you, right has just been given a prompt.
fresh
ev 1200 UserPromptSubmit s1 "" "" "" "/my-coding-skill" 101
ev 1200 PreToolUse s1 "" Edit "" "" 101
ev 0 UserPromptSubmit s2 "" "" "" "/my-coding-skill" 102
wait 0.5; smile; snap coding-smiling-thinking 0

# Happy: two puppets smiling.
fresh
ev 1200 UserPromptSubmit s1 "" "" "" "/my-coding-skill" 101
ev 1200 PreToolUse s1 "" Edit "" "" 101
ev 600 UserPromptSubmit s2 "" "" "" "/my-planner" 102
ev 600 PreToolUse s2 "" Edit "" "" 102
wait 0.5; smile; snap dev-planner-happy 0

# Coder and Matrix side by side, the Matrix one just given a prompt.
fresh
ev 1200 UserPromptSubmit s1 "" "" "" "/my-coding-skill" 101
for i in 1 2 3 4 5 6 7; do ev 0 PreToolUse s1 "" Edit "" "" 101; done
ev 0 UserPromptSubmit s2 "" "" "" "/my-planner" 102
snap coding-planning 0.3

# Waiting for you: a coder, and a resting puppet with Claude's notification.
fresh
ev 1800 UserPromptSubmit s1 "" "" "" "/my-coding-skill" 101
for i in 1 2 3 4 5 6 7 8 9; do ev 0 PreToolUse s1 "" Edit "" "" 101; done
ev 900 UserPromptSubmit s2 "" "" "" "" 102
ev 840 Stop s2 "" "" "" "Added the retry." 102
wait 1
ev 0 Notification s2 "" "" "" "Claude is waiting for your input" 102
snap coding-waiting 0.5

# Permission.
fresh
ev 120 UserPromptSubmit s1 "" "" "" "/my-coding-skill" 101
ev 0 PermissionRequest s1 "" Bash "" "" 101
snap bash-may-I-use-bash 0.5

# Question.
fresh
ev 120 UserPromptSubmit s1 "" "" "" "/my-coding-skill" 101
ev 0 PreToolUse s1 "" AskUserQuestion "" "" 101
snap question 0.5

# Done: the first sentence of the answer.
fresh
ev 600 UserPromptSubmit s1 "" "" "" "/my-coding-skill" 101
ev 0 Stop s1 "" "" "" "Fixed the parser and added two tests." 101
snap response-coder 0.5

# Several sessions: Matrix, ping pong and coding.
fresh
ev 1500 UserPromptSubmit s1 "" "" "" "/my-planner" 101
for i in 1 2 3 4 5; do ev 0 PreToolUse s1 "" Edit "" "" 101; done
ev 900 UserPromptSubmit s2 "" "" "" "/my-reviewer" 102
ev 900 PreToolUse s2 "" Agent "" "Check the contract" 102
ev 900 PreToolUse s2 "" Agent "" "Try to break it" 102
ev 900 SubagentStart s2 a1 "" general-purpose "" 102
ev 900 SubagentStart s2 a2 "" general-purpose "" 102
for i in 1 2 3; do ev 0 PreToolUse s2 a1 Read "" "" 102; ev 0 PreToolUse s2 a2 Bash "" "" 102; done
ev 300 UserPromptSubmit s3 "" "" "" "/my-coding-skill" 103
for i in 1 2 3 4 5 6 7 8; do ev 0 PreToolUse s3 "" Edit "" "" 103; done
snap planner-reviewer-ping-pong-coding 1.2

# All done.
fresh
for n in 1 2 3; do ev 600 UserPromptSubmit s$n "" "" "" "" 10$n; done
for n in 1 2 3; do ev 0 Stop s$n "" "" "" "" 10$n; done
snap 3-desk-done 0.5

# Between turns: three puppets dozing.
fresh
for n in 1 2 3; do ev 1200 UserPromptSubmit s$n "" "" "" "" 10$n; ev 300 Stop s$n "" "" "" "Done." 10$n; done
snap 3-desks-sleeping 9

# The card: the mouse rests on a puppet whose subagents work.
fresh
ev 1900 UserPromptSubmit s1 "" "" "" "/my-reviewer" 101 "Shop-api PR 12 review"
ev 1900 PreToolUse s1 "" Agent "" "Check the contract" 101
ev 1900 PreToolUse s1 "" Agent "" "Try to break it" 101
ev 1900 SubagentStart s1 a1 "" general-purpose "" 101
ev 1900 SubagentStart s1 a2 "" general-purpose "" 101
for i in 1 2 3 4 5 6; do ev 30 PreToolUse s1 a1 Read "" "" 101; ev 30 PreToolUse s1 a2 Bash "" "" 101; done
wait 0.6; hsq "$D; return D.hover('s1')"; snap hover-card 0.6

# Nothing running: the home puppet.
fresh
snap big-desk 0.5

hsq "$D; return D.finish()"
hsq "return dofile('$S/bodies.lua')('$OUT/bodies.png')"
rm -f "$EV"
