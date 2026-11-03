#!/bin/sh
# Adds Deskmates' hooks to Claude Code's hooks file (config.sh), replacing any already there; keeps a backup.
here=$(dirname "$0")
. "$here/../../hook/install-lib.sh"
install_hooks "Claude Code" "$("$here/config.sh")" "$here/hooks.json" || exit 1
todo "start a new Claude Code session"
