# Shared by every harness's install.sh, uninstall.sh and detect.sh (harnesses/<id>/ sources it). Agents that
# keep hooks as {"hooks": {event: [{matcher?, hooks: [{type, command}]}]}} share the jq filters here: ours
# are the hook commands under ~/.deskmates/ or the old ~/.claude-puppet/.

OURS='\.deskmates/|\.claude-puppet/'

# Settings without our hook commands; events and groups left empty go.
OURS_REMOVE='if has("hooks") then .hooks |= with_entries(.value |= map(.hooks |= map(select(.command // "" | test($ours) | not)) | select(.hooks | length > 0)) | select(.value | length > 0)) else . end'

say() { echo "✓ $1"; }
todo() { echo "→ $1"; }

need_jq() {
  command -v jq > /dev/null 2>&1 && return 0
  echo "jq is needed: brew install jq"
  return 1
}

backup() {
  [ -f "$1" ] && cp -p "$1" "$1.bak"
  return 0
}

# Fails, leaving file $1 as it was, unless it holds JSON.
valid_json() {
  jq empty "$1" > /dev/null 2>&1 && return 0
  echo "$1 is not valid JSON; left as it was" >&2
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

# Our hooks from snippet $2 added to settings file $1, replacing any of ours already there.
hooks_merge() {
  if [ ! -f "$1" ]; then
    mkdir -p "$(dirname "$1")" && echo '{}' > "$1" || return 1
  fi
  valid_json "$1" || return 1
  out=$(jq -s --arg ours "$OURS" "(.[0] | $OURS_REMOVE) as \$mine | .[1].hooks as \$add
    | \$mine | .hooks = (reduce (\$add | keys_unsorted[]) as \$e ((\$mine.hooks // {}); .[\$e] = ((.[\$e] // []) + \$add[\$e])))" \
    "$1" "$2") || return 1
  write_json "$1" "$out"
}

hooks_present() {
  [ -f "$1" ] || return 1
  jq -e --arg ours "$OURS" '[.hooks[]?[]?.hooks[]?.command // "" | select(test($ours))] | length > 0' "$1" > /dev/null 2>&1
}
