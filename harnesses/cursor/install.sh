#!/bin/sh
# Adds Deskmates' hooks to Cursor's hooks file, replacing any already there; keeps a backup. Cursor reads a
# hook's command as a path, relative ones from ~/.cursor/, so ours go in with the home spelled out.
here=$(dirname "$0")
. "$here/../../hook/install-lib.sh"
hooks=$("$here/config.sh")
need_jq || exit 1
if [ -f "$hooks" ]; then
  valid_json "$hooks" || exit 1
  backup "$hooks"
fi
snippet=$(mktemp) || exit 1
jq --arg home "$HOME" '.hooks[][].command |= sub("^~"; $home)' "$here/hooks.json" > "$snippet" &&
  hooks_merge "$hooks" "$snippet"
ok=$?
rm -f "$snippet"
[ "$ok" = 0 ] || exit 1
say "Cursor hooks in ~/.cursor/hooks.json (backups in ~/.cursor/hooks.json.bak and .last.bak)"
todo "start a new Cursor agent session (agent) to pick them up"
