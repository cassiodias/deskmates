#!/bin/sh
# Removes Deskmates' hooks from Cursor's hooks file (config.sh); keeps a backup.
here=$(dirname "$0")
. "$here/../../hook/install-lib.sh"
uninstall_hooks "Cursor" "$("$here/config.sh")" || exit 1
