#!/bin/sh
# Removes Deskmates' hooks from Claude Code's hooks file (config.sh); keeps a backup.
here=$(dirname "$0")
. "$here/../../hook/install-lib.sh"
uninstall_hooks "Claude Code" "$("$here/config.sh")" || exit 1
