#!/bin/sh
# Removes Deskmates' hooks from Claude Code's user settings; keeps a backup.
. "$(dirname "$0")/../../hook/install-lib.sh"
settings="$HOME/.claude/settings.json"
need_jq || exit 1
[ -f "$settings" ] && { valid_json "$settings" || exit 1; }
if ! hooks_present "$settings"; then
  say "no Deskmates hooks in ~/.claude/settings.json"
  exit 0
fi
backup "$settings"
hooks_remove "$settings" || exit 1
say "Claude Code hooks removed from ~/.claude/settings.json (backup in ~/.claude/settings.json.bak)"
