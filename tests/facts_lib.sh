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

# The rules (facts_note): a note made from an event, applied to the session's facts.
if [ -n "$found_jq" ]; then
  # A def from FACTS_DEFS on JSON value $2.
  def() { printf '%s' "$2" | "$found_jq" -c "$FACTS_DEFS $1"; }
  # Applies note $2 (JSON) to session $1 at time $3; prints the status.
  note() { PUPPET_NOW=$3 PUPPET_PAYLOAD=$2 facts_note "$1" '.'; echo "$?"; }
  # The value of jq filter $2 on session $1's facts.
  got() { "$found_jq" -c "$2" "$FACTS/$1.json" 2>/dev/null; }

  expect "tickets: one" "$(def tickets '"Implement ABC-12 via my-developer"')" '["ABC-12"]'
  expect "tickets: first first" "$(def tickets '"ABC-34 then ABC-12"')" '["ABC-34","ABC-12"]'
  expect "tickets: not tickets" "$(def tickets '"UTF-8 and SHA-256, RFC-2119"')" '[]'
  expect "tickets: inside a word" "$(def tickets '"xABC-12"')" '[]'
  expect "tickets: one letter" "$(def tickets '"A-1"')" '[]'
  expect "tickets: too long a project" "$(def tickets '"ABCDEFGHIJK-1"')" '[]'
  expect "phase: a developer" "$(def phase '"my-developer"')" '"dev"'
  expect "phase: QA" "$(def phase '"QA ABC-12 lens break"')" '"review"'
  expect "phase: review wins over plan" "$(def phase '"Review the plan"')" '"review"'
  expect "phase: dev wins over plan" "$(def phase '"Implement the plan"')" '"dev"'
  expect "phase: only whole words" "$(def phase '"rebuild the planet"')" 'null'
  expect "phase: an engineer plans" "$(def phase '"my-engineer"')" '"plan"'
  long=$(printf 'a%.0s' $(seq 1 300))
  expect "clean: control characters out, 200 characters" \
    "$(def clean "\"bell\\u0007$long\"" | "$found_jq" -r '[length, (explode | any(. < 32))] | @csv')" '200,false'

  # A skill naming a ticket: it becomes current, in the skill's phase.
  expect "a skill note writes" "$(note n1 '{"kind":"skill","text":"my-developer","from":"my-developer ABC-12","moves":true}' 10)" 0
  expect "its ticket is current" "$(got n1 .current)" '"ABC-12"'
  expect "in the skill's phase" "$(got n1 '.tickets["ABC-12"] | [.phase, .phaseAt, .phases.dev, .seen]')" '["dev",10,10,10]'
  expect "a phase line, then the skill's, newest first" "$(got n1 '[.timeline[] | [.kind, .text, .ticket, .phase, .at]]')" \
    '[["skill","my-developer","ABC-12","dev",10],["phase","dev","ABC-12","dev",10]]'

  # A phase with no ticket waits under "-", and moves to the first ticket that appears.
  note n2 '{"kind":"skill","text":"my-reviewer","from":"my-reviewer","moves":true}' 10 > /dev/null
  expect "the phase waits" "$(got n2 '[.current, .tickets["-"].phase]')" '[null,"review"]'
  note n2 '{"kind":"subagent","text":"Implement ABC-12","from":"Implement ABC-12","moves":true}' 20 > /dev/null
  expect "the waiting ticket is gone" "$(got n2 '.tickets | keys')" '["ABC-12"]'
  expect "its phases moved" "$(got n2 '.tickets["ABC-12"] | [.phase, .phases.review, .phases.dev]')" '["dev",10,20]'
  expect "its lines moved" "$(got n2 '[.timeline[].ticket] | unique')" '["ABC-12"]'
  expect "current is the ticket" "$(got n2 .current)" '"ABC-12"'

  # A reply naming another ticket: a line under it; current stays.
  note n3 '{"kind":"skill","text":"my-developer","from":"my-developer ABC-12","moves":true}' 10 > /dev/null
  note n3 '{"kind":"reply","text":"ABC-34 is done.","from":"ABC-34 is done.","moves":false}' 20 > /dev/null
  expect "the reply's line is the other ticket's" "$(got n3 '.timeline[0] | [.ticket, .kind]')" '["ABC-34","reply"]'
  expect "current stays" "$(got n3 .current)" '"ABC-12"'
  note n3 '{"kind":"reply","text":"Fixed the typo.","from":"Fixed the typo.","moves":false}' 30 > /dev/null
  expect "a reply naming none is current's" "$(got n3 '.timeline[0] | [.ticket, .text]')" '["ABC-12","Fixed the typo."]'

  # Nothing to hang a line on: no file.
  expect "a reply with no facts yet writes nothing" "$(note n4 '{"kind":"reply","text":"Fixed the typo.","from":"Fixed the typo.","moves":false}' 10)" 1
  expect "a test run with no facts yet writes nothing" "$(note n4 '{"kind":"tests","text":"passed","from":"","moves":false}' 10)" 1
  expect "a skill with no ticket and no phase writes nothing" "$(note n4 '{"kind":"skill","text":"my-skill","from":"my-skill","moves":true}' 10)" 1
  expect "no file for them" "$(ls "$FACTS" | grep -c n4)" 0

  # Jira: a status, or the ticket only.
  expect "a Jira status" "$(note n5 '{"kind":"jira","text":"In Dev","ticket":"ABC-12","jira":"In Dev","from":"","moves":true}' 10)" 0
  expect "its status kept" "$(got n5 '[.current, .tickets["ABC-12"].jira.status, .tickets["ABC-12"].jira.at, .timeline[0].kind]')" '["ABC-12","In Dev",10,"jira"]'
  note n6 '{"kind":null,"ticket":"ABC-12","from":"","moves":true}' 10 > /dev/null
  expect "a Jira read with no status: the ticket, no line" "$(got n6 '[.current, (.timeline | length)]')" '["ABC-12",0]'
  expect "a key that is no ticket writes nothing" "$(note n7 '{"kind":null,"ticket":"nope","from":"","moves":true}' 10)" 1

  # A test run of the current ticket.
  note n8 '{"kind":"skill","text":"my-developer","from":"my-developer ABC-12","moves":true}' 10 > /dev/null
  note n8 '{"kind":"tests","text":"failed","from":"","moves":false}' 20 > /dev/null
  expect "a test run's line" "$(got n8 '.timeline[0] | [.ticket, .kind, .text, .phase]')" '["ABC-12","tests","failed","dev"]'

  # Review fixes: a reply never starts facts, nor moves a waiting phase; the phase comes from phaseFrom.
  expect "a reply naming an unknown ticket, no facts: nothing" "$(note r1 '{"kind":"reply","text":"Upgraded to GPT-4.","from":"Upgraded to GPT-4.","moves":false}' 10)" 1
  expect "and no file" "$(ls "$FACTS" | grep -c r1)" 0
  note r2 '{"kind":"skill","text":"my-developer","from":"my-developer","moves":true}' 10 > /dev/null
  note r2 '{"kind":"reply","text":"ABC-34 looks related.","from":"ABC-34 looks related.","moves":false}' 20 > /dev/null
  expect "a reply naming a ticket leaves a waiting phase where it is" "$(got r2 '[(.tickets | keys), .timeline[0].ticket]')" '[["-"],"-"]'
  note r3 '{"kind":"skill","text":"my-developer","from":"my-developer ABC-12, then write tests","phaseFrom":"my-developer","moves":true}' 10 > /dev/null
  expect "the phase from phaseFrom, the ticket from from" "$(got r3 '[.current, .tickets["ABC-12"].phase]')" '["ABC-12","dev"]'
  expect "phaseFrom with no phase word: none" "$(note r4 '{"kind":"skill","text":"commit","from":"commit fix the review comments","phaseFrom":"commit","moves":true}' 10)" 1

  # A lane ends: a subagent's stop (its description names the phase), or a plan approved.
  note e1 '{"kind":"subagent","text":"Implement ABC-12 via my-developer","from":"Implement ABC-12 via my-developer","moves":true}' 10 > /dev/null
  expect "an end writes" "$(note e1 '{"kind":"done","text":"Applied the two edits.","from":"Implement ABC-12 via my-developer","phaseFrom":"Implement ABC-12 via my-developer","ends":true,"moves":false}' 20)" 0
  expect "the lane's end" "$(got e1 '.tickets["ABC-12"] | [.phase, .ends.dev.at, .ends.dev.outcome]')" '["dev",20,"Applied the two edits."]'
  expect "a done line in that lane" "$(got e1 '.timeline[0] | [.kind, .text, .phase, .ticket]')" '["done","Applied the two edits.","dev","ABC-12"]'
  note e1 '{"kind":"done","text":"Two findings.","from":"QA ABC-12 review","phaseFrom":"QA ABC-12 review","ends":true,"verdict":"CHANGES_REQUESTED","moves":false}' 30 > /dev/null
  expect "an end with no start starts it then, with its verdict" "$(got e1 '.tickets["ABC-12"] | [.phases.review, .ends.review.at, .ends.review.verdict, .phase]')" '[30,30,"CHANGES_REQUESTED","dev"]'
  note e1 '{"kind":"subagent","text":"Implement ABC-12 fixes","from":"Implement ABC-12 fixes","moves":true}' 40 > /dev/null
  expect "starting the lane again reopens it" "$(got e1 '.tickets["ABC-12"] | [(.ends | has("dev")), (.ends | has("review"))]')" '[false,true]'
  expect "an end naming no phase: nothing" "$(note e1 '{"kind":"done","text":"Found it.","from":"Explore the code","phaseFrom":"Explore the code","ends":true,"moves":false}' 50)" 1
  expect "an end with no facts yet: nothing" "$(note e2 '{"kind":"done","text":"Plan approved","from":"","phaseFrom":"plan","ends":true,"moves":false}' 10)" 1
  note e3 '{"kind":"skill","text":"my-developer","from":"my-developer ABC-12","moves":true}' 10 > /dev/null
  note e3 '{"kind":"done","text":"Plan approved","from":"","phaseFrom":"plan","ends":true,"moves":false}' 20 > /dev/null
  expect "a plan approved ends Plan under current" "$(got e3 '.tickets["ABC-12"] | [.phases.plan, .ends.plan.outcome, .phase]')" '[20,"Plan approved","dev"]'

  # The cut: 30 lines, 10 tickets, never current.
  note n9 '{"kind":"skill","text":"my-developer","from":"my-developer ABC-12","moves":true}' 1 > /dev/null
  for i in $(seq 2 32); do note n9 "{\"kind\":\"reply\",\"text\":\"line $i\",\"from\":\"line $i\",\"moves\":false}" "$i" > /dev/null; done
  expect "30 lines, the newest kept" "$(got n9 '[(.timeline | length), .timeline[0].text, .timeline[29].text]')" '[30,"line 32","line 3"]'
  note n10 '{"kind":"skill","text":"my-developer","from":"my-developer ABC-1","moves":true}' 1 > /dev/null
  for i in $(seq 2 11); do note n10 "{\"kind\":\"reply\",\"text\":\"ABC-$i done.\",\"from\":\"ABC-$i done.\",\"moves\":false}" "$i" > /dev/null; done
  expect "cut keeps current" "$(got n10 '[(.tickets | length), .current, (.tickets | has("ABC-1")), (.tickets | has("ABC-2"))]')" '[10,"ABC-1",true,false]'
