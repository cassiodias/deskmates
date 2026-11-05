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
  expect "its folder mode 700" "$(stat -f %Lp "$PLANS")" 700
  expect "the next change starts from it" "$(plan_update s1 claude "$ADD_STEP" && "$found_jq" '.steps | length' "$PLANS/s1.json")" 2

  # A filter that fails, or makes no plan, leaves the file exactly as it was.
  before=$(cat "$PLANS/s1.json")
  expect "a failing filter says so" "$(plan_update s1 claude '$cur | error("no")'; echo "|$?")" "|1"
  expect "a failing filter leaves the file" "$(cat "$PLANS/s1.json")" "$before"
  expect "a filter that makes no object says so" "$(plan_update s1 claude '"text"'; echo "|$?")" "|1"
  expect "a filter that makes no object leaves the file" "$(cat "$PLANS/s1.json")" "$before"
  expect "no temp file left behind" "$(ls "$PLANS")" "s1.json"

  # Hooks for tool calls made together run at the same time: no change is lost.
  PARALLEL='. as $p | $cur | .steps += [{id: $p.id, title: "x", status: "pending"}]'
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    PUPPET_PAYLOAD="{\"id\": \"$i\"}" plan_update s6 claude "$PARALLEL" &
  done
  wait
  expect "changes made at once are all kept" "$("$found_jq" '.steps | length' "$PLANS/s6.json")" 12
  expect "no lock left behind" "$(ls -a "$PLANS" | grep -c lock)" 0
  rm -f "$PLANS/s6.json"

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
  # A lock left by a hook that was killed does not stop plans for long.
  mkdir "$PLANS/s1.json.lock"
  echo "$$" > "$HOME/.deskmates/on"
  expect "a stale lock is taken over" "$(plan_update s1 claude "$ADD_STEP"; echo "|$?")" "|0"
  rm "$HOME/.deskmates/on"
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

# No helper leaves a variable behind: the shell's variables before and after each public helper (run in this
# shell, as a translator runs them) differ only in the helper-private names (_plan_…) and the documented results.
snap_vars() {
  set | grep -E '^[A-Za-z_][A-Za-z0-9_]*=' |
    grep -Ev '^(_|BASH[A-Z_]*|RANDOM|SRANDOM|SECONDS|LINENO|PIPESTATUS|OLDPWD|EPOCH[A-Z]*|snap_[a-z]*)='
}
# leaks name command…: runs the command here; nothing, or the names of the variables it changed that it should not.
leaks() {
  snap_vars > "$HOME/snap.before"
  "$@" > /dev/null 2>&1
  snap_vars > "$HOME/snap.after"
  cat "$HOME/snap.before" "$HOME/snap.after" | sort | uniq -u | cut -d= -f1 | sort -u |
    grep -Ev '^(_plan_|(nothing))' | tr '\n' ' '
}
expect "leak: plan_file" "$(leaks plan_file s30)" ""
expect "leak: deskmates_on" "$(leaks deskmates_on)" ""
if [ -n "$found_jq" ]; then
  expect "leak: plan_update" "$(leaks plan_update s30 claude "$ADD_STEP")" ""
  expect "leak: deskmates_json_update" "$(leaks deskmates_json_update "$PLANS/s31.json" '{}' 'type == "object"' '$cur')" ""
fi
expect "leak: plan_delete" "$(leaks plan_delete s30)" ""

rm -rf "$HOME"
[ "$failed" = 0 ] && echo "plan-lib: ok"
exit "$failed"
