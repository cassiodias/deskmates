#!/bin/sh
# The helpers in hook/puppet-lib.sh on their own: what a translator keeps from a payload, and what it drops.
cd "$(dirname "$0")/.." || exit 1
failed=0
HOME=$(mktemp -d) || exit 1
export HOME
. hook/puppet-lib.sh

expect() {
  if [ "$2" != "$3" ]; then
    echo "puppet-lib: $1"
    echo "  got      '$2'"
    echo "  expected '$3'"
    failed=1
  fi
}

# leading_command: a /command's name only, never a path or anything after it.
expect "a /command" "$(leading_command "/review the docs")" "/review"
expect "a /command alone" "$(leading_command "/my-coding-skill")" "/my-coding-skill"
expect "a plugin's /command" "$(leading_command "/plugin:do_it now")" "/plugin:do_it"
expect "a /command before a tab" "$(leading_command "/build	now")" "/build"
expect "no slash" "$(leading_command "review /build")" ""
expect "a path is not a command" "$(leading_command "/Users/me/my-app/notes.pdf summarise")" ""
expect "a path with a dot is not a command" "$(leading_command "/notes.pdf summarise")" ""
expect "a lone slash" "$(leading_command "/ hello")" ""

rm -rf "$HOME"
[ "$failed" = 0 ] && echo "puppet-lib: ok"
exit "$failed"