fi

# Git facts (facts_git_start, facts_turn_*, facts_edit): on a repo made here, never the user's git config.
if [ -n "$found_jq" ] && command -v git > /dev/null; then
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM
  # git on repo $1 with an identity of its own.
  tgit() { r=$1; shift; git -C "$r" -c user.name=Test -c user.email=test@example.com "$@"; }
  repo="$HOME/repo"
  mkdir -p "$repo/src" "$repo/docs"
  git init -q "$repo"
  echo one > "$repo/src/app.js"
  echo one > "$repo/src/my file.js"
  echo one > "$repo/docs/ção.md"
  tgit "$repo" add -A
  tgit "$repo" commit -q -m "First"
  first=$(git -C "$repo" rev-parse HEAD)
  echo two > "$repo/src/app.js"
  echo note > "$repo/notes.txt"

  # The base: once per session, with what was dirty then.
  expect "the base writes" "$(facts_git_start g1 "$repo"; echo "|$?")" "|0"
  expect "root and base" "$(got g1 '.git | [.root, .base]')" "[\"$(cd "$repo" && pwd -P)\",\"$first\"]"
  expect "dirty at start" "$(got g1 '.git.dirtyAtStart | sort')" '["notes.txt","src/app.js"]'
  expect "a file with git only is valid facts" "$(got g1 '[.tickets, .timeline]')" '[{},[]]'
  echo three > "$repo/src/my file.js"
  tgit "$repo" commit -q -m "Second" -- "src/my file.js"
  expect "the base again writes nothing" "$(facts_git_start g1 "$repo"; echo "|$?")" "|1"
  expect "the first base kept" "$(got g1 .git.base)" "\"$first\""
  second=$(git -C "$repo" rev-parse HEAD)

  # No repo, or a repo with no commit yet: no facts.
  mkdir -p "$HOME/plain" "$HOME/empty"
  git init -q "$HOME/empty"
  expect "a folder that is no repo writes nothing" "$(facts_git_start g2 "$HOME/plain"; echo "|$?")" "|1"
  expect "a repo with no commit writes nothing" "$(facts_git_start g3 "$HOME/empty"; echo "|$?")" "|1"
  expect "no file for them" "$(ls "$FACTS" | grep -c 'g[23]')" 0

  # A turn: its files, tests and commits.
  expect "a turn starts" "$(PUPPET_NOW=100 facts_turn_start g1; echo "|$?")" "|0"
  expect "the open turn" "$(got g1 '.turns | [length, .[0].at, .[0].head, (.[0] | has("endAt")), .[0].files, .[0].tests, .[0].commits]')" \
    "[1,100,\"$second\",false,[],{\"ran\":0,\"passed\":0,\"failed\":0},[]]"
  expect "an absolute path writes" "$(facts_edit g1 "$repo" "$repo/src/app.js"; echo "|$?")" "|0"
  facts_edit g1 "$repo" "./src/../src/my file.js" "/etc/hosts" "src/app.js"
  expect "a path outside the repo only writes nothing" "$(facts_edit g1 "$repo" /etc/hosts "../x"; echo "|$?")" "|1"
  expect "the turn's files" "$(got g1 '.turns[0].files')" '["src/app.js","src/my file.js"]'
  expect "the paths seen" "$(got g1 '.seen')" '{"src/app.js":true,"src/my file.js":true}'
  facts_turn_test g1 ran
  facts_turn_test g1 ran
  facts_turn_test g1 passed
  expect "a test count writes" "$(facts_turn_test g1 failed; echo "|$?")" "|0"
  expect "no such count writes nothing" "$(facts_turn_test g1 skipped; echo "|$?")" "|1"
  expect "the turn's tests" "$(got g1 '.turns[0].tests')" '{"ran":2,"passed":1,"failed":1}'
  echo four > "$repo/src/app.js"
  tgit "$repo" commit -q -m "Fix the typo" -- src/app.js
  expect "a turn ends" "$(PUPPET_NOW=200 facts_turn_end g1; echo "|$?")" "|0"
  expect "its end and commits" "$(got g1 '.turns[0] | [.endAt, (.commits | map(.subject)), (.commits[0].hash | length)]')" \
    '[200,["Fix the typo"],7]'
  expect "the commit's hash" "$(got g1 '.turns[0].commits[0].hash')" "\"$(git -C "$repo" rev-parse --short=7 HEAD)\""
  expect "no open turn: an end writes nothing" "$(facts_turn_end g1; echo "|$?")" "|1"
  expect "no open turn: a test count writes nothing" "$(facts_turn_test g1 ran; echo "|$?")" "|1"
  facts_edit g1 "$repo" "docs/ção.md"
  expect "no open turn: an edit is only seen" "$(got g1 '[.turns[0].files, (.seen | keys)]')" \
    '[["src/app.js","src/my file.js"],["docs/ção.md","src/app.js","src/my file.js"]]'

  # A turn still open when the next prompt comes was stopped (Esc runs no Stop hook): it keeps no end and no
  # commits, since neither is known (a commit since may be the user's own).
  PUPPET_NOW=300 facts_turn_start g1
  echo five > "$repo/src/app.js"
  tgit "$repo" commit -q -m "Second fix" -- src/app.js
  PUPPET_NOW=400 facts_turn_start g1
  expect "the open turn left by the next: no end, no commits" \
    "$(got g1 '.turns | [length, .[0].at, (.[0] | has("endAt")), .[1].at, (.[1] | has("endAt")), .[1].commits]')" \
    '[3,400,false,300,false,[]]'

  # A session started in a subfolder: its relative paths are the subfolder's.
  facts_git_start g4 "$repo/src"
  facts_turn_start g4
  expect "the folder and its place in the repo" "$(got g4 '.git | [.folder, .prefix]')" "[\"$repo/src\",\"src/\"]"
  facts_edit g4 "$repo/src" app.js "$repo/src/my file.js" ../notes.txt "$(cd "$repo" && pwd -P)/docs/ção.md"
  expect "relative to the subfolder, or to the real root" "$(got g4 '.turns[0].files')" \
    '["src/app.js","src/my file.js","notes.txt","docs/ção.md"]'

  # A folder spelled through a symlink: its paths still land relative to the root.
  ln -s repo "$HOME/alias"
  facts_git_start g5 "$HOME/alias"
  facts_turn_start g5
  facts_edit g5 "$HOME/alias" "$HOME/alias/src/app.js"
  expect "through a symlink" "$(got g5 '.turns[0].files')" '["src/app.js"]'
  # A subfolder spelled through a symlink: a path beside it is still in the repo.
  facts_git_start g12 "$HOME/alias/src"
  facts_turn_start g12
  facts_edit g12 "$HOME/alias/src" "$HOME/alias/docs/ção.md" "$HOME/alias/src/app.js"
  expect "beside a subfolder spelled through a symlink" "$(got g12 '.turns[0].files')" '["docs/ção.md","src/app.js"]'
  expect "the root's other spelling, checked" "$(got g12 .git.top)" "\"$HOME/alias\""
  # A symlink straight at the subfolder, named like it: its parent is not the repo, so a path there is refused.
  mkdir -p "$HOME/proj"
  ln -s "$repo/src" "$HOME/proj/src"
  facts_git_start g13 "$HOME/proj/src"
  facts_turn_start g13
  facts_edit g13 "$HOME/proj/src" "$HOME/proj/x.md" "$HOME/proj/src/app.js"
  expect "no other spelling of the root" "$(got g13 .git.top)" null
  expect "a path beside it, outside the repo, dropped" "$(got g13 '.turns[0].files')" '["src/app.js"]'

  # The cuts: 30 turns, subjects of 120 characters.
  facts_git_start g6 "$repo"
  for i in $(seq 1 31); do PUPPET_NOW=$i facts_turn_start g6; done
  expect "a 31st turn drops the oldest" "$(got g6 '.turns | [length, .[0].at, .[29].at]')" '[30,31,2]'
  facts_git_start g7 "$repo"
  facts_turn_start g7
  long=$(printf 's%.0s' $(seq 1 200))
  tgit "$repo" commit -q --allow-empty -m "$long"
  facts_turn_end g7
  expect "a subject of 200 characters cut to 120" "$(got g7 '.turns[0].commits[0].subject | length')" 120

  # A rename gives both paths at start.
  tgit "$repo" mv "docs/ção.md" docs/new.md
  facts_git_start g8 "$repo"
  expect "a rename, both paths" "$(got g8 '.git.dirtyAtStart | sort')" '["docs/new.md","docs/ção.md","notes.txt"]'
  tgit "$repo" mv docs/new.md "docs/ção.md"

  # Every git call is made with GIT_OPTIONAL_LOCKS=0: it never takes the agent's index.lock.
  mkdir -p "$HOME/fakebin"
  printf '#!/bin/sh\necho "${GIT_OPTIONAL_LOCKS-unset}" >> "%s"\nexec %s "$@"\n' "$HOME/locks" "$(command -v git)" \
    > "$HOME/fakebin/git"
  chmod +x "$HOME/fakebin/git"
  (
    PATH="$HOME/fakebin:$PATH"
    facts_git_start g9 "$repo"
    facts_turn_start g9
    facts_edit g9 "$repo" src/app.js
    facts_turn_test g9 ran
    facts_turn_end g9
    facts_turn_start g9
  )
  expect "the fake git was used" "$(got g9 '.turns | length')" 2
  expect "every git call without optional locks" "$(sort -u "$HOME/locks")" 0
  expect "no index.lock left" "$(ls "$repo/.git" | grep -c index.lock)" 0

  # An edit from the folder the session started in asks git nothing; from another folder, once.
  (
    PATH="$HOME/fakebin:$PATH"
    before=$(wc -l < "$HOME/locks")
    facts_edit g9 "$repo" src/app.js "src/my file.js"
    expect "an edit from the session's folder runs no git" "$(($(wc -l < "$HOME/locks") - before))" 0
    facts_edit g9 "$repo/src" app.js
    expect "an edit from another folder runs git once" "$(($(wc -l < "$HOME/locks") - before))" 1
    [ "$failed" = 0 ]
  ) || failed=1
  expect "both edits written" "$(got g9 '.seen | keys')" '["src/app.js","src/my file.js"]'

  # The git to run is looked up once per hook (again when PATH changes).
  (
    PATH="$HOME/fakebin:$PATH"
    expect "the git found" "$(deskmates_git > /dev/null; mv "$HOME/fakebin/git" "$HOME/git.moved"; deskmates_git)" \
      "$HOME/fakebin/git"
    mv "$HOME/git.moved" "$HOME/fakebin/git"
    [ "$failed" = 0 ]
  ) || failed=1

  # facts_track: one event's work on the facts, and whether its line should carry the facts flag.
  facts_track t1 "$repo" UserPromptSubmit "" no
  expect "a prompt: the facts flag" "$(facts_track t1 "$repo" UserPromptSubmit "" no; echo "|$?")" "|0"
  expect "a prompt with a test flag: no facts flag" "$(facts_track t1 "$repo" UserPromptSubmit test no; echo "|$?")" "|1"
  expect "a prompt with a plan flag: no facts flag" "$(facts_track t1 "$repo" UserPromptSubmit plan no; echo "|$?")" "|1"
  expect "a prompt opened turns" "$(got t1 '.turns | length')" 4
  expect "a tool event: no facts flag" "$(facts_track t1 "$repo" PreToolUse "" no; echo "|$?")" "|1"
  facts_track t1 "$repo" PreToolUse test no
  facts_track t1 "$repo" PreToolUse test yes
  expect "a test run counts ran, trusted or not" "$(got t1 '.turns[0].tests')" '{"ran":2,"passed":0,"failed":0}'
  facts_track t1 "$repo" PostToolUse test no
  facts_track t1 "$repo" PostToolUseFailure test no
  expect "no exit codes: nothing else counted" "$(got t1 '.turns[0].tests')" '{"ran":2,"passed":0,"failed":0}'
  facts_track t1 "$repo" PostToolUse "" yes
  facts_track t1 "$repo" PostToolUseFailure "" yes
  expect "no test flag: nothing counted" "$(got t1 '.turns[0].tests')" '{"ran":2,"passed":0,"failed":0}'
  facts_track t1 "$repo" PostToolUse test yes
  facts_track t1 "$repo" PostToolUseFailure test yes
  facts_track t1 "$repo" PostToolUseFailure test yes
  expect "trusted exit codes: passed and failed counted" "$(got t1 '.turns[0].tests')" '{"ran":2,"passed":1,"failed":2}'
  expect "a stop: the facts flag" "$(facts_track t1 "$repo" Stop "" no; echo "|$?")" "|0"
  expect "the turn ended" "$(got t1 '.turns[0] | has("endAt")')" true
  expect "a stop with a test flag: no facts flag" "$(facts_track t1 "$repo" Stop test no; echo "|$?")" "|1"
  expect "a stop with no open turn writes nothing: no flag" "$(facts_track t1 "$repo" Stop "" no; echo "|$?")" "|1"
  expect "a session end does nothing" "$(facts_track t2 "$repo" SessionEnd "" no; echo "|$?")" "|1"
  expect "a session end: no file" "$(ls "$FACTS" | grep -c '^t2')" 0
  expect "an empty folder does nothing" "$(facts_track t3 "" UserPromptSubmit "" no; echo "|$?")" "|1"
  expect "an empty folder: no file" "$(ls "$FACTS" | grep -c '^t3')" 0
  expect "an event it does not know: no flag" "$(facts_track t1 "$repo" Notification "" no; echo "|$?")" "|1"

  # Without git, or with Deskmates off: nothing.
  mkdir -p "$HOME/nogit"
  for t in grep mkdir mktemp mv rm rmdir date cat head sleep; do ln -s "$(command -v "$t")" "$HOME/nogit/$t"; done
  expect "no git: no git" "$(PATH="$HOME/nogit" deskmates_git; echo "|$?")" "|1"
  expect "no git writes nothing" "$(PATH="$HOME/nogit" facts_git_start g10 "$repo"; echo "|$?")" "|1"
  expect "no git, no file" "$(ls "$FACTS" | grep -c g10)" 0
  expect "a git found" "$(deskmates_git)" "$(command -v git)"
  rm "$HOME/.deskmates/on"
  expect "Deskmates off writes nothing" "$(facts_git_start g11 "$repo"; echo "|$?")" "|1"
  expect "Deskmates off: no turn" "$(facts_turn_start g1; echo "|$?")" "|1"
  expect "Deskmates off: no file" "$(ls "$FACTS" | grep -c g11)" 0
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

