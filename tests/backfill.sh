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

# The script: a home with the session's transcript where Claude Code keeps it, Deskmates on, a fixed clock.
B=1767225600
SID=11111111-2222-3333-4444-555555555555
FACTSF="$HOME/.deskmates/facts/$SID.json"
# setup <case> [facts json]: a fresh home for case <case>'s transcript (and subagents), with those facts.
setup() {
  rm -rf "$HOME/.claude" "$HOME/.deskmates"
  mkdir -p "$HOME/.claude/projects/-work-my-app" "$HOME/.deskmates/facts"
  echo "$$" > "$HOME/.deskmates/on"
  cp "tests/backfill/$1/transcript.jsonl" "$HOME/.claude/projects/-work-my-app/$SID.jsonl"
  [ -d "tests/backfill/$1/transcript" ] && cp -R "tests/backfill/$1/transcript" "$HOME/.claude/projects/-work-my-app/$SID"
  [ -n "${2:-}" ] && printf '%s' "$2" > "$FACTSF"
  return 0
}
run() { PUPPET_NOW=$((B + 9000)) sh hook/backfill.sh "$SID"; }
q() { "$PUPPET_JQ" -c "$1" "$FACTSF" 2>/dev/null; }
HOOK_TURN='{"at": %d, "endAt": %d, "head": "h%d", "files": ["src/app.js"], "tests": {"ran": 0, "passed": 0, "failed": 0}, "commits": [{"hash": "abc1234", "subject": "Hook"}]}'
turn() { printf "$HOOK_TURN" "$((B + $1))" "$((B + $1 + 9))" "$1"; }

# A gap between two turns the hooks recorded: only it is added; theirs stay as they are.
setup three "{\"tickets\": {}, \"timeline\": [], \"turns\": [$(turn 300), $(turn 100)]}"
before100=$(q '.turns[] | select(.at == '$((B + 100))')')
expect "gap: the answer" "$(run)" "ok 1"
expect "gap: turns, newest first" "$(q '[.turns[].at]')" "[$((B + 300)),$((B + 200)),$((B + 100))]"
expect "gap: the added turn says where it came from" "$(q '.turns[1] | [.fromTranscript, .endAt, .files, .tests]')" \
  "[true,$((B + 210)),[],{\"ran\":0,\"passed\":0,\"failed\":0}]"
expect "gap: the hooks' turn unchanged" "$(q '.turns[] | select(.at == '$((B + 100))')')" "$before100"
expect "gap: read up to the end" "$(q '.backfill.upTo')" "$(wc -c < tests/backfill/three/transcript.jsonl | tr -d ' ')"
# Again: nothing new to read.
first=$(q 'del(.backfill.at, .updatedAt)')
expect "again: the answer" "$(run)" "none"
expect "again: nothing changed" "$(q 'del(.backfill.at, .updatedAt)')" "$first"

# A hook turn 3 s from the transcript's prompt is that prompt's turn: no gap.
setup three "{\"tickets\": {}, \"timeline\": [], \"turns\": [$(turn 303), $(turn 203), $(turn 103)]}"
expect "window: no gap" "$(run)" "none"
expect "window: the offset kept" "$(q '.backfill.upTo > 0')" true

# Grown: what was read before is not read again for gaps (its missing turn stays missing), the new part is.
upto=$(head -n 4 tests/backfill/three/transcript.jsonl | wc -c | tr -d ' ')
setup three "{\"tickets\": {}, \"timeline\": [], \"turns\": [$(turn 200)], \"backfill\": {\"upTo\": $upto, \"at\": 1}}"
expect "grown: the answer" "$(run)" "ok 1"
expect "grown: only the new prompt added" "$(q '[.turns[].at]')" "[$((B + 300)),$((B + 200))]"

# No facts at all: everything from the transcript, tickets and steps too.
setup subagent
expect "nofacts: the answer" "$(run)" "ok 1"
expect "nofacts: the ticket" "$(q '.current')" '"ABC-12"'
expect "nofacts: its step" "$("$PUPPET_JQ" -cS '.tickets["ABC-12"].passes' "$FACTSF")" \
  "[{\"at\":$((B + 101)),\"by\":\"Implement ABC-12 via my-developer\",\"endAt\":$((B + 150)),\"phase\":\"dev\",\"verdict\":\"CHANGES_REQUESTED\"}]"
expect "nofacts: the timeline, newest first" "$(q '[.timeline[].kind]')" '["reply","done","tests","subagent","phase"]'

