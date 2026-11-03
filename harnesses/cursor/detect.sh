#!/bin/sh
# Exits 0 when Cursor's CLI (or Cursor) is on this Mac.
[ -d "$HOME/.cursor" ] || command -v cursor-agent > /dev/null 2>&1
