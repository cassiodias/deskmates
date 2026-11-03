#!/bin/sh
# Exits 0 when Codex is on this Mac.
[ -d "$HOME/.codex" ] || command -v codex > /dev/null 2>&1
