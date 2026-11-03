#!/bin/sh
# Runs every test: the Spoon's scenario snapshots, the harness fixtures and the installs. Needs Lua 5.4 (brew install lua@5.4) and jq.
set -e
cd "$(dirname "$0")/.."
LUA=$(command -v lua5.4 || command -v lua-5.4 || echo /opt/homebrew/opt/lua@5.4/bin/lua)
for test in tests/*_test.lua; do "$LUA" "$test"; done
[ -x tests/harnesses.sh ] && tests/harnesses.sh
[ -x tests/codex_tty.sh ] && tests/codex_tty.sh
[ -x tests/cursor_turns.sh ] && tests/cursor_turns.sh
[ -x tests/install.sh ] && tests/install.sh
exit 0
