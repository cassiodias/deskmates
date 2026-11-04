#!/bin/sh
# The plan helpers in hook/plan-lib.sh on their own: where a session's plan file lives, when one is written
# (only while Deskmates runs, only with jq), and that a failed change leaves the old file as it was.
# shellcheck disable=SC2034 # PUPPET_PAYLOAD is read by the library this sources
cd "$(dirname "$0")/.." || exit 1
failed=0
HOME=$(mktemp -d) || exit 1
export HOME
. hook/puppet-lib.sh
. hook/plan-lib.sh
found_jq=$PUPPET_JQ

expect() {
  if [ "$2" != "$3" ]; then
    echo "plan-lib: $1"
    echo "  got      '$2'"
    echo "  expected '$3'"
    failed=1
  fi
}

PLANS="$HOME/.deskmates/plans"
ADD_STEP='. as $p | $cur | .steps += [{id: "1", title: $p.tool_input.subject, status: "pending"}]'
PUPPET_PAYLOAD='{"tool_input": {"subject": "Fixed the typo."}}'
PUPPET_NOW=100

# plan_file: a session id names one file in the plans folder, and nothing outside it.
expect "a session's file" "$(plan_file s1)" "$PLANS/s1.json"
expect "an id with dots and dashes" "$(plan_file a.b-c_1)" "$PLANS/a.b-c_1.json"
expect "an id with a slash is refused" "$(plan_file ../evil; echo "|$?")" "|1"
expect "an id of two dots is refused" "$(plan_file ..; echo "|$?")" "|1"
expect "an empty id is refused" "$(plan_file ''; echo "|$?")" "|1"

# deskmates_on: the marker the Spoon writes, naming a process that still runs.
mkdir -p "$HOME/.deskmates"
expect "no marker: off" "$(deskmates_on && echo on)" ""
sh -c 'exit 0' & dead=$!
wait "$dead"
echo "$dead" > "$HOME/.deskmates/on"
expect "a marker of a process that ended: off" "$(deskmates_on && echo on)" ""
echo "not a pid" > "$HOME/.deskmates/on"
expect "a marker with no pid: off" "$(deskmates_on && echo on)" ""
echo "$$" > "$HOME/.deskmates/on"
expect "a marker of a running process: on" "$(deskmates_on && echo on)" on

if [ -n "$found_jq" ]; then
  # plan_update: writes the whole new plan, readable by its owner only.
  expect "an update says it wrote" "$(plan_update s1 claude "$ADD_STEP"; echo "|$?")" "|0"
  expect "the plan written" "$("$found_jq" -c . "$PLANS/s1.json")" \
    '{"harness":"claude","session":"s1","steps":[{"id":"1","title":"Fixed the typo.","status":"pending"}],"updatedAt":100}'
  expect "mode 600" "$(stat -f %Lp "$PLANS/s1.json")" 600
  expect "the next change starts from it" "$(plan_update s1 claude "$ADD_STEP" && "$found_jq" '.steps | length' "$PLANS/s1.json")" 2

  # A filter that fails, or makes no plan, leaves the file exactly as it was.
  before=$(cat "$PLANS/s1.json")
  expect "a failing filter says so" "$(plan_update s1 claude '$cur | error("no")'; echo "|$?")" "|1"
  expect "a failing filter leaves the file" "$(cat "$PLANS/s1.json")" "$before"
  expect "a filter that makes no object says so" "$(plan_update s1 claude '"text"'; echo "|$?")" "|1"
  expect "a filter that makes no object leaves the file" "$(cat "$PLANS/s1.json")" "$before"
  expect "no temp file left behind" "$(ls "$PLANS")" "s1.json"

  # A broken file is started over, not kept.
  printf '{"steps": [' > "$PLANS/s2.json"
  plan_update s2 claude "$ADD_STEP"
  expect "a broken file is started over" "$("$found_jq" '.steps | length' "$PLANS/s2.json")" 1

  # Refused: a bad session, Deskmates off.
  expect "a bad session writes nothing" "$(plan_update ../evil claude "$ADD_STEP"; echo "|$?")" "|1"
  expect "nothing outside the plans folder" "$(ls "$HOME/.deskmates")" "on
plans"
  rm "$HOME/.deskmates/on"
  expect "Deskmates off writes nothing" "$(plan_update s3 claude "$ADD_STEP"; echo "|$?")" "|1"
  expect "no file for it" "$(ls "$PLANS")" "s1.json
s2.json"
  echo "$$" > "$HOME/.deskmates/on"
fi

# Without jq there is no plan.
expect "no jq writes nothing" "$(PUPPET_JQ= plan_update s4 claude "$ADD_STEP"; echo "|$?")" "|1"
expect "no file without jq" "$(ls "$PLANS" 2>/dev/null | grep -c s4)" 0

# plan_delete: the session's file goes; a bad id deletes nothing.
mkdir -p "$PLANS"
: > "$PLANS/s5.json"
plan_delete s5
expect "plan_delete removes the file" "$(ls "$PLANS" | grep -c s5)" 0
plan_delete ../evil
expect "plan_delete of a bad id" "$?" 0

rm -rf "$HOME"
[ "$failed" = 0 ] && echo "plan-lib: ok"
exit "$failed"
