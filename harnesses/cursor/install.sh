#!/bin/sh
# Adds Deskmates' hooks to Cursor's hooks file (config.sh), replacing any already there; keeps a backup.
# Cursor reads a hook's command as a path, relative ones from ~/.cursor/, so ours go in with the home spelled out.
here=$(dirname "$0")
. "$here/../../hook/install-lib.sh"
install_hooks "Cursor" "$("$here/config.sh")" "$here/hooks.json" \
  '.hooks[][].command |= sub("^~"; $home)' || exit 1
todo "start a new Cursor agent session (agent) to pick them up"
