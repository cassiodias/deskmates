#!/bin/sh
# Removes Deskmates' hooks from Cursor's hooks file; keeps a backup.
here=$(dirname "$0")
. "$here/../../hook/install-lib.sh"
hooks=$("$here/config.sh")
need_jq || exit 1
[ -f "$hooks" ] && { valid_json "$hooks" || exit 1; }
if ! hooks_present "$hooks"; then
  say "no Deskmates hooks in ~/.cursor/hooks.json"
  exit 0
fi
backup "$hooks"
hooks_remove "$hooks" || exit 1
say "Cursor hooks removed from ~/.cursor/hooks.json (backups in ~/.cursor/hooks.json.bak and .last.bak)"
