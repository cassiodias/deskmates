#!/bin/sh
# Adds Deskmates' hooks to Codex's hooks file (config.sh), replacing any already there; keeps a backup.
here=$(dirname "$0")
. "$here/../../hook/install-lib.sh"
install_hooks "Codex" "$("$here/config.sh")" "$here/hooks.json" || exit 1
todo "open codex, type /hooks and trust the Deskmates hooks"
