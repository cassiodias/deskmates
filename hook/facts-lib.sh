# The facts helpers a translator uses after hook/puppet-lib.sh and hook/plan-lib.sh: what a session is working
# on (its tickets, their phases and Jira status, and a short timeline), worked out from the events its agent
# already sends, kept as one file per session that the Spoon reads (model/facts.lua):
#   ~/.deskmates/facts/<session>.json
#   { "current": "ABC-12",
#     "tickets": { "ABC-12": { "phase": "dev", "phaseAt": 1730700000, "phases": { "plan": …, "dev": … },
#                              "jira": { "status": "In Dev", "at": … }, "seen": … } },
#     "timeline": [ { "at": …, "ticket": "ABC-12", "kind": "reply", "text": "…", "phase": "dev" } ],
#     "updatedAt": 1730700000 }
# Only derived facts are kept, never prompts or file contents. Like plans: only while Deskmates runs, only with
# jq, deleted at SessionEnd and by the Spoon after hours of silence.

PUPPET_FACTS="$PUPPET_DIR/facts"

# The facts file of session $1; nothing, and false, for an id that could name a path outside the facts folder.
facts_file() {
  case "$1" in ""|.|..|*[!A-Za-z0-9._-]*) return 1 ;; esac
  printf '%s/%s.json\n' "$PUPPET_FACTS" "$1"
}

# Changes session $1's facts with jq filter $2, given the payload as `.` and the current facts as $cur (a new
# one when there is none, or the file is not facts); more jq arguments may follow. The filter makes the whole
# new file. False, and nothing written, when Deskmates is off, there is no jq, the id is refused or the filter
# fails.
facts_update() {
  deskmates_on || return 1
  [ -n "$PUPPET_JQ" ] || return 1
  file=$(facts_file "$1") || return 1
  filter=$2
  shift 2
  deskmates_json_update "$file" '{"tickets":{},"timeline":[]}' \
    'type == "object" and (.tickets | type) == "object" and (.timeline | type) == "array"' "$filter" "$@"
}

# Deletes session $1's facts, if it has any.
facts_delete() {
  file=$(facts_file "$1") || return 0
  rm -f "$file"
  return 0
}

# The jq defs that turn a note into facts; a translator may use tickets, phase and clean in its own filters.
#   tickets: the ticket keys in a text, first first: whole words like ABC-12, minus words that only look like
#            one (UTF-8, SHA-256, RFC-2119…).
#   phase:   the phase a skill's name or a subagent's description names, by whole words: "plan", "dev" or
#            "review" (the later phase wins when it names two), or null.
#   clean:   a text as the card may show it: no control characters, 200 characters at most.
FACTS_DEFS='
def tickets: [match("(?<![A-Za-z0-9])[A-Z][A-Z0-9]{1,9}-[0-9]+(?![A-Za-z0-9])"; "g").string
  | select(split("-")[0] as $k | ["UTF", "SHA", "ISO", "RFC", "CVE", "HTTP", "TLS", "AES", "RSA", "MD"]
    | any(.[]; . == $k) | not)];
def phase: (ascii_downcase | [scan("[a-z0-9]+")]) as $w
  | if any($w[]; IN("qa", "review", "reviewer", "test", "tests", "testing", "tester")) then "review"
    elif any($w[]; IN("dev", "developer", "develop", "implement", "implementation", "build", "builder")) then "dev"
    elif any($w[]; IN("plan", "planner", "planning", "engineer", "architect")) then "plan"
    else null end;
def clean: tostring | gsub("[[:cntrl:]]"; "") | .[0:200];
def facts_line($ticket; $kind; $text): .timeline = [{at: $now, ticket: $ticket, kind: $kind, text: ($text | clean),
  phase: .tickets[$ticket].phase}] + .timeline;