# Test runs: only real ones count, in the turn and the timeline.
setup tests
run > /dev/null
expect "tests: counted in the turn" "$(q '.turns[0].tests')" '{"ran":1,"passed":0,"failed":1}'
expect "tests: on the timeline" "$(q '[.timeline[] | select(.kind == "tests") | .text]')" '["failed"]'

# No transcript: none, nothing written. Deskmates off: an error, nothing written.
setup three
rm "$HOME/.claude/projects/-work-my-app/$SID.jsonl"
expect "notranscript: none" "$(run)" "none"
expect "notranscript: no facts" "$(ls "$HOME/.deskmates/facts")" ""
setup three
rm "$HOME/.deskmates/on"
expect "off: an error" "$(run)" "error Deskmates is off"
expect "off: no facts" "$(ls "$HOME/.deskmates/facts")" ""

# A long session no hook saw: only the newest 30 gaps get turns (and git calls); the answer counts those kept.
mkdir -p "$HOME/long"
: > "$HOME/long/t.jsonl"
i=1
while [ "$i" -le 35 ]; do
  t=$(date -u -r $((B + i * 100)) +%Y-%m-%dT%H:%M:%S.000Z)
  printf '{"type":"user","timestamp":"%s","cwd":"/work/my-app","message":{"content":"Prompt %d"}}\n' "$t" "$i" >> "$HOME/long/t.jsonl"
  i=$((i + 1))
done
rm -rf "$HOME/.claude" "$HOME/.deskmates"
mkdir -p "$HOME/.claude/projects/-work-my-app" "$HOME/.deskmates/facts"
echo "$$" > "$HOME/.deskmates/on"
cp "$HOME/long/t.jsonl" "$HOME/.claude/projects/-work-my-app/$SID.jsonl"
expect "long: the answer counts the turns kept" "$(run)" "ok 30"
expect "long: the newest 30" "$(q '[.turns | length, .[-1].at]')" "[30,$((B + 600))]"

# Git for backfilled turns, from git log by time: a repo with commits at set times, the transcript run in it.
gitrepo() {
  rm -rf "$HOME/repo"; mkdir -p "$HOME/repo"
  REPO=$(cd -P "$HOME/repo" && pwd -P)
  git -C "$REPO" init -q
  for c in "50 Start" "104 Fix the typo" "205 Docs"; do
    echo "${c#* }" > "$REPO/README.md"
    git -C "$REPO" add -A
    GIT_AUTHOR_DATE="@$((B + ${c%% *})) +0000" GIT_COMMITTER_DATE="@$((B + ${c%% *})) +0000" \
      git -C "$REPO" -c user.email=t@t -c user.name=t commit -q -m "${c#* }"
  done
}
sha_at() { git -C "$REPO" log --format=%H --grep="^$1\$"; }
short_at() { git -C "$REPO" log --format=%h --grep="^$1\$"; }
# setup_git <facts json>: case simple, its paths in the repo.
setup_git() {
  setup simple "${1:-}"
  sed -i '' "s|/work/my-app|$REPO|g" "$HOME/.claude/projects/-work-my-app/$SID.jsonl"
}
gitrepo
setup_git
expect "git: the answer" "$(run)" "ok 2"
expect "git: the repo, its base when the session started" "$("$PUPPET_JQ" -cS .git "$FACTSF")" \
  "{\"base\":\"$(sha_at Start)\",\"dirtyAtStart\":[],\"folder\":\"$REPO\",\"fromTranscript\":true,\"prefix\":\"\",\"root\":\"$REPO\",\"top\":null}"
expect "git: the first turn" "$(q '.turns[1] | [.head, .files, .commits]')" \
  "[\"$(sha_at Start)\",[\"README.md\"],[{\"hash\":\"$(short_at "Fix the typo")\",\"subject\":\"Fix the typo\"}]]"
expect "git: the second turn" "$(q '.turns[0] | [.head, .commits]')" \
  "[\"$(sha_at "Fix the typo")\",[{\"hash\":\"$(short_at Docs)\",\"subject\":\"Docs\"}]]"
# Git facts the hooks recorded stay.
setup_git '{"tickets": {}, "timeline": [], "git": {"root": "/kept", "base": "k1", "dirtyAtStart": [], "folder": "/kept", "prefix": "", "top": null}}'
run > /dev/null
expect "git: the hooks' git facts kept" "$(q '.git.base')" '"k1"'
# The hooks' base is newer than turns the backfill fills: the base moves back to when the session started.
hookgit() { printf '{"root": "%s", "base": "%s", "dirtyAtStart": ["README.md"], "folder": "%s", "prefix": "", "top": null%s}' \
  "$REPO" "$(sha_at Docs)" "$REPO" "${1:-}"; }
