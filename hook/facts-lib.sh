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
  | (if $n.kind == "skill" or $n.kind == "subagent" then ($n.phaseFrom // $from | tostring) | phase else null end) as $p
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
  | if $p and $p != .tickets[$target].phase then
      .tickets[$target] |= (.phase = $p | .phaseAt = $now
        | .phases = ((.phases // {}) | if has($p) then . else .[$p] = $now end))
      | facts_line($target; "phase"; $p)
    else . end
  | if ($n.jira | type) == "string" and $n.jira != "" then .tickets[$target].jira = {status: ($n.jira | clean), at: $now}
    else . end
  | if ($n.kind | type) == "string" then facts_line($target; $n.kind; $n.text // "") else . end
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
# status. A note that does not move (a reply, a test run) never starts facts nor moves a phase that waits.
# False, and nothing written, for a null note, or one with no ticket to hang it on (a reply in a session with
# no facts yet), and as facts_update.
facts_note() {
  session=$1 note=$2
  shift 2
  facts_update "$session" "$FACTS_DEFS ($note) as \$n
    | if \$n == null then error(\"no note\") else \$cur | facts_apply(\$n) end" "$@"
}
