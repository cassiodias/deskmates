#!/bin/sh
# Fills a Claude session's facts from its transcript, for the turns the hooks did not record (a session started
# before Deskmates watched, or one that ran while it was off). The Spoon runs it when a card opens:
#   hook/backfill.sh <session>   prints "ok <turns added>", "none" or "error <why>"
# Sourced (tests), it only defines its helpers. See the design: -mem specs/2026-11-07-transcript-backfill-design.md.

# Its own folder, through any link (Hammerspoon runs it as …/Spoons/Deskmates.spoon/../hook/backfill.sh, and that
# Spoon is a link to the clone's): a logical cd would take the .. before the link.
_backfill_dir=$(cd -P "$(dirname "$0")" 2>/dev/null && pwd -P)
case "$_backfill_dir" in */hook) ;; *) _backfill_dir=$(pwd)/hook ;; esac
. "$_backfill_dir/puppet-lib.sh"
. "$_backfill_dir/plan-lib.sh"
. "$_backfill_dir/facts-lib.sh"

# The byte offset just after the last complete line of file $1 (a line still being written is left for later).
backfill_size() {
  _backfill_total=$(wc -c < "$1" 2>/dev/null | tr -d ' ') || return 1
  [ -n "$_backfill_total" ] || return 1
  [ "$_backfill_total" -gt 0 ] || { echo 0; return 0; }
  _backfill_tail=$(tail -c 1 "$1" | od -An -c | tr -d ' ')
  if [ "$_backfill_tail" = '\n' ]; then echo "$_backfill_total"; return 0; fi
  # The last newline: the size minus the length of the cut line after it.
  _backfill_cut=$(tail -n 1 "$1" | wc -c | tr -d ' ')
  echo $((_backfill_total - _backfill_cut))
}

