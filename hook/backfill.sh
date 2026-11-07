#!/bin/sh
# Fills a Claude session's facts from its transcript, for the turns the hooks did not record (a session started
# before Deskmates watched, or one that ran while it was off). The Spoon runs it when a card opens:
#   hook/backfill.sh <session>   prints "ok <turns added>", "none" or "error <why>"
# Sourced (tests), it only defines its helpers. See the design: -mem specs/2026-11-07-transcript-backfill-design.md.

_backfill_dir=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
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
def is_prompt: .type == "user" and (.isMeta != true) and (.isSidechain != true)
  and ((.message.content | type) == "string"
    or ((.message.content | type) == "array" and (.message.content | any(.type == "tool_result") | not)
      and (.message.content | any(.type == "text"))));
def command: (.message.content | text_of) as $t
  | (($t | capture("<command-name>/?(?<c>[^<]+)</command-name>") | .c)
    // ($t | capture("^/(?<c>[A-Za-z0-9:_-]+)(\\s|$)") | .c) // null);
def prompt_text: (.message.content | text_of) as $t
  | if ($t | test("<command-name>")) then "/" + command + " " + (($t | capture("<command-args>(?<a>[^<]*)</command-args>") | .a) // "")
    else $t end;
[inputs | fromjson? | select(type == "object")] as $all
| [$sub[] | fromjson? | select(type == "object")] as $subs
| [$all[] | select(ts != null)] as $recs
| [$recs[] | select(is_prompt) | {at: ts, command: command, prompt: prompt_text}] as $p
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
    | {at: $a, endAt: ($done // ([$in[] | ts] | last)), reply: (if $last then ($last | sentence) else null end),
       edits: [$uses[] | select(.name == "Write" or .name == "Edit" or .name == "MultiEdit" or .name == "NotebookEdit")
         | select(turn_of(.at) == $i) | (.input.file_path // .input.notebook_path // empty) | tostring] | unique}] as $turns
| {cwd: ([$recs[] | .cwd | strings] | first),
   prompts: [$p[] | {at, command}],
   turns: $turns,
   notes: ([
     ($p[] | select(.command != null) | . as $x | {at: $x.at, note: ({prompt: $x.prompt} | claude_command_note($x.command))}),
     ($uses[] | select(.side | not) | . as $u | $results[$u.id] as $r
       | if $u.name == "Skill" then {at: $u.at, note: ({tool_input: $u.input} | claude_skill_note)}
         elif $u.name == "Agent" or $u.name == "Task" then
           {at: $u.at, note: ({tool_input: $u.input} | claude_agent_note)},
           (($u.input.description // "" | tostring) as $d | select($d != "" and $r != null)
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
  tail -c +"$(($2 + 1))" "$1" | head -c "$(($3 - $2))" |
    "$PUPPET_JQ" -nRc --rawfile subtext "$_backfill_subs" \
      "$FACTS_DEFS $FACTS_CLAUDE_DEFS (\$subtext | split(\"\\n\") | map(select(. != \"\"))) as \$sub | $BACKFILL_READ"
  _backfill_rc=$?
  rm -f "$_backfill_subs"
  return "$_backfill_rc"
}
