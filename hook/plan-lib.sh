# The plan helpers a translator uses after hook/puppet-lib.sh, when its agent plans: a checklist of steps and a
# plan document, kept as one neutral file per session that the Spoon reads (model/plans.lua):
#   ~/.deskmates/plans/<session>.json
#   { "harness": "claude", "session": "…", "updatedAt": 1730700000,
#     "steps": [ { "id": "1", "title": "Write the failing test", "status": "pending|active|done" } ],
#     "plan": { "markdown": "…", "at": 1730700000 } }
# A plan is kept only while Deskmates runs (the Spoon's marker ~/.deskmates/on names its process), only with jq,
# and only while the session lives: it is deleted at SessionEnd, and by the Spoon after hours of silence.

PUPPET_PLANS="$PUPPET_DIR/plans"

# The plan file of session $1; nothing, and false, for an id that could name a path outside the plans folder.
plan_file() {
  case "$1" in ""|.|..|*[!A-Za-z0-9._-]*) return 1 ;; esac
  printf '%s/%s.json\n' "$PUPPET_PLANS" "$1"
}

# True while Deskmates runs: the marker the Spoon writes at start names a process that is still there. A
# marker left by a Hammerspoon that crashed names none.
deskmates_on() {
  [ -f "$PUPPET_DIR/on" ] || return 1
  pid=$(head -n 1 "$PUPPET_DIR/on" 2>/dev/null)
  case "$pid" in ""|*[!0-9]*) return 1 ;; esac
  kill -0 "$pid" 2>/dev/null
}

# Changes session $1's plan (harness $2) with jq filter $3, given the payload as `.` and the current plan as
# $cur (a new one when there is none, or the file is broken); more jq arguments may follow (--arg, --rawfile).
# The filter makes the whole new plan. Written atomically, readable by its owner only. False, and nothing
# written, when Deskmates is off, there is no jq, the id is refused or the filter fails.
plan_update() {
  deskmates_on || return 1
  [ -n "$PUPPET_JQ" ] || return 1
  file=$(plan_file "$1") || return 1
  start=$(printf '{"harness":"%s","session":"%s","steps":[]}' "$2" "$1")
  filter=$3
  shift 3
  deskmates_json_update "$file" "$start" 'type == "object"' "$filter" "$@"
}

# Changes JSON file $1 with jq filter $4, given the payload as `.` and the current file as $cur: the file when
# it is JSON for which jq test $3 holds, else $2; more jq arguments may follow. The new file is kept only when
# the filter makes an object (its updatedAt set to now): written to a temp file and moved into place, readable
# by its owner only, one change at a time. False, and the file left as it was, when the filter fails.
deskmates_json_update() {
  file=$1 start=$2 valid=$3 filter=$4
  shift 4
  (umask 077; mkdir -p "${file%/*}") || return 1
  # Tool calls made together run their hooks at the same time: one change at a time, or one is lost.
  deskmates_lock "$file"
  cur=$start
  [ -s "$file" ] && cur=$("$PUPPET_JQ" -c "if $valid then . else error(\"not valid\") end" "$file" \
    2>/dev/null) || cur=$start
  written=1
  tmp=$(umask 077; mktemp "$file.XXXXXX") || { rmdir "$file.lock" 2>/dev/null; return 1; }
  if printf '%s' "$PUPPET_PAYLOAD" | "$PUPPET_JQ" -c --argjson cur "$cur" \
      --argjson now "${PUPPET_NOW:-$(date +%s)}" "$@" \
      "($filter) | if type == \"object\" then .updatedAt = \$now else error(\"not an object\") end" \
      > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
    mv -f "$tmp" "$file" && written=0
  fi
  rm -f "$tmp"
  rmdir "$file.lock" 2>/dev/null
  return "$written"
}

# Takes the lock of file $1 (a folder beside it: mkdir either makes it or fails, at once). A lock still there
# after about a second was left by a hook that was killed: it is taken over.
deskmates_lock() {
  tries=0
  until mkdir "$1.lock" 2>/dev/null; do
    tries=$((tries + 1))
    [ "$tries" -ge 40 ] && return 0
    sleep 0.025
  done
}

# Deletes session $1's plan, if it has one.
plan_delete() {
  file=$(plan_file "$1") || return 0
  rm -f "$file"
  return 0
}
