#!/bin/sh
# Removes Deskmates' hooks from Codex's hooks file (config.sh); keeps a backup.
here=$(dirname "$0")
. "$here/../../hook/install-lib.sh"
uninstall_hooks "Codex" "$("$here/config.sh")" || exit 1
