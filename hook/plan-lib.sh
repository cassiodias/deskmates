# The plan helpers a translator uses after hook/puppet-lib.sh, when its agent plans: a checklist of steps and a
# plan document, kept as one neutral file per session that the Spoon reads (model/plans.lua):
#   ~/.deskmates/plans/<session>.json
#   { "harness": "claude", "session": "…", "updatedAt": 1730700000,
#     "steps": [ { "id": "1", "title": "Write the failing test", "status": "pending|active|done" } ],
#     "plan": { "markdown": "…", "at": 1730700000 } }
# A plan is kept only while Deskmates runs (the Spoon's marker ~/.deskmates/on names its process), only with jq,
# and only while the session lives: it is deleted at SessionEnd, and by the Spoon after hours of silence.

# A helper keeps its working variables to itself: every one it sets is named _plan_<name>, so a translator that
# sources this may use any other name without a clash (tests/plan_lib.sh pins it).

PUPPET_PLANS="$PUPPET_DIR/plans"

# The plan file of session $1; nothing, and false, for an id that could name a path outside the plans folder.
plan_file() {
  case "$1" in ""|.|..|*[!A-Za-z0-9._-]*) return 1 ;; esac
  printf '%s/%s.json\n' "$PUPPET_PLANS" "$1"
}

# Changes session $1's plan (harness $2) with jq filter $3, given the payload as `.` and the current plan as
# $cur (a new one when there is none, or the file is broken); more jq arguments may follow (--arg, --rawfile).
# The filter makes the whole new plan. Written atomically, readable by its owner only. False, and nothing
# written, when Deskmates is off, there is no jq, the id is refused or the filter fails.
plan_update() {
  deskmates_on || return 1
  [ -n "$PUPPET_JQ" ] || return 1
  _plan_file=$(plan_file "$1") || return 1
  _plan_start=$(printf '{"harness":"%s","session":"%s","steps":[]}' "$2" "$1")
  _plan_filter=$3
  shift 3
  deskmates_json_update "$_plan_file" "$_plan_start" 'type == "object"' "$_plan_filter" "$@"
}

# Changes JSON file $1 with jq filter $4, given the payload as `.` and the current file as $cur: the file when
# it is JSON for which jq test $3 holds, else $2; more jq arguments may follow. The new file is kept only when
# the filter makes an object (its updatedAt set to now): written to a temp file and moved into place, readable
# by its owner only, one change at a time. False, and the file left as it was, when the filter fails.
deskmates_json_update() {
  _plan_file=$1 _plan_start=$2 _plan_valid=$3 _plan_filter=$4
  shift 4
  (umask 077; mkdir -p "${_plan_file%/*}") || return 1
  # Tool calls made together run their hooks at the same time: one change at a time, or one is lost.
  deskmates_lock "$_plan_file"
  _plan_cur=$_plan_start
  [ -s "$_plan_file" ] && _plan_cur=$("$PUPPET_JQ" -c "if $_plan_valid then . else error(\"not valid\") end" "$_plan_file" \
    2>/dev/null) || _plan_cur=$_plan_start
  _plan_written=1
  _plan_tmp=$(umask 077; mktemp "$_plan_file.XXXXXX") || { rmdir "$_plan_file.lock" 2>/dev/null; return 1; }
  if printf '%s' "$PUPPET_PAYLOAD" | "$PUPPET_JQ" -c --argjson cur "$_plan_cur" \
      --argjson now "${PUPPET_NOW:-$(date +%s)}" "$@" \
      "($_plan_filter) | if type == \"object\" then .updatedAt = \$now else error(\"not an object\") end" \
      > "$_plan_tmp" 2>/dev/null && [ -s "$_plan_tmp" ]; then
    mv -f "$_plan_tmp" "$_plan_file" && _plan_written=0
  fi
  rm -f "$_plan_tmp"
  rmdir "$_plan_file.lock" 2>/dev/null
  return "$_plan_written"
}

# Takes the lock of file $1 (a folder beside it: mkdir either makes it or fails, at once). A lock still there
# after about a second was left by a hook that was killed: it is taken over.
deskmates_lock() {
  _plan_tries=0
  until mkdir "$1.lock" 2>/dev/null; do
    _plan_tries=$((_plan_tries + 1))
    [ "$_plan_tries" -ge 40 ] && return 0
    sleep 0.025
  done
}

# Deletes session $1's plan, if it has one.
plan_delete() {
  _plan_file=$(plan_file "$1") || return 0
  rm -f "$_plan_file"
  return 0
}
