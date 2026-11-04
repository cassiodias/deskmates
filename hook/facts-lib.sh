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
