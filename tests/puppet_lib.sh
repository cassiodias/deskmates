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

# The payload is parsed once per event: with jq, no plutil runs for each field, and a 5 MB tool result keeps
# the agent waiting well under half a second.
mkdir -p "$HOME/bin"
printf '#!/bin/sh\necho run >> "%s/plutil.log"\nexec /usr/bin/plutil "$@"\n' "$HOME" > "$HOME/bin/plutil"
chmod +x "$HOME/bin/plutil"
PATH="$HOME/bin:$PATH" PUPPET_NOW=0 PUPPET_TTY=/dev/ttys009 harnesses/claude/translate.sh \
  < harnesses/claude/fixtures/tool-tests.json
expect "with jq, plutil runs for no field" "$(cat "$HOME/plutil.log" 2>/dev/null | wc -l | tr -d ' ')" 0
head -c 3700000 /dev/zero | tr '\0' x | fold -w 100 | jq -Rs '{session_id: "big", cwd: "/Users/dev/my-app",
  hook_event_name: "PostToolUse", tool_name: "Read", tool_input: {file_path: "/Users/dev/my-app/big.txt"},
  tool_response: {type: "text", file: {filePath: "/Users/dev/my-app/big.txt", content: ., numLines: 37000}}}' \
  > "$HOME/big.json"
seconds=$( { /usr/bin/time -p env PUPPET_NOW=0 PUPPET_TTY=/dev/ttys009 harnesses/claude/translate.sh \
  < "$HOME/big.json" > /dev/null; } 2>&1 | awk '/^real/ { print $2 }')
expect "a 5 MB payload takes under 0.5 s (took $seconds s)" "$(echo "$seconds" | awk '{ print ($1 < 0.5) }')" 1
expect "and its line is written" "$(tail -n 1 "$HOME/.deskmates/events")" \
  "0|PostToolUse|big||Read|||my-app|${TERM_PROGRAM:-}||/dev/ttys009|claude|"

# Without jq (macOS 13 and 14), plutil reads each field: the same helpers, the same answers.
PUPPET_PAYLOAD='{"a":{"b":"one|two\nthree"},"n":3,"t":true,"z":null,"list":["x","y"],"cwd":"/Users/me/my-app"}'
for jq in "$PUPPET_JQ" ""; do
  PUPPET_JQ=$jq
  puppet_parse_payload
  mode=${jq:+jq}
  mode=${mode:-plutil}
  expect "$mode: a nested field, on one line without |" "$(field a.b)" "one two three"
  expect "$mode: a number" "$(field n)" 3
  expect "$mode: true" "$(field t)" true
  expect "$mode: null is nothing" "$(field z)" ""
  expect "$mode: a missing key is nothing" "$(field nope)" ""
  [ -n "$jq" ] && expect "jq: an object is nothing" "$(field a)" ""
  expect "$mode: an array item" "$(path_field list.1)" y
  expect "$mode: a path" "$(path_field cwd)" /Users/me/my-app
  expect "$mode: json_value" "$(printf '{"x":{"y":"deep"}}' | json_value x.y)" deep
  expect "$mode: json_value of a missing key" "$(printf '{"x":1}' | json_value y)" ""
done

rm -rf "$HOME"
[ "$failed" = 0 ] && echo "puppet-lib: ok"
exit "$failed"
