# Shared by every harness's install.sh and uninstall.sh (harnesses/<id>/ sources it; install_hooks and
# uninstall_hooks below do their work), and by bin/deskmates.
# The jq filters here handle a JSON hooks file with an event map under "hooks", in either shape:
#   nested (Claude Code, Codex):  {"hooks": {event: [{matcher?, hooks: [{type, command}]}]}}
#   flat:                         {"version": 1, "hooks": {event: [{command}]}}
# Ours are the hook commands under ~/.deskmates/ or the old ~/.claude-puppet/. An agent whose hooks live
# elsewhere (not JSON, or another layout) writes its own install.sh and uninstall.sh, and a present.sh that
# exits 0 when our hooks are on, which bin/deskmates then uses instead of hooks_present.

OURS='\.deskmates/|\.claude-puppet/'

# Settings without our hook commands; events and groups left empty go.
OURS_REMOVE='if (.hooks | type) == "object" then .hooks |= with_entries(.value |= map(
    if (.hooks | type) == "array" then .hooks |= map(select(.command // "" | test($ours) | not)) | select(.hooks | length > 0)
    else select(.command // "" | test($ours) | not) end)
  | select(.value | length > 0)) else . end'

# Every hook command in the file, in either shape.
COMMANDS='.hooks | objects | .[] | arrays | .[] | objects | ((.hooks | arrays | .[] | objects | .command), .command) | strings'

say() { echo "✓ $1"; }
todo() { echo "→ $1"; }

need_jq() {
  command -v jq > /dev/null 2>&1 && return 0
  echo "jq is needed: brew install jq"
  return 1
}

# Copies file $1 to $1.last.bak, keeping its mode. The first copy also goes to $1.bak, which is never
# overwritten: the file as it was before Deskmates first changed it (or a .bak of the user's own, left alone).
# With no file yet, $1.bak is left empty, to say there was none: it never holds Deskmates' own changes.
backup() {
  if [ ! -f "$1" ]; then
    [ -e "$1.bak" ] || { mkdir -p "$(dirname "$1")" && : > "$1.bak"; }
    return
  fi
  [ -e "$1.bak" ] || cp -p "$1" "$1.bak" || return 1
  cp -p "$1" "$1.last.bak"
}

# Fails, leaving file $1 as it was, unless it holds a JSON object.
valid_json() {
  jq -e 'type == "object"' "$1" > /dev/null 2>&1 && return 0
  echo "$1 is not a JSON object; left as it was" >&2
  return 1
}

# The file a path names after following its links (a settings file often links into dotfiles).
real_path() {
  path=$1
  while [ -L "$path" ]; do
    link=$(readlink "$path")
    case "$link" in
      /*) path=$link ;;
      *) path="$(dirname "$path")/$link" ;;
    esac
  done
  echo "$path"
}

# Writes JSON $2 to file $1 through a temp file beside its real target, keeping the target's mode, so a link
# stays a link and a failed write leaves the file as it was.
write_json() {
  target=$(real_path "$1")
  tmp="$target.deskmates-tmp"
  cp -p "$target" "$tmp" && printf '%s\n' "$2" > "$tmp" && mv "$tmp" "$target" && return 0
  rm -f "$tmp"
  return 1
}

hooks_remove() {
  [ -f "$1" ] || return 0
  valid_json "$1" || return 1
  out=$(jq --arg ours "$OURS" "$OURS_REMOVE" "$1") || return 1
  write_json "$1" "$out"
}

# Our hooks from snippet $2 added to settings file $1, replacing any of ours already there. The snippet's other
# top-level keys (like "version") are added when the file has none of its own, and stay after hooks_remove.
hooks_merge() {
  if [ ! -f "$1" ]; then
    mkdir -p "$(dirname "$1")" && echo '{}' > "$1" || return 1
  fi
  valid_json "$1" || return 1
  out=$(jq -s --arg ours "$OURS" "(.[0] | $OURS_REMOVE) as \$mine | .[1].hooks as \$add
    | (.[1] | del(.hooks)) + \$mine | .hooks = (reduce (\$add | keys_unsorted[]) as \$e (((\$mine.hooks | objects) // {}); .[\$e] = ((.[\$e] // []) + \$add[\$e])))" \
    "$1" "$2") || return 1
  write_json "$1" "$out"
}

hooks_present() {
  [ -f "$1" ] || return 1
  jq -e --arg ours "$OURS" "[$COMMANDS | select(test(\$ours))] | length > 0" "$1" > /dev/null 2>&1
}

# Path $1 as the user knows it: ~/… under their home.
# shellcheck disable=SC2088 # a ~ to read, not to expand
tilde() {
  case "$1" in
    "$HOME"/*) printf '~/%s' "${1#"$HOME"/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# install_hooks name file snippet [filter]: what a harness's install.sh does. Adds our hooks from snippet (its
# hooks.json) to the agent's hooks file, replacing any of ours already there, after a backup; a jq filter, when
# given, rewrites the snippet first, with $home set to the user's home. Fails, leaving the file as it was, when
# it is not a JSON object.
install_hooks() {
  need_jq || return 1
  was=new
  if [ -f "$2" ]; then
    valid_json "$2" || return 1
    was=""
  fi
  backup "$2" || return 1
  if [ -n "$4" ]; then
    rewritten=$(mktemp) || return 1
    jq --arg home "$HOME" "$4" "$3" > "$rewritten" && hooks_merge "$2" "$rewritten"
    merged=$?
    rm -f "$rewritten"
    [ "$merged" = 0 ] || return 1
  else
    hooks_merge "$2" "$3" || return 1
  fi
  if [ -n "$was" ]; then
    say "$1 hooks in $(tilde "$2") (a new file; the empty $(tilde "$2").bak says there was none)"
  else
    say "$1 hooks in $(tilde "$2") (backups in $(tilde "$2").bak and .last.bak)"
  fi
}

# uninstall_hooks name file: what a harness's uninstall.sh does. Removes our hooks from the agent's hooks file,
# after a backup, and nothing else.
uninstall_hooks() {
  need_jq || return 1
  if [ -f "$2" ]; then
    valid_json "$2" || return 1
  fi
  if ! hooks_present "$2"; then
    say "no Deskmates hooks in $(tilde "$2")"
    return 0
  fi
  backup "$2" && hooks_remove "$2" || return 1
  say "$1 hooks removed from $(tilde "$2") (backups in $(tilde "$2").bak and .last.bak)"
}
