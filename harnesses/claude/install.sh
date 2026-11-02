#!/bin/sh
# Adds Deskmates' hooks to Claude Code's user settings, replacing any already there; keeps a backup.
here=$(dirname "$0")
. "$here/../../hook/install-lib.sh"
settings=$("$here/config.sh")
need_jq || exit 1
if [ -f "$settings" ]; then
  valid_json "$settings" || exit 1
  backup "$settings"
fi
hooks_merge "$settings" "$here/hooks.json" || exit 1
say "Claude Code hooks in ~/.claude/settings.json (backup in ~/.claude/settings.json.bak)"
todo "start a new Claude Code session"
