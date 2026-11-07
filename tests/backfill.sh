#!/bin/sh
# hook/backfill.sh on its own: what it reads from a Claude transcript (tests/backfill/<case>/transcript.jsonl and
# its subagents), and how it fills a session's facts. Neutral text only.
cd "$(dirname "$0")/.." || exit 1
failed=0
HOME=$(mktemp -d) || exit 1
export HOME
. hook/backfill.sh
[ -n "$PUPPET_JQ" ] || { echo "backfill: no jq, skipped"; exit 0; }

expect() {
  if [ "$2" != "$3" ]; then
    echo "backfill: $1"
    echo "  got      '$2'"
    echo "  expected '$3'"
    failed=1
  fi
}

# Reading: each case's reading.json is what backfill_read gives for its whole transcript.
for case in tests/backfill/*/; do
  [ -e "$case/reading.json" ] || continue
  t="$case/transcript.jsonl"
  expect "read: $(basename "$case")" "$(backfill_read "$t" 0 "$(backfill_size "$t")" | "$PUPPET_JQ" -S .)" \
    "$("$PUPPET_JQ" -S . "$case/reading.json")"
done
expect "size: stops before a line still being written" "$(backfill_size tests/backfill/cut/transcript.jsonl)" \
  "$(head -n 2 tests/backfill/cut/transcript.jsonl | wc -c | tr -d ' ')"

rm -rf "$HOME"
[ "$failed" = 0 ] && echo "backfill: ok"
exit "$failed"
