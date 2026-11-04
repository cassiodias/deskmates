#!/bin/sh
# The facts helpers in hook/facts-lib.sh on their own: where a session's facts file lives, when one is written
# (only while Deskmates runs, only with jq), and that a failed change leaves the old file as it was.
# shellcheck disable=SC2034 # PUPPET_PAYLOAD is read by the library this sources
cd "$(dirname "$0")/.." || exit 1
failed=0
HOME=$(mktemp -d) || exit 1
export HOME
. hook/puppet-lib.sh
. hook/plan-lib.sh
. hook/facts-lib.sh
found_jq=$PUPPET_JQ

expect() {
  if [ "$2" != "$3" ]; then
    echo "facts-lib: $1"
    echo "  got      '$2'"
    echo "  expected '$3'"
    failed=1
  fi
}

FACTS="$HOME/.deskmates/facts"
SET='. as $p | $cur | .tickets[$p.k] = {seen: $now}'
PUPPET_PAYLOAD='{"k": "ABC-12"}'
PUPPET_NOW=100
mkdir -p "$HOME/.deskmates"
echo "$$" > "$HOME/.deskmates/on"

# facts_file: a session id names one file in the facts folder, and nothing outside it.
expect "a session's file" "$(facts_file s1)" "$FACTS/s1.json"
expect "an id with a slash is refused" "$(facts_file ../evil; echo "|$?")" "|1"
expect "an id of two dots is refused" "$(facts_file ..; echo "|$?")" "|1"
expect "an empty id is refused" "$(facts_file ''; echo "|$?")" "|1"

if [ -n "$found_jq" ]; then
  expect "an update says it wrote" "$(facts_update s1 "$SET"; echo "|$?")" "|0"
  expect "the facts written" "$("$found_jq" -c . "$FACTS/s1.json")" \
    '{"tickets":{"ABC-12":{"seen":100}},"timeline":[],"updatedAt":100}'
  expect "mode 600" "$(stat -f %Lp "$FACTS/s1.json")" 600
  expect "its folder mode 700" "$(stat -f %Lp "$FACTS")" 700

  # A filter that fails, or makes no object, leaves the file exactly as it was.
  before=$(cat "$FACTS/s1.json")
  expect "a failing filter says so" "$(facts_update s1 '$cur | error("no")'; echo "|$?")" "|1"
  expect "a failing filter leaves the file" "$(cat "$FACTS/s1.json")" "$before"
  expect "a filter that makes no object says so" "$(facts_update s1 '"text"'; echo "|$?")" "|1"
  expect "a filter that makes no object leaves the file" "$(cat "$FACTS/s1.json")" "$before"
  expect "no temp file left behind" "$(ls "$FACTS")" "s1.json"

  # Junk and half files are started over.
  echo '[1,2]' > "$FACTS/s2.json"
  facts_update s2 "$SET"
  expect "a junk file is started over" "$("$found_jq" -c .tickets "$FACTS/s2.json")" '{"ABC-12":{"seen":100}}'
  printf '{"tickets": {' > "$FACTS/s3.json"
  facts_update s3 "$SET"
  expect "a half file is started over" "$("$found_jq" -c .timeline "$FACTS/s3.json")" '[]'
  echo '{"tickets": [], "timeline": []}' > "$FACTS/s4.json"
  facts_update s4 "$SET"
  expect "a file of the wrong shape is started over" "$("$found_jq" -c .tickets "$FACTS/s4.json")" \
    '{"ABC-12":{"seen":100}}'
  rm -f "$FACTS/s2.json" "$FACTS/s3.json" "$FACTS/s4.json"

  # Hooks for tool calls made together run at the same time: no change is lost.
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    PUPPET_PAYLOAD="{\"k\": \"K-$i\"}" facts_update s6 "$SET" &
  done
  wait
  expect "changes made at once are all kept" "$("$found_jq" '.tickets | length' "$FACTS/s6.json")" 12
  expect "no lock left behind" "$(ls -a "$FACTS" | grep -c lock)" 0
  rm -f "$FACTS/s6.json"

  # A lock left by a hook that was killed does not stop facts for long.
  mkdir "$FACTS/s1.json.lock"
  expect "a stale lock is taken over" "$(facts_update s1 "$SET"; echo "|$?")" "|0"
  rmdir "$FACTS/s1.json.lock" 2>/dev/null

  # Refused: a bad session, Deskmates off.
  expect "a bad session writes nothing" "$(facts_update ../evil "$SET"; echo "|$?")" "|1"
  rm "$HOME/.deskmates/on"
  expect "Deskmates off writes nothing" "$(facts_update s5 "$SET"; echo "|$?")" "|1"
  expect "no file for it" "$(ls "$FACTS")" "s1.json"
  echo "$$" > "$HOME/.deskmates/on"
fi

# Without jq there are no facts.
expect "no jq writes nothing" "$(PUPPET_JQ= facts_update s7 "$SET"; echo "|$?")" "|1"
expect "no file without jq" "$(ls "$FACTS" 2>/dev/null | grep -c s7)" 0

# facts_delete: the session's file goes; a bad id deletes nothing.
mkdir -p "$FACTS"
: > "$FACTS/s8.json"
facts_delete s8
expect "facts_delete removes the file" "$(ls "$FACTS" | grep -c s8)" 0
facts_delete ../evil
expect "facts_delete of a bad id" "$?" 0

rm -rf "$HOME"
[ "$failed" = 0 ] && echo "facts-lib: ok"
exit "$failed"
