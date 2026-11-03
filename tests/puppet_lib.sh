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

# Text is cut by characters, never inside one, even when the hook runs with the C locale (a background process).
a119=$(printf '%119s' '' | tr ' ' a)
PUPPET_PAYLOAD="{\"message\":\"${a119}éèê\",\"last_assistant_message\":\"$(printf '%89s' '' | tr ' ' b)€€ more\"}"
expect "field cuts at 120 characters" "$(export LC_ALL=C; field message)" "${a119}é"
expect "first_sentence cuts at 90 characters" "$(export LC_ALL=C; first_sentence last_assistant_message)" \
  "$(printf '%89s' '' | tr ' ' b)€"
mkdir -p "$HOME/.deskmates"
(export LC_ALL=C PUPPET_NOW=0 PUPPET_TTY=; write_event claude Stop s1 "" "" "" "" "/Users/me/${a119}ü✓" "" "")
expect "the folder is cut at 120 characters" "$(LC_ALL=C cut -d'|' -f8 "$HOME/.deskmates/events")" "${a119}ü"

rm -rf "$HOME"
[ "$failed" = 0 ] && echo "puppet-lib: ok"
exit "$failed"
