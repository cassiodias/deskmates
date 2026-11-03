#!/bin/sh
# Removes Deskmates' hooks from Claude Code's user settings; keeps a backup.
here=$(dirname "$0")
. "$here/../../hook/install-lib.sh"
settings=$("$here/config.sh")
need_jq || exit 1
[ -f "$settings" ] && { valid_json "$settings" || exit 1; }
if ! hooks_present "$settings"; then
  say "no Deskmates hooks in ~/.claude/settings.json"
  exit 0
fi
backup "$settings"
hooks_remove "$settings" || exit 1
say "Claude Code hooks removed from ~/.claude/settings.json (backups in ~/.claude/settings.json.bak and .last.bak)"