setup_git "{\"tickets\": {}, \"timeline\": [], \"git\": $(hookgit), \"turns\": [$(turn 200)]}"
expect "older: the answer" "$(run)" "ok 1"
expect "older: the base when the session started, read from the transcript" \
  "$(q '.git | [.base, .fromTranscript, .dirtyAtStart, .root == "'"$REPO"'"]')" "[\"$(sha_at Start)\",true,[],true]"
setup_git "{\"tickets\": {}, \"timeline\": [], \"git\": $(hookgit), \"turns\": [$(turn 100)]}"
run > /dev/null
expect "newer gap: the hooks' base stays" "$(q '.git | [.base, .fromTranscript]')" "[\"$(sha_at Docs)\",null]"
# Final review: hooks that watched from the start keep only their newest 30 turns, so the transcript's first prompt
# looks older; their base is the commit at that prompt already: it stays, with what was dirty then.
hookgitAt() { printf '{"root": "%s", "base": "%s", "dirtyAtStart": ["README.md"], "folder": "%s", "prefix": "", "top": null}' \
  "$REPO" "$(sha_at "$1")" "$REPO"; }
setup_git "{\"tickets\": {}, \"timeline\": [], \"git\": $(hookgitAt Start), \"turns\": [$(turn 200)]}"
run > /dev/null
expect "dropped turns: the hooks' base and dirty files stay" "$(q '.git | [.base, .fromTranscript, .dirtyAtStart]')" \
  "[\"$(sha_at Start)\",null,[\"README.md\"]]"
setup_git "{\"tickets\": {}, \"timeline\": [], \"git\": $(hookgit ', "fromTranscript": true'), \"turns\": [$(turn 200)]}"
run > /dev/null
expect "from the transcript already: kept" "$(q '.git.base')" "\"$(sha_at Docs)\""

# A folder that is no repo: no git facts, the turns still added.
setup simple
expect "nogit: the answer" "$(run)" "ok 2"
expect "nogit: no git facts" "$(q '.git')" null
expect "nogit: turns, no paths" "$(q '[.turns[] | .files]')" '[[],[]]'

# Live (7 Nov): Hammerspoon runs the script as ~/.hammerspoon/Spoons/Deskmates.spoon/../hook/backfill.sh, where
# Deskmates.spoon is a link to the clone's: its helpers are found beside the real file.
mkdir -p "$HOME/hs/Spoons"
ln -s "$(pwd -P)/Deskmates.spoon" "$HOME/hs/Spoons/Deskmates.spoon"
setup three
# Run from another folder, as Hammerspoon does (its own): nothing may depend on where it is started.
expect "through the Spoon's link: it runs" "$(cd "$HOME/hs" && PUPPET_NOW=$((B + 9000)) sh "$HOME/hs/Spoons/Deskmates.spoon/../hook/backfill.sh" "$SID" 2>&1)" "ok 3"

# No helper leaves a plain variable behind (run in this shell, as a script would).
snap_vars() {
  set | grep -E '^[A-Za-z_][A-Za-z0-9_]*=' |
    grep -Ev '^(_|BASH[A-Z_]*|RANDOM|SRANDOM|SECONDS|LINENO|PIPESTATUS|OLDPWD|EPOCH[A-Z]*|snap_[a-z]*)='
}
leaks() {
  snap_vars > "$HOME/snap.before"
  "$@" > /dev/null 2>&1
  snap_vars > "$HOME/snap.after"
  cat "$HOME/snap.before" "$HOME/snap.after" | sort | uniq -u | cut -d= -f1 | sort -u |
    grep -Ev '^(_backfill_|_facts_|_plan_|_puppet_|PUPPET_|DESKMATES_GIT|DESKMATES_GIT_PATH|facts_root|facts_open)' | tr '\n' ' '
}
setup three
expect "leak: backfill_find" "$(leaks backfill_find "$SID")" ""
expect "leak: backfill_size" "$(leaks backfill_size tests/backfill/three/transcript.jsonl)" ""
expect "leak: backfill_read" "$(leaks backfill_read tests/backfill/three/transcript.jsonl 0 10)" ""
expect "leak: backfill_main" "$(PUPPET_NOW=$((B + 9000)); leaks backfill_main "$SID")" ""

rm -rf "$HOME"
[ "$failed" = 0 ] && echo "backfill: ok"
exit "$failed"
