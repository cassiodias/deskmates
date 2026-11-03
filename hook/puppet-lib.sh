# Shared by every harness translator (harnesses/<id>/translate.sh sources it). It reads the agent's JSON
# payload and writes the one line per event the puppets read. The line format lives here and in
# Deskmates.spoon/lib/puppet/events/parse.lua only:
#   time|event|session|agent id|tool|agent type|text|folder|terminal app|flag|tty|harness|title
# Kept from an agent: a prompt's leading /command, a skill's name, a notification, the first sentence of the
# agent's reply, and what the agent itself wrote to name the work: the session's title and a subagent's short
# description. Never prompts, commands or code. Tests set PUPPET_NOW and PUPPET_TTY to make lines repeatable.

PUPPET_DIR="$HOME/.deskmates"
PUPPET_EVENTS="$PUPPET_DIR/events"

# Reads the payload from stdin once; field and first_sentence read from it.
puppet_read_payload() {
  PUPPET_PAYLOAD=$(cat)
}

# One value from the JSON on stdin by key path, on one line, without "|".
json_value() {
  value=$(plutil -extract "$1" raw -o - - 2>/dev/null) || return 0
  printf '%s' "$value" | tr '\n|' '  ' | cut -c1-120
}

# One value from the payload by key path (like tool_input.command).
field() {
  printf '%s' "$PUPPET_PAYLOAD" | json_value "$1"
}

# A path from the payload (cwd, transcript_path), whole: field would cut a deep one short. Nothing when the
# payload has none (plutil prints its error on stdout).
path_field() {
  value=$(printf '%s' "$PUPPET_PAYLOAD" | plutil -extract "$1" raw -o - - 2>/dev/null) || return 0
  printf '%s' "$value" | tr -d '\n|'
}

# The first sentence of a text field, past any heading, without markdown marks.
first_sentence() {
  value=$(printf '%s' "$PUPPET_PAYLOAD" | plutil -extract "$1" raw -o - - 2>/dev/null) || return 0
  printf '%s\n' "$value" | grep -v -e '^[[:space:]]*$' -e '^[[:space:]]*#' | head -n 1 | tr -d '#*`|' |
    sed 's/^[[:space:]>-]*//' | sed 's/\([.!?]\)[[:space:]].*/\1/' | cut -c1-90
}

# A prompt's leading /command, or nothing.
leading_command() {
  case "$1" in /*) printf '%s' "${1%% *}" ;; esac
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
    "$(printf '%s' "${8##*/}" | cut -c1-120)" "${TERM_PROGRAM:-}" "$9" "$tty" "$1" "${10}" >> "$PUPPET_EVENTS"
  # Keeps the file small; the puppets start reading again from the top.
  [ "$(wc -c < "$PUPPET_EVENTS")" -gt 1000000 ] && : > "$PUPPET_EVENTS"
  return 0
}