# No helper leaves a variable behind: the shell's variables before and after each public helper (run in this
# shell, as a translator runs them) differ only in the helper-private names (_facts_|_plan_…) and the documented results.
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
    grep -Ev '^(_facts_|_plan_|DESKMATES_GIT|DESKMATES_GIT_PATH|facts_root|facts_open)' | tr '\n' ' '
}
if [ -n "$found_jq" ] && command -v git > /dev/null; then
  lrepo="$HOME/leakrepo"
  mkdir -p "$lrepo/src"
  git init -q "$lrepo"
  echo one > "$lrepo/src/app.js"
  git -C "$lrepo" add -A
  git -C "$lrepo" -c user.name=Test -c user.email=test@example.com commit -q -m "First"
  # What the facts helpers set: facts_root and facts_open (facts_git_state), DESKMATES_GIT (deskmates_git).
  expect "leak: facts_file" "$(leaks facts_file s20)" ""
  expect "leak: facts_update" "$(leaks facts_update s20 "$SET")" ""
  expect "leak: facts_note" "$(leaks facts_note s20 '{kind: "reply", text: "Hi", from: "ABC-12", moves: false}')" ""
  expect "leak: deskmates_git" "$(leaks deskmates_git)" ""
  expect "leak: facts_git_start" "$(leaks facts_git_start s21 "$lrepo/src/")" ""
  expect "leak: facts_git_start, no repo" "$(leaks facts_git_start s22 "$HOME")" ""
  expect "leak: facts_turn_start" "$(leaks facts_turn_start s21)" ""
  expect "leak: facts_turn_test" "$(leaks facts_turn_test s21 ran)" ""
  expect "leak: facts_edit" "$(leaks facts_edit s21 "$lrepo/src/" "$lrepo/src/app.js")" ""
  expect "leak: facts_turn_end" "$(leaks facts_turn_end s21)" ""
  expect "leak: facts_track" "$(leaks facts_track s21 "$lrepo/src/" UserPromptSubmit "" yes)" ""
  expect "leak: facts_delete" "$(leaks facts_delete s21)" ""
fi

rm -rf "$HOME"
[ "$failed" = 0 ] && echo "facts-lib: ok"
exit "$failed"
