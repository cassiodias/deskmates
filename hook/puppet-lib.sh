# Shared by every harness translator (harnesses/<id>/translate.sh sources it). It reads the agent's JSON
# payload and writes the one line per event the puppets read. The line format lives here and in
# Deskmates.spoon/lib/puppet/events/parse.lua only:
#   time|event|session|agent id|tool|agent type|text|folder|terminal app|flag|tty|harness|title
# Kept from an agent: a prompt's leading /command, a skill's name, a notification, the first sentence of the
# agent's reply, and what the agent itself wrote to name the work: the session's title and a subagent's short
# description. Never prompts, commands or code. Tests set PUPPET_NOW and PUPPET_TTY to make lines repeatable.

PUPPET_DIR="$HOME/.deskmates"
PUPPET_EVENTS="$PUPPET_DIR/events"

# jq, when this Mac has it: on the PATH, or where macOS and Homebrew put it (an app's hooks may run with a short
# PATH). Without it (macOS 13 and 14 before `brew install jq`), plutil reads each field instead. Tests set
# PUPPET_JQ (empty: no jq).
puppet_find_jq() {
  command -v jq 2>/dev/null && return 0
  for jq in /usr/bin/jq /opt/homebrew/bin/jq /usr/local/bin/jq; do
    [ -x "$jq" ] && { printf '%s\n' "$jq"; return 0; }
  done
  return 0
}
[ -n "${PUPPET_JQ+set}" ] || PUPPET_JQ=$(puppet_find_jq)

# Every value in a JSON document, one per line: its key path (tool_input.command, workspace_roots.0), a tab,
# then the value with its newlines as \036. Only what a translator may read: paths up to 4 keys deep, the first
# 16 items of an array, and the first 4000 characters of a text; a big tool result is never copied whole.
PUPPET_FLATTEN='paths(type != "object" and type != "array") as $p
  | select(($p | length) <= 4 and all($p[]; type == "string" or . < 16))
  | ($p | map(tostring) | join(".")) + "\t"
    + (getpath($p) | if type == "string" then .[0:4000] elif . == null then "" else tostring end
      | gsub("\n"; "\u001e"))'

# Reads the payload from stdin once and parses it once; field, path_field and first_sentence read from that.
puppet_read_payload() {
  PUPPET_PAYLOAD=$(cat)
  puppet_parse_payload
}

# Parses PUPPET_PAYLOAD into PUPPET_FIELDS with one jq run, when there is jq; PUPPET_PARSED says it worked.
puppet_parse_payload() {
  PUPPET_PARSED=""
  PUPPET_FIELDS=""
  [ -n "$PUPPET_JQ" ] || return 0
  PUPPET_FIELDS=$(printf '%s' "$PUPPET_PAYLOAD" | "$PUPPET_JQ" -r "$PUPPET_FLATTEN" 2>/dev/null) && PUPPET_PARSED=1
  return 0
}

# The value at key path $1 in the payload, as it is (newlines kept); nothing when it is missing, null, an object
# or an array.
payload_value() {
  if [ -n "$PUPPET_PARSED" ]; then
    printf '%s\n' "$PUPPET_FIELDS" |
      awk -v key="$1" 'index($0, key "\t") == 1 { print substr($0, length(key) + 2); exit }' | tr '\036' '\n'
    return 0
  fi
  # plutil prints its error on stdout.
  value=$(printf '%s' "$PUPPET_PAYLOAD" | plutil -extract "$1" raw -o - - 2>/dev/null) || return 0
  printf '%s\n' "$value"
}

# The first $1 characters of stdin, never cutting one in two: hooks may run with the C locale (from a
# background process), where cut counts bytes.
cut_chars() {
  LC_ALL=en_US.UTF-8 cut -c "1-$1" 2>/dev/null
}

# Value $1 on one line, without "|", cut to 120 characters.
one_line() {
  printf '%s' "$1" | tr '\n|' '  ' | cut_chars 120
}