def facts_apply($n):
  ($n.from // "" | tostring) as $from
  | (if ($n.ticket | type) == "string" and ($n.ticket | tickets) == [$n.ticket] then $n.ticket
     else ($from | tickets | .[0]) end) as $t
  | (if $n.kind == "skill" or $n.kind == "subagent" or $n.ends then ($n.phaseFrom // $from | tostring) | phase
     else null end) as $p
  | if $n.ends and $p == null then error("no lane to end") else . end
  # A reply or a test run never starts facts: a ticket it names counts once the session has a current ticket.
  | (if $n.moves then (if $t then $t elif $p then (.current // "-") else .current end)
     elif $t and (.tickets[$t] != null or .current != null) then $t
     else (.current // (if .tickets["-"] then "-" else null end)) end) as $target
  | if $target == null then error("nothing to hang it on") else . end
  # A phase that waited for a ticket moves to the first one that appears.
  | if $n.moves and $target != "-" and .tickets["-"] then
      .tickets["-"] as $w
      | .tickets[$target] = ((.tickets[$target] // {}) as $x | $x + ({phase: ($x.phase // $w.phase),
          phaseAt: ($x.phaseAt // $w.phaseAt),
          phases: (($w.phases // {}) as $a | ($x.phases // {}) as $b
            | reduce (($a + $b) | keys[]) as $k ({}; .[$k] = ([$a[$k], $b[$k]] | map(select(. != null)) | min)))}
        | with_entries(select(.value != null))))
      | del(.tickets["-"])
      | .timeline |= map(if .ticket == "-" then .ticket = $target else . end)
    else . end
  | if $n.moves and $target != "-" then .current = $target else . end
  | .tickets[$target] = ((.tickets[$target] // {}) | .seen = $now)
  # A lane ends (it gets its start then too, when that was missed); starting it again reopens it.
  | if $n.ends then
      .tickets[$target] |= (.phases = ((.phases // {}) | if has($p) then . else .[$p] = $now end)
        | .ends = ((.ends // {}) | .[$p] = ({at: $now, outcome: ($n.text // "" | clean)}
          + (if ($n.verdict | type) == "string" and $n.verdict != "" then {verdict: ($n.verdict | clean)} else {} end))))
    elif $p then
      .tickets[$target] |= (if .ends then .ends |= del(.[$p]) else . end)
      | if $p != .tickets[$target].phase then
          .tickets[$target] |= (.phase = $p | .phaseAt = $now
            | .phases = ((.phases // {}) | if has($p) then . else .[$p] = $now end))
          | facts_line($target; "phase"; $p)
        else . end
    else . end
  | if ($n.jira | type) == "string" and $n.jira != "" then .tickets[$target].jira = {status: ($n.jira | clean), at: $now}
    else . end
  | if ($n.kind | type) == "string" then facts_line($target; $n.kind; $n.text // "") else . end
  | if $n.ends then .timeline[0].phase = $p else . end
  | .timeline |= .[0:30]
  | .current as $c
  | (if $c != null and (.tickets | has($c)) then 1 else 0 end) as $kept
  | if (.tickets | length) > 10 then
      .tickets |= ((to_entries | map(select(.key == $c)))
        + (to_entries | map(select(.key != $c)) | sort_by(-(.value.seen // 0)) | .[0:(10 - $kept)]) | from_entries)
    else . end;
'

# Applies the note jq filter $2 makes from the payload to session $1's facts (more jq arguments may follow). A
# note is { kind, text, from, moves, ticket?, jira? }: kind is the timeline line's kind ("skill", "subagent",
# "jira", "tests", "reply", or null for none), text its text, from the text tickets and the phase are looked for
# in, phaseFrom the text the phase is looked for in when it is not all of from (a skill's name, not its
# arguments), moves whether its ticket becomes the current one, ticket a key given outright (Jira's), jira a
# status, ends true when the note ends the lane its phase words name (with verdict, a verdict the agent wrote).
# A note that does not move (a reply, a test run, an end) never starts facts nor moves a phase that waits.
# False, and nothing written, for a null note, or one with no ticket to hang it on (a reply in a session with
# no facts yet), and as facts_update.
facts_note() {
  session=$1 note=$2
  shift 2
  facts_update "$session" "$FACTS_DEFS ($note) as \$n
    | if \$n == null then error(\"no note\") else \$cur | facts_apply(\$n) end" "$@"
}

# Git facts: the repo a session works in, its turns and the paths its agent edited, kept beside the tickets:
#   "git":   { "root": "/abs/repo", "base": "<sha at the first event>", "dirtyAtStart": ["src/app.js"],
#              "folder": "<the session's folder, as given>", "prefix": "<its place in the repo: src/, or empty>",
#              "top": "<the root as the folder spells it (/tmp/alias for /tmp/alias/src), when checked; else null>" },
#   "seen":  { "src/app.js": true },
#   "turns": [ { "at": …, "endAt": …, "head": "<sha at its start>", "files": ["src/app.js"],
#                "tests": { "ran": 2, "passed": 1, "failed": 1 }, "commits": [ { "hash": "a1b2c3d", "subject": "…" } ] } ]
# Turns newest first; the open one has no endAt. Paths are relative to the root, normalised. Every git call is
# made with GIT_OPTIONAL_LOCKS=0, so it never takes the index.lock the agent's own git needs. Each helper is
# true when it wrote, false (and nothing written) when Deskmates is off, there is no jq or git, the folder is
# no repo, or there was nothing to write.

FACTS_NL='
'

# The git to run, also kept in DESKMATES_GIT: nothing, and false, when there is none, or it is Apple's shim with
# no developer tools behind it (running it would open an install dialog). Looked up once per hook, and again
# only when PATH changes.
deskmates_git() {
  if [ "${DESKMATES_GIT_PATH-}" != "$PATH" ] || [ -z "${DESKMATES_GIT_PATH+set}" ]; then
    DESKMATES_GIT_PATH=$PATH
    DESKMATES_GIT=$(command -v git) || DESKMATES_GIT=
    if [ "$DESKMATES_GIT" = /usr/bin/git ] && ! xcode-select -p > /dev/null 2>&1; then DESKMATES_GIT=; fi
  fi
  [ -n "$DESKMATES_GIT" ] || return 1
  printf '%s\n' "$DESKMATES_GIT"
}

# Runs git $1 with the rest as its arguments, never taking an optional lock.
facts_run_git() {
  bin=$1
  shift
  GIT_OPTIONAL_LOCKS=0 "$bin" "$@" 2>/dev/null
}

# Sets git to the git to run, when git facts may be written now: Deskmates runs, jq and git are there.
facts_git_ready() {
  deskmates_on && [ -n "$PUPPET_JQ" ] && deskmates_git > /dev/null || return 1
  git=$DESKMATES_GIT
}

# The jq defs of git facts.
#   nul_list:  NUL-separated git output as a list of its parts, the empty ones left out.
#   porcelain: `git status --porcelain -z` output as its paths; a rename or copy gives both.
#   commits:   `git log -z --format='%h%x09%s'` output as [{hash, subject}], subjects of 120 characters at most.
#   open_turn: true when the newest turn is still open.
#   end_turn($commits): the newest turn ended now with those commits.
#   rel($root; $folder; $prefix; $top): a path an edit names, relative to the root and normalised; null when it
#              is outside the root ($prefix null: the folder is not in that repo, so only paths under the root
#              count). $top, when not null, is another spelling of the root, checked at start: a path beside a
#              subfolder reached through a symlink still lands in the repo.
FACTS_GIT_DEFS='
def nul_list: split("\u0000") | map(select(. != ""));
def porcelain: split("\u0000") | reduce .[] as $e ({out: [], orig: false};
  if .orig then .out += [$e] | .orig = false
  elif ($e | length) > 3 then .out += [$e[3:]] | .orig = ($e[0:2] | test("[RC]"))
  else . end) | .out;
def commits: nul_list | map(index("\t") as $i | select($i != null)
  | {hash: .[0:$i], subject: (.[$i + 1:] | gsub("[[:cntrl:]]"; "") | .[0:120])});
def open_turn: (.turns // [])[0] | . != null and (has("endAt") | not);
def end_turn($commits): .turns[0] += {endAt: $now, commits: $commits};
def rel($root; $folder; $prefix; $top):
  ($folder | rtrimstr("/")) as $f
  | (if startswith($root + "/") then .[($root | length) + 1:]
     elif $prefix == null then null
     elif $f != "" and startswith($f + "/") then $prefix + .[($f | length) + 1:]
     elif ($top | type) == "string" and $top != "" and startswith($top + "/") then .[($top | length) + 1:]
     elif startswith("/") then null
     else $prefix + . end)
  | if . == null then null else
      reduce split("/")[] as $s ([];
        if . == null then null
        elif $s == "" or $s == "." then .
        elif $s == ".." then (if length == 0 then null else .[0:-1] end)
        else . + [$s] end)
      | if . == null or length == 0 then null else join("/") end
    end;
'

# Records session $1's repo, once: its root, the commit it starts from (base), the paths already changed or
# untracked then (500 at most), and its folder $2 with that folder's place in the repo (so an edit from it asks
# git nothing). A repo with no commit yet gives nothing: the base is taken at the first event after the first
# commit.
facts_git_start() {
  file=$(facts_file "$1") || return 1
  grep -q '"git":{' "$file" 2>/dev/null && return 1
  facts_git_ready || return 1
  out=$(facts_run_git "$git" -C "$2" rev-parse --show-toplevel --show-prefix HEAD) || return 1
  case "$out" in *"$FACTS_NL"*"$FACTS_NL"*) ;; *) return 1 ;; esac
  root=${out%%"$FACTS_NL"*} base=${out##*"$FACTS_NL"}
  prefix=${out#*"$FACTS_NL"}
  prefix=${prefix%"$FACTS_NL"*}
  # The root as the folder spells it (the folder minus its prefix), kept only when it is the root for real.
  top=
  folder=${2%/} sub=${prefix%/}
  if [ -n "$sub" ]; then
    case "$folder" in
      ?*/"$sub") top=${folder%/"$sub"}
        [ "$(cd -P -- "$top" 2>/dev/null && pwd -P)" = "$root" ] || top= ;;
    esac
  fi
  status=$(mktemp) || return 1
  if facts_run_git "$git" -C "$root" status --porcelain -z --untracked-files=all > "$status"; then
    facts_update "$1" "$FACTS_GIT_DEFS \$cur | if .git then error(\"kept\") else
      .git = {root: \$root, base: \$base, dirtyAtStart: (\$status | porcelain | unique | .[0:500]),
        folder: \$folder, prefix: \$prefix, top: (if \$top == \"\" then null else \$top end)} end" \
      --arg root "$root" --arg base "$base" --arg folder "$2" --arg prefix "$prefix" --arg top "$top" \
      --rawfile status "$status"
    written=$?
  else
    written=1
  fi
  rm -f "$status"
  return "$written"
}

# Reads session $1's git facts into facts_root (its repo's root) and facts_open (the head its open turn started
# from, empty when no turn is open); false when the session has no git facts.
facts_git_state() {
  file=$(facts_file "$1") || return 1
  grep -q '"git":{' "$file" 2>/dev/null || return 1
  state=$("$PUPPET_JQ" -r "$FACTS_GIT_DEFS"' (.git.root | strings), (if open_turn then .turns[0].head else "" end)' \
    "$file" 2>/dev/null) || return 1
  facts_root=${state%%"$FACTS_NL"*} facts_open=
  case "$state" in *"$FACTS_NL"*) facts_open=${state#*"$FACTS_NL"} ;; esac
  [ -n "$facts_root" ]
}

# Changes session $1's turns with jq filter $2 (given $cur and $commits: what the open turn committed since it
# started, as git $3 says), after facts_git_state; more jq arguments may follow.
facts_turn_change() {
  session=$1 filter=$2 git=$3
  shift 3
  log=$(mktemp) || return 1
  [ -z "$facts_open" ] || facts_run_git "$git" -C "$facts_root" log -z --format='%h%x09%s' -n 20 "$facts_open..HEAD" > "$log"
  facts_update "$session" "$FACTS_GIT_DEFS (\$log | commits) as \$commits | \$cur | $filter" \
    --rawfile log "$log" "$@"
  written=$?
  rm -f "$log"
  return "$written"
}

# Opens a turn in session $1 from the commit it is at now; a turn still open is ended first, as facts_turn_end
# would. The newest 30 turns are kept.
facts_turn_start() {
  facts_git_ready || return 1
  facts_git_state "$1" || return 1
  head=$(facts_run_git "$git" -C "$facts_root" rev-parse HEAD) || return 1
  facts_turn_change "$1" '(if open_turn then end_turn($commits) else . end)
    | .turns = ([{at: $now, head: $head, files: [], tests: {ran: 0, passed: 0, failed: 0}, commits: []}]
      + (.turns // []))[0:30]' "$git" --arg head "$head"
}

# Ends session $1's open turn: its end, and the commits made since it started (20 at most). Nothing without
# an open turn.
facts_turn_end() {
  facts_git_ready || return 1
  facts_git_state "$1" && [ -n "$facts_open" ] || return 1
  facts_turn_change "$1" 'if open_turn then end_turn($commits) else error("no open turn") end' "$git"
}

# Counts a test run in session $1's open turn: $2 is ran, passed or failed. Nothing without an open turn.
facts_turn_test() {
  case "$2" in ran|passed|failed) ;; *) return 1 ;; esac
  file=$(facts_file "$1") || return 1
  grep -q '"turns":\[{' "$file" 2>/dev/null || return 1
  facts_update "$1" "$FACTS_GIT_DEFS \$cur | if open_turn then .turns[0].tests[\$k] += 1
    else error(\"no open turn\") end" --arg k "$2"
}

# Adds the paths an edit in session $1 named, from its folder $2, to the open turn's files and to the paths
# seen (500 at most each); a path outside the repo is left out. Nothing when none is left.
facts_edit() {
  session=$1 folder=$2
  shift 2
  file=$(facts_file "$session") || return 1
  grep -q '"git":{' "$file" 2>/dev/null || return 1
  [ "$#" -gt 0 ] || return 1
  facts_git_ready || return 1
  # The folder's place in the repo: recorded at start for the session's folder (a JSON string with nothing to
  # escape is found as written), else asked of git, when the folder is in the session's repo at all.
  gtop='' prefix=''
  case "$folder" in
    *[\"\\]*) recorded=1 ;;
    *) grep -qF "\"folder\":\"$folder\"" "$file"; recorded=$? ;;
  esac
  if [ "$recorded" != 0 ]; then
    out=$(facts_run_git "$git" -C "$folder" rev-parse --show-toplevel --show-prefix) || out=
    gtop=${out%%"$FACTS_NL"*}
    case "$out" in *"$FACTS_NL"*) prefix=${out#*"$FACTS_NL"} ;; esac
  fi
  count=$# n=0
  for path do
    set -- "$@" --arg "path$n" "$path"
    n=$((n + 1))
  done
  shift "$count"
  facts_update "$session" "$FACTS_GIT_DEFS \$cur | .git.root as \$root
    | (\$folder == .git.folder and (.git.prefix | type) == \"string\") as \$own
    | (if \$own then .git.prefix elif \$gtop != \"\" and \$gtop == \$root then \$prefix else null end) as \$pre
    | (if \$own then .git.top else null end) as \$top
    | [\$ARGS.named | to_entries[] | select(.key | test(\"^path[0-9]+\$\"))] | sort_by(.key[4:] | tonumber)
    | map(.value | rel(\$root; \$folder; \$pre; \$top) | select(. != null)) as \$paths
    | if \$paths == [] or (\$root | type) != \"string\" then error(\"nothing to add\") else . end
    | \$cur
    | .seen = reduce \$paths[] as \$p (.seen // {}; if has(\$p) or length >= 500 then . else .[\$p] = true end)
    | if open_turn then .turns[0].files = reduce \$paths[] as \$p (.turns[0].files // [];
        if any(.[]; . == \$p) or length >= 500 then . else . + [\$p] end) else . end" \
    --arg folder "$folder" --arg gtop "$gtop" --arg prefix "$prefix" "$@"
}
