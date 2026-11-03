#!/bin/sh
# Adds Deskmates' hooks to Codex's hooks file, replacing any already there; keeps a backup.
here=$(dirname "$0")
. "$here/../../hook/install-lib.sh"
hooks=$("$here/config.sh")
need_jq || exit 1
if [ -f "$hooks" ]; then
  valid_json "$hooks" || exit 1
  backup "$hooks"
fi
hooks_merge "$hooks" "$here/hooks.json" || exit 1
say "Codex hooks in ~/.codex/hooks.json (backup in ~/.codex/hooks.json.bak)"
todo "open codex, type /hooks and trust the Deskmates hooks"