# One value from the JSON on stdin by key path, on one line, without "|"; for a file of the agent's.
json_value() {
  if [ -n "$PUPPET_JQ" ]; then
    value=$("$PUPPET_JQ" -r --arg key "$1" 'getpath($key | split(".") | map(tonumber? // .))?
      | if type == "object" or type == "array" or . == null then empty else tostring end' 2>/dev/null) || return 0
  else
    value=$(plutil -extract "$1" raw -o - - 2>/dev/null) || return 0
  fi
  one_line "$value"
}

# One value from the payload by key path (like tool_input.command), on one line, without "|", cut to 120
# characters.
field() {
  one_line "$(payload_value "$1")"
}

# A path from the payload (cwd, transcript_path), whole: field would cut a deep one short.
path_field() {
  payload_value "$1" | tr -d '\n|'
}

# The first sentence of a text field, past any heading, without markdown marks.
first_sentence() {
  payload_value "$1" | grep -v -e '^[[:space:]]*$' -e '^[[:space:]]*#' | head -n 1 | tr -d '#*`|' |
    sed 's/^[[:space:]>-]*//' | sed 's/\([.!?]\)[[:space:]].*/\1/' | cut_chars 90
}

# A prompt's leading /command, or nothing: a slash and a name of letters, digits and ":_-". A prompt that starts
# with a path ("/Users/me/notes.pdf summarise") has no command.
leading_command() {
  word=${1%%[[:space:]]*}
  name=${word#/}
  case "$word" in /*) ;; *) return 0 ;; esac
  case "$name" in ""|*[!A-Za-z0-9:_-]*) return 0 ;; esac
  printf '/%s' "$name"
}

# True when a shell command runs tests, so the puppet shows a progress bar and the result. It looks at the word
# in each command's place (after variable settings and wrappers like npx, uv run or python -m), so a test runner's
# name in an argument (cat jest.config.js) is not a test run.
is_test_command() {
  printf '%s\n' "$1" | awk '
    function base(word) { sub(/.*\//, "", word); return word }
    function isTest(word) { return word == "test" || word ~ /^test:/ }
    {
      gsub(/[;&|()]/, "\n")
      n = split($0, commands, "\n")
      for (c = 1; c <= n; c++) {
        m = split(commands[c], w, /[ \t]+/)
        i = 1
        while (i <= m && w[i] == "") i++
        while (i <= m) {
          if (w[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/ || w[i] ~ /^(npx|bunx|pnpx|exec|time|env|sudo|nice|command)$/) i++
          else if (w[i] ~ /^(uv|poetry|pipenv|pdm|hatch)$/ && w[i + 1] == "run") i += 2
          else if (w[i] == "bundle" && w[i + 1] == "exec") i += 2
          else if (base(w[i]) ~ /^python[0-9.]*$/ && w[i + 1] == "-m") i += 2
          else break
        }
        if (i > m) continue
        program = base(w[i]); first = w[i + 1]; second = w[i + 2]
        if (program ~ /^(pytest|py\.test|unittest|jest|vitest|mocha|rspec|tox|phpunit)$/) found = 1
        else if (program ~ /^(go|cargo|mvn|gradle|gradlew|make|dotnet|swift|mix|deno)$/ && isTest(first)) found = 1
        else if (program ~ /^(npm|yarn|pnpm|bun)$/) {
          if (isTest(first) || (first == "run" && isTest(second))) found = 1
          else if (first ~ /^(exec|dlx|x)$/ && base(second) ~ /^(jest|vitest|mocha)$/) found = 1
          else if (base(first) ~ /^(jest|vitest|mocha)$/) found = 1
        }
      }
    }
    END { exit !found }'
}

# The terminal of process $1 (/dev/ttys004), or nothing.
terminal_of() {
  name=$(ps -o tty= -p "$1" 2>/dev/null | tr -d ' ')
  case "$name" in ""|"??") ;; *) printf '/dev/%s' "$name" ;; esac
}

# Names the program, or programs, the agent runs as in its terminal (the last part of ps -o comm, like the
# harness's `program`): a terminal remembered for a session then counts only while it still runs one of them.
puppet_program() {
  PUPPET_PROGRAM=$*
}

# Whether terminal $1 still runs one of the programs named in $2 (space separated, the last part of ps -o comm),
# or anything at all when $2 is empty. Once its tab or window closes, nothing runs in it.
terminal_runs() {
  [ -n "$1" ] || return 1
  ps -o comm= -t "${1#/dev/}" 2>/dev/null | awk -v names=" $2 " '
    { name = $0; sub(/.*\//, "", name); sub(/^-/, "", name); if (names == "  " || index(names, " " name " ")) found = 1 }
    END { exit !found }'
}

# The terminal the session runs in: the hook's own, else the one remembered for the session while it still runs
# the agent, else the first ancestor process's that has one. A translator names its agent's program with
# puppet_program; without it, a remembered terminal counts while anything runs in it. An agent that runs its
# hooks away from its terminal (no ancestor has one) defines puppet_tty_fallback in its translator to print it
# another way, usually
# `puppet_tty_fallback() { tty_from_program <its program>; }`. Not finding one is not remembered, so a later
# event can still find it.
puppet_tty() {
  if [ -n "${PUPPET_TTY+set}" ]; then printf '%s' "$PUPPET_TTY"; return; fi
  cache="$PUPPET_DIR/tty-$1"
  tty=$(terminal_of $$)
  if [ -z "$tty" ] && [ -n "$1" ] && [ -f "$cache" ]; then
    tty=$(cat "$cache")
    terminal_runs "$tty" "${PUPPET_PROGRAM:-}" || tty=""
  fi
  pid=$(ps -o ppid= -p $$ | tr -d ' ')
  while [ -z "$tty" ] && [ -n "$pid" ] && [ "$pid" -gt 1 ]; do
    tty=$(terminal_of "$pid")
    pid=$(ps -o ppid= -p "$pid" | tr -d ' ')
  done
  [ -z "$tty" ] && command -v puppet_tty_fallback > /dev/null && tty=$(puppet_tty_fallback)
  # Written each time, so the cache of a session still at work never expires.
  [ -n "$1" ] && [ -n "$tty" ] && printf '%s' "$tty" > "$cache"
  printf '%s' "$tty"
}

# Removes what sessions left in $PUPPET_DIR (tty caches, a translator's state like Cursor's turns: every file but
# the events file) once untouched for the Spoon's 2 hours (config.STALE_SECONDS): Codex and Cursor often end a
# session without SessionEnd.
puppet_expire() {
  find "$PUPPET_DIR" -maxdepth 1 -type f ! -name events -mmin +120 -delete 2>/dev/null
  return 0
}

# The terminal of a process named $1 (pgrep -x) working in the payload's cwd, for agents whose hooks run in a
# background process. With several there, the first one no other session has claimed.
tty_from_program() {
  folder=$(cd "$(path_field cwd)" 2>/dev/null && pwd -P) || return 0
  first=""
  for pid in $(pgrep -x "$1"); do
    name=$(ps -o tty= -p "$pid" | tr -d ' ')
    case "$name" in ""|"??") continue ;; esac
    [ "$(lsof -a -d cwd -p "$pid" -Fn 2>/dev/null | sed -n 's/^n//p')" = "$folder" ] || continue
    [ -n "$first" ] || first="/dev/$name"
    claimed_by_other "/dev/$name" || { printf '/dev/%s' "$name"; return 0; }
  done
  printf '%s' "$first"
}

# Whether a session other than the payload's already has terminal $1.
claimed_by_other() {
  for cache in "$PUPPET_DIR"/tty-*; do
    [ -f "$cache" ] && [ "$cache" != "$PUPPET_DIR/tty-$(field session_id)" ] && [ "$(cat "$cache")" = "$1" ] && return 0
  done
  return 1
}

# Prints JSON $1 for the agent when the translator exits, however it exits: for agents that wait for an answer
# on some events (Codex wants {} after Stop). Call it before anything that could fail.
respond() {
  PUPPET_RESPONSE=$1
  trap 'printf "%s\n" "$PUPPET_RESPONSE"' EXIT
}

# write_event harness event session agent_id tool agent_type text cwd flag title
# Appends the line; the only place that writes the events file. event is one of the common names (see
# CONTRIBUTING.md, "What each event must carry"); agent_id is empty on the main thread; flag is "test" or empty.
write_event() {
  mkdir -p "$PUPPET_DIR"
  puppet_expire
  tty=$(puppet_tty "$3")
  [ "$2" = "SessionEnd" ] && rm -f "$PUPPET_DIR/tty-$3"
  printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' "${PUPPET_NOW:-$(date +%s)}" "$2" "$3" "$4" "$5" "$6" "$7" \
    "$(printf '%s' "${8##*/}" | cut_chars 120)" "${TERM_PROGRAM:-}" "$9" "$tty" "$1" "${10}" >> "$PUPPET_EVENTS"
  # Keeps the file small; the puppets start reading again from the top.
  [ "$(wc -c < "$PUPPET_EVENTS")" -gt 1000000 ] && : > "$PUPPET_EVENTS"
  return 0
}