# The jq that reads transcript records (one JSON per line, as text; lines that are not JSON skipped), with the
# subagents' records as $sub, into the reading: { cwd, prompts, turns, notes, tests }. See backfill_read.
BACKFILL_READ='
def ts: (.timestamp // "") | tostring | sub("\\.[0-9]+Z$"; "Z") | (try fromdateiso8601 catch null);
def text_of: if type == "string" then . elif type == "array" then map(select(type == "object" and .type == "text") | .text) | join("\n") else "" end;
def sentence: split("\n") | map(select(test("^\\s*$") | not) | select(test("^\\s*#") | not)) | (.[0] // "")
  | gsub("[#*`|]"; "") | sub("^[\\s>-]*"; "") | sub("(?<p>[.!?])\\s.*$"; "\(.p)") | .[0:90];
# What Claude Code writes as a user record but no one typed to the agent: a compaction summary, a ! command and
# its output, a local command'"'"'s output, an interruption note.
def not_typed: (.message.content | text_of) as $t | .isCompactSummary == true
  or ($t | test("^\\s*<(bash-input|bash-stdout|bash-stderr|local-command-stdout|local-command-stderr|local-command-caveat)>"))
  or ($t | test("^\\[Request interrupted"));
def is_prompt: .type == "user" and (.isMeta != true) and (.isSidechain != true)
  and ((.message.content | type) == "string"
    or ((.message.content | type) == "array" and (.message.content | any(.type == "tool_result") | not)
      and (.message.content | any(.type == "text"))))
  and (not_typed | not);
# A record of the agent'"'"'s own work in a turn: what it said, or what a tool gave back to it.
def is_work: .type == "assistant" or (.type == "user" and (.message.content | type) == "array"
  and (.message.content | any(.type == "tool_result")));
def command: (.message.content | text_of) as $t
  | (($t | capture("<command-name>/?(?<c>[^<]+)</command-name>") | .c)
    // ($t | capture("^/(?<c>[A-Za-z0-9:_-]+)(\\s|$)") | .c) // null);
def prompt_text: (.message.content | text_of) as $t
  | if ($t | test("<command-name>")) then "/" + command + " " + (($t | capture("<command-args>(?<a>[^<]*)</command-args>") | .a) // "")
    else $t end;
[inputs | fromjson? | select(type == "object")] as $all
| [$sub[] | fromjson? | select(type == "object")] as $subs
| [$all[] | select(ts != null)] as $recs
# A /command run by Claude Code itself (/clear, /plugin…) is followed by its local_command record: no prompt.
| [range(0; $recs | length) as $i | $recs[$i] | select(is_prompt)
    | select((command != null and ($recs[$i + 1:$i + 3] | any(.type == "system" and .subtype == "local_command"))) | not)
    | {at: ts, command: command, prompt: prompt_text,
       notice: (((.message.content | text_of) | capture("<task-notification>[\\s\\S]*<tool-use-id>(?<id>[^<]+)</tool-use-id>") | .id) // null)}] as $p
| ([$recs[], $subs[] | select(.type == "user" and (.message.content | type) == "array") | ts as $t
    | .toolUseResult as $tur | .message.content[] | select(.type == "tool_result")
    | {key: .tool_use_id, value: {at: $t, text: (.content | text_of), error: (.is_error == true),
        response: ($tur // .content)}}] | from_entries) as $results
| [$recs[], $subs[] | select(.type == "assistant") | ts as $t | (.isSidechain == true) as $side
    | .message.content[]? | select(.type == "tool_use") | {at: $t, id, name, input, side: $side}] as $uses
| ($p | map(.at)) as $starts
| def span($i): [$starts[$i], ($starts[$i + 1] // 1e18)];
  def turn_of($t): ([range(0; $starts | length) | select($starts[.] <= $t)] | last);
  [range(0; $p | length) as $i | span($i) as [$a, $b]
    | [$recs[] | ts as $t | select($t > $a and $t < $b)] as $in
    | ([$in[] | select(.type == "system" and .subtype == "turn_duration") | ts] | first) as $done
    | ([$in[] | select(.type == "assistant" and (.isSidechain != true)) | .message.content | text_of | select(. != "")] | last) as $last
    | {at: $a, endAt: ($done // ([$in[] | select(is_work) | ts] | last)), reply: (if $last then ($last | sentence) else null end),
       edits: [$uses[] | select(.name == "Write" or .name == "Edit" or .name == "MultiEdit" or .name == "NotebookEdit")
         | select(turn_of(.at) == $i) | (.input.file_path // .input.notebook_path // empty) | tostring] | unique}] as $turns
| {cwd: ([$recs[] | .cwd | strings] | first),
   prompts: [$p[] | {at, command: (if .notice then null else .command end)}],
   turns: $turns,
   notes: ([
     ($p[] | select(.command != null and .notice == null) | . as $x | {at: $x.at, note: ({prompt: $x.prompt} | claude_command_note($x.command))}),
     # A background agent ends when its task notification comes (its result at launch only said it started): as a
     # prompt, or queued as an attachment (newer Claude Code).
     ([($p[] | select(.notice != null) | {at, id: .notice, text: .prompt}),
       ($recs[] | select(.type == "attachment" and .attachment.type? == "queued_command")
         | (.attachment.prompt // "" | tostring) as $t
         | ($t | capture("<task-notification>[\\s\\S]*<tool-use-id>(?<id>[^<]+)</tool-use-id>") | .id) as $id
         | {at: ts, id: $id, text: $t})][]
       | . as $x | ($uses[] | select(.id == $x.id and (.name == "Agent" or .name == "Task"))) as $u
       | ($u.input.description // "" | tostring) as $d | select($d != "")
       | (($x.text | capture("<result>(?<r>[\\s\\S]*?)</result>") | .r) // ($x.text | capture("<summary>(?<r>[\\s\\S]*?)</summary>") | .r) // "") as $text
       | {at: $x.at, note: ({last_assistant_message: $text} | claude_done_note($d; ($text | sentence)))}),
     ($uses[] | select(.side | not) | . as $u | $results[$u.id] as $r
       | if $u.name == "Skill" then {at: $u.at, note: ({tool_input: $u.input} | claude_skill_note)}
         elif $u.name == "Agent" or $u.name == "Task" then
           {at: $u.at, note: ({tool_input: $u.input} | claude_agent_note)},
           (($u.input.description // "" | tostring) as $d | select($d != "" and $r != null)
             | select(($r.response | type) != "object" or $r.response.status != "async_launched")
             | {at: $r.at, note: ({last_assistant_message: $r.text} | claude_done_note($d; ($r.text | sentence)))})
         elif ($u.name | test("^mcp__.*Jira")) and $r != null then
           {at: $r.at, note: ({tool_input: $u.input, tool_response: $r.response} | claude_jira_note)}
         elif $u.name == "ExitPlanMode" and $r != null and ($r.error | not) then {at: $r.at, note: ({} | claude_plan_note)}
         else empty end),
     ($turns[] | select(.reply != null and .endAt != null) | . as $t | {at: $t.endAt, note: ({} | claude_reply_note($t.reply))})
   ] | map(select(.note != null and .at != null)) | sort_by(.at)),
   tests: [$uses[] | select(.name == "Bash") | (.input.command // "" | tostring) as $c
     | select($c | test("(^|[^A-Za-z])(test|pytest|jest|vitest|mocha|rspec|tox|phpunit)")) | $results[.id] as $r
     | {at: ($r.at // .at), command: $c, failed: ($r.error // false)}]}
'

# The reading of transcript $1 from byte $2 to byte $3 (and all of its subagents' transcripts), as JSON.
backfill_read() {
  _backfill_subs=$(mktemp) || return 1
  for _backfill_f in "${1%.jsonl}"/subagents/agent-*.jsonl; do
    [ -f "$_backfill_f" ] && cat "$_backfill_f" >> "$_backfill_subs"
  done
  { [ "$3" -gt "$2" ] && tail -c +"$(($2 + 1))" "$1" | head -c "$(($3 - $2))"; } |
    "$PUPPET_JQ" -nRc --rawfile subtext "$_backfill_subs" \
      "$FACTS_DEFS $FACTS_CLAUDE_DEFS (\$subtext | split(\"\\n\") | map(select(. != \"\"))) as \$sub | $BACKFILL_READ"
  _backfill_rc=$?
  rm -f "$_backfill_subs"
  return "$_backfill_rc"
}

# The transcript of session $1: where Claude Code keeps it, in the folder of the project it ran in.
backfill_find() {
  for _backfill_t in "$HOME"/.claude/projects/*/"$1".jsonl; do
    [ -f "$_backfill_t" ] && { printf '%s\n' "$_backfill_t"; return 0; }
  done
  return 1
}

# The jq that turns a reading into what the facts gain, given $cur (the facts now; {} when none), $real (the
# indexes of the reading's test candidates that are test runs), $to (the offset read up to) and $gaps (the prompt
# times that have no turn, the newest 30 only: the facts keep 30 turns): { tickets, current, timeline, turns,
# lastAt, upTo }. Every note is replayed in time
# order through facts_apply, at its own time.
BACKFILL_BUILD='
def apply_at($now; $n): '"$FACTS_DEFS"' facts_apply($n);
. as $r
| ($r.tests | to_entries | map(select(.key as $k | any($real[]; . == $k))) | map(.value)) as $tests
| ($r.prompts | map(.at)) as $starts
| def turn_of($t): ([range(0; $starts | length) | select($starts[.] <= $t)] | last);
  ([$r.notes[], ($tests[] | . as $t | {at: $t.at, note: ({} | claude_tests_note(if $t.failed then "failed" else "passed" end))})]
    | sort_by(.at)) as $notes
| (reduce $notes[] as $x ({tickets: {}, timeline: []}; . as $f | try ($f | apply_at($x.at; $x.note)) catch $f)) as $replay
| [range(0; $r.turns | length) as $i | $r.turns[$i] | select(.at as $a | any($gaps[]; . == $a))
    | ($gitturns[.at | tostring] // {}) as $g
    | {at, fromTranscript: true, commits: ($g.commits // []),
       files: (if $git then [.edits[] | rel($git.root; $git.folder; $git.prefix; $git.top) | select(. != null)] | unique
         else [] end),
       tests: ([$tests[] | select(turn_of(.at) == $i)] | {ran: length, passed: map(select(.failed | not)) | length,
         failed: map(select(.failed)) | length})}
      + (if .endAt then {endAt} else {} end) + (if $g.head then {head: $g.head} else {} end)] as $turns
| {tickets: $replay.tickets, current: $replay.current, timeline: $replay.timeline, turns: $turns,
   lastAt: ([$r.prompts[].at, $r.notes[].at, ($r.turns[] | .endAt // .at)] | max), upTo: $to,
   git: (if $git and $git.fromTranscript then $git else null end), moveBase: $move}
'

# The facts after a backfill $b: tickets and steps from the replay (when it found any), its timeline lines and
# the facts' own lines newer than the transcript, the hooks' turns kept and the transcript's added, newest first.
FACTS_BACKFILL_DEFS='
def backfill_merge($b; $now):
  (if ($b.tickets | length) > 0 then .tickets = $b.tickets | .current = $b.current else . end)
  | .timeline = (($b.timeline + [(.timeline // [])[] | select(.at > $b.lastAt)]) | sort_by(-.at) | .[0:30])
  | .turns = (((.turns // []) + $b.turns) | sort_by(-.at) | .[0:30])
  | if .turns == [] then del(.turns) else . end
  | if $b.git and ((.git | not) or $b.moveBase) then .git = $b.git else . end
  | .backfill = {upTo: $b.upTo, at: $now};
'

# Git for a backfill, from reading $1 (a file), the facts now $2 and the gap prompt times $3, into the files
# $4.git (the repo: the facts' own, or one found from the transcript's folder with its base when the session
# started, marked fromTranscript; null for none) and $4.turns ({ "<turn start>": { head, commits } } for the gap
# turns: the commit at their start and the commits made between their start and end, by git log).
backfill_git() {
  printf 'null' > "$4.git"
  printf '{}' > "$4.turns"
  printf 'false' > "$4.move"
  facts_git_ready || return 0
  _backfill_g=$(printf '%s' "$2" | "$PUPPET_JQ" -c '.git // empty')
  # The hooks' base is newer than the session (they started watching late): when the transcript's first prompt
  # comes more than 5 s before the hooks' oldest turn, the base moves back to the commit at that prompt; what was
  # dirty then is not known.
  _backfill_first=$("$PUPPET_JQ" -r '.prompts[0].at // empty' "$1")
  _backfill_oldest=$(printf '%s' "$2" | "$PUPPET_JQ" -r 'if .git and (.git.fromTranscript != true) then ([.turns[]?.at] | min // empty) else empty end')
  if [ -n "$_backfill_g" ] && [ -n "$_backfill_first" ] && [ -n "$_backfill_oldest" ] &&
      [ "$_backfill_first" -lt $((_backfill_oldest - 5)) ]; then
    _backfill_root=$(printf '%s' "$_backfill_g" | "$PUPPET_JQ" -r .root)
    _backfill_base=$(facts_run_git "$_facts_git" -C "$_backfill_root" rev-list -1 --before="@$_backfill_first" HEAD)
    _backfill_old=$(printf '%s' "$_backfill_g" | "$PUPPET_JQ" -r .base)
    # Only when the hooks really started late: the commit at the first prompt comes before theirs. Hooks that
    # watched from the start but kept only their newest 30 turns already have that commit, and what was dirty then.
    if [ -n "$_backfill_base" ] && [ "$_backfill_base" != "$_backfill_old" ] &&
        facts_run_git "$_facts_git" -C "$_backfill_root" merge-base --is-ancestor "$_backfill_base" "$_backfill_old"; then
      _backfill_g=$(printf '%s' "$_backfill_g" | "$PUPPET_JQ" -c --arg base "$_backfill_base" \
        '.base = $base | .dirtyAtStart = [] | .fromTranscript = true')
      printf 'true' > "$4.move"
    fi
  fi
  if [ -z "$_backfill_g" ]; then
    _backfill_cwd=$("$PUPPET_JQ" -r '.cwd // empty' "$1")
    [ -n "$_backfill_cwd" ] && [ -n "$_backfill_first" ] || return 0
    _backfill_out=$(facts_run_git "$_facts_git" -C "$_backfill_cwd" rev-parse --show-toplevel --show-prefix) || return 0
    _backfill_root=${_backfill_out%%"$FACTS_NL"*}
    _backfill_prefix=${_backfill_out#*"$FACTS_NL"}
    [ "$_backfill_prefix" = "$_backfill_out" ] && _backfill_prefix=
    _backfill_base=$(facts_run_git "$_facts_git" -C "$_backfill_root" rev-list -1 --before="@$_backfill_first" HEAD)
    [ -n "$_backfill_base" ] || return 0
    _backfill_g=$("$PUPPET_JQ" -nc '{root: $root, base: $base, dirtyAtStart: [], folder: $folder, prefix: $prefix,
      top: null, fromTranscript: true}' --arg root "$_backfill_root" --arg base "$_backfill_base"       --arg folder "$_backfill_cwd" --arg prefix "$_backfill_prefix")
  fi
  printf '%s' "$_backfill_g" > "$4.git"
  _backfill_root=$(printf '%s' "$_backfill_g" | "$PUPPET_JQ" -r .root)
  "$PUPPET_JQ" -r --argjson gaps "$3" '.turns[] | select(.at as $a | any($gaps[]; . == $a)) | "\(.at) \(.endAt // .at)"' "$1" |
    while read -r _backfill_at _backfill_end; do
      _backfill_head=$(facts_run_git "$_facts_git" -C "$_backfill_root" rev-list -1 --before="@$_backfill_at" HEAD)
      facts_run_git "$_facts_git" -C "$_backfill_root" log -z --format='%h%x09%s' -n 20 --since="@$_backfill_at" \
        --until="@$_backfill_end" HEAD > "$4.log"
      "$PUPPET_JQ" -nc "$FACTS_GIT_DEFS {key: \$at, value: ({commits: (\$log | commits)}
        + (if \$head == \"\" then {} else {head: \$head} end))}" --arg at "$_backfill_at" --arg head "$_backfill_head" \
        --rawfile log "$4.log"
    done | "$PUPPET_JQ" -sc 'from_entries' > "$4.turns"
  rm -f "$4.log"
  [ -s "$4.turns" ] || printf '{}' > "$4.turns"
  return 0
}

# Fills session $1's facts from its transcript; prints "ok <turns added>", "none" or "error <why>".
backfill_main() {
  facts_file "$1" > /dev/null || { echo "error bad session"; return 1; }
  deskmates_on || { echo "error Deskmates is off"; return 1; }
  [ -n "$PUPPET_JQ" ] || { echo "error no jq"; return 1; }
  _backfill_t=$(backfill_find "$1") || { echo none; return 0; }
  _backfill_facts=$(facts_file "$1")
  _backfill_cur='{}'
  [ -s "$_backfill_facts" ] && _backfill_cur=$("$PUPPET_JQ" -c 'if type == "object" then . else {} end' "$_backfill_facts" 2>/dev/null)
  [ -n "$_backfill_cur" ] || _backfill_cur='{}'
  _backfill_to=$(backfill_size "$_backfill_t") || { echo "error transcript not readable"; return 1; }
  _backfill_from=$(printf '%s' "$_backfill_cur" | "$PUPPET_JQ" '.backfill.upTo // 0 | floor')
  [ "$_backfill_from" -le "$_backfill_to" ] || _backfill_from=0
  _backfill_work=$(mktemp -d) || { echo "error no temp"; return 1; }
  if ! backfill_read "$_backfill_t" "$_backfill_from" "$_backfill_to" > "$_backfill_work/part"; then
    rm -rf "$_backfill_work"; echo "error transcript not readable"; return 1
  fi
  _backfill_gaps=$("$PUPPET_JQ" -c --argjson cur "$_backfill_cur" '[.prompts[].at as $a
    | select(($cur.turns // []) | all(((.at - $a) | fabs) > 5)) | $a] | sort | .[-30:]' "$_backfill_work/part")
  if [ "$_backfill_gaps" = "[]" ]; then
    rm -rf "$_backfill_work"
    # Nothing to fill: remember how far it read, when the session has facts to keep it in.
    [ "$_backfill_cur" = '{}' ] || PUPPET_PAYLOAD='{}' facts_update "$1" '$cur | .backfill = {upTo: $to, at: $now}' \
      --argjson to "$_backfill_to"
    echo none
    return 0
  fi
  if [ "$_backfill_from" -gt 0 ]; then
    backfill_read "$_backfill_t" 0 "$_backfill_to" > "$_backfill_work/full" || { rm -rf "$_backfill_work"; echo "error transcript not readable"; return 1; }
  else
    cp "$_backfill_work/part" "$_backfill_work/full"
  fi
  # The test candidates the shell's rule counts as test runs.
  _backfill_real=$("$PUPPET_JQ" -r '.tests | to_entries[] | "\(.key)\t\(.value.command | @base64)"' "$_backfill_work/full" |
    while IFS="	" read -r _backfill_k _backfill_c; do
      is_test_command "$(printf '%s' "$_backfill_c" | base64 -D 2>/dev/null || printf '%s' "$_backfill_c" | base64 -d)" && printf '%s\n' "$_backfill_k"
    done | "$PUPPET_JQ" -sc 'map(tonumber)')
  backfill_git "$_backfill_work/full" "$_backfill_cur" "$_backfill_gaps" "$_backfill_work/g"
  "$PUPPET_JQ" -c --argjson real "$_backfill_real" --argjson to "$_backfill_to" --argjson gaps "$_backfill_gaps" \
    --slurpfile gitf "$_backfill_work/g.git" --slurpfile gitturnsf "$_backfill_work/g.turns" \
    --argjson move "$(cat "$_backfill_work/g.move")" \
    "$FACTS_DEFS $FACTS_CLAUDE_DEFS $FACTS_GIT_DEFS \$gitf[0] as \$git | \$gitturnsf[0] as \$gitturns | $BACKFILL_BUILD" \
    "$_backfill_work/full" > "$_backfill_work/b" ||
    { rm -rf "$_backfill_work"; echo "error transcript not readable"; return 1; }
  if PUPPET_PAYLOAD='{}' facts_update "$1" "$FACTS_BACKFILL_DEFS \$cur | backfill_merge(\$b[0]; \$now)" \
      --slurpfile b "$_backfill_work/b"; then
    # The turns it added that the facts kept (the newest 30 turns are).
    echo "ok $("$PUPPET_JQ" --argjson gaps "$_backfill_gaps" '[.turns[]? | select(.fromTranscript and (.at as $a | any($gaps[]; . == $a)))] | length' "$(facts_file "$1")")"
    rm -rf "$_backfill_work"
    return 0
  fi
  rm -rf "$_backfill_work"
  echo "error facts not written"
  return 1
}

# Run as a command (not sourced by a test): fill the session named.
case "$0" in */backfill.sh) [ "$#" -ge 1 ] && backfill_main "$1" ;; esac
