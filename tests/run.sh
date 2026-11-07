#!/bin/sh
# Runs every test: the Spoon's scenario snapshots, the harness fixtures and the installs. Needs Lua 5.4 (brew install lua@5.4) and jq.
set -e
cd "$(dirname "$0")/.."
LUA=$(command -v lua5.4 || command -v lua-5.4 || echo /opt/homebrew/opt/lua@5.4/bin/lua)
for test in tests/*_test.lua; do "$LUA" "$test"; done
# Each script runs through sh, so one that lost its executable bit still runs.
for test in puppet_lib plan_lib facts_lib backfill harnesses codex_tty cursor_turns install; do sh "tests/$test.sh"; done
exit 0
