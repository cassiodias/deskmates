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
    printf '%s\n' "$PUPPET_FIELDS" | awk -v key="$1" 'index($0, key "\t") == 1 { print substr($0, length(key) + 2); exit }' |
      tr '\036' '\n'
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

# True when a shell command runs tests, so the puppet shows a progress bar and the result.
is_test_command() {
  case " $1 " in
    *pytest*|*"npm test"*|*"npm run test"*|*"yarn test"*|*"pnpm test"*|*"go test"*|*"cargo test"*|*jest*|*vitest*|\
    *rspec*|*"mvn test"*|*"gradle test"*|*"make test"*|*" tox "*|*unittest*) return 0 ;;
  esac
  return 1
}

# The terminal the session runs in: the first ancestor process that has one, remembered per session. An agent
# that runs its hooks away from its terminal (no ancestor has one) defines puppet_tty_fallback in its translator
# to print it another way, usually `puppet_tty_fallback() { tty_from_program <its program>; }`. Not finding one
# is not remembered, so a later event can still find it.
puppet_tty() {
  if [ -n "${PUPPET_TTY+set}" ]; then printf '%s' "$PUPPET_TTY"; return; fi
  cache="$PUPPET_DIR/tty-$1"
  if [ -n "$1" ] && [ -f "$cache" ]; then cat "$cache"; return; fi
  tty=""
  pid=$$
  while [ -n "$pid" ] && [ "$pid" -gt 1 ]; do
    name=$(ps -o tty= -p "$pid" | tr -d ' ')
    case "$name" in
      ""|"??") pid=$(ps -o ppid= -p "$pid" | tr -d ' ') ;;
      *) tty="/dev/$name"; break ;;
    esac
  done
  [ -z "$tty" ] && command -v puppet_tty_fallback > /dev/null && tty=$(puppet_tty_fallback)
  [ -n "$1" ] && [ -n "$tty" ] && printf '%s' "$tty" > "$cache"
  printf '%s' "$tty"
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
  tty=$(puppet_tty "$3")
  [ "$2" = "SessionEnd" ] && rm -f "$PUPPET_DIR/tty-$3"
  printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' "${PUPPET_NOW:-$(date +%s)}" "$2" "$3" "$4" "$5" "$6" "$7" \
    "$(printf '%s' "${8##*/}" | cut_chars 120)" "${TERM_PROGRAM:-}" "$9" "$tty" "$1" "${10}" >> "$PUPPET_EVENTS"
  # Keeps the file small; the puppets start reading again from the top.
  [ "$(wc -c < "$PUPPET_EVENTS")" -gt 1000000 ] && : > "$PUPPET_EVENTS"
  return 0
}
