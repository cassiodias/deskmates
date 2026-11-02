#!/bin/sh
# Exits 0 when Claude Code is on this Mac.
[ -d "$HOME/.claude" ] || command -v claude > /dev/null 2>&1
