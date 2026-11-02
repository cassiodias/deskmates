#!/bin/sh
# Runs each harness's install, uninstall and detect against a fake home and checks what they leave in the
# agent's settings. Needs jq.
cd "$(dirname "$0")/.."
src=$(pwd)
failed=0
HOME_DIR=
OURS='\.deskmates/|\.claude-puppet/'
ours_cmd='~/.deskmates/src/harnesses/claude/translate.sh'

check() {
  if eval "$2"; then :; else echo "install: $1 failed"; failed=1; fi
}

# A new empty home in $HOME.
fresh_home() {
  [ -n "$HOME_DIR" ] && rm -rf "$HOME_DIR"
  HOME_DIR=$(mktemp -d) || exit 1
  export HOME="$HOME_DIR"
}

# Counts hook commands in settings file $1 matching regex $2.
count() {
  jq --arg re "$2" '[.hooks[]?[]?.hooks[]?.command | select(test($re))] | length' "$1"
}

claude="$src/harnesses/claude"
settings() { echo "$HOME/.claude/settings.json"; }

# Fresh home with ~/.claude/ only.
fresh_home
mkdir "$HOME/.claude"
"$claude/install.sh" > /dev/null
s=$(settings)
check "fresh: 10 events" '[ "$(jq ".hooks | length" "$s")" = 10 ]'
check "fresh: one ours per event" \
  '[ "$(jq --arg c "$ours_cmd" "[.hooks[] | (map(.hooks[].command) == [\$c])] | all" "$s")" = true ]'

# A user's own hooks and an old puppet entry.
fresh_home
mkdir "$HOME/.claude"
cp tests/install/claude-settings-user.json "$(settings)"
"$claude/install.sh" > /dev/null
s=$(settings)
check "user: notify hook kept" '[ "$(count "$s" "^~/bin/deskmates-notify$")" = 1 ]'
check "user: stop hook kept" '[ "$(count "$s" "^~/bin/my-stop.sh$")" = 1 ]'
check "user: old puppet gone" '[ "$(count "$s" "\\.claude-puppet/")" = 0 ]'
check "user: one ours per event" \
  '[ "$(jq --arg c "$ours_cmd" "[.hooks[] | ([.[].hooks[].command | select(. == \$c)] | length == 1)] | all" "$s")" = true ]'
check "user: 10 ours" '[ "$(count "$s" "$OURS")" = 10 ]'
check "user: other settings kept" '[ "$(jq -r .model "$s")" = opus ]'
check "user: backup is the original" 'cmp -s "$s.bak" tests/install/claude-settings-user.json'

# Installing twice changes nothing.
cp "$s" "$HOME/once.json"
"$claude/install.sh" > /dev/null
check "twice: same file" 'cmp -s "$s" "$HOME/once.json"'

# Uninstall leaves the user's hooks only.
"$claude/uninstall.sh" > /dev/null
check "uninstall: none of ours" '[ "$(count "$s" "$OURS")" = 0 ]'
check "uninstall: notify hook kept" '[ "$(count "$s" "^~/bin/deskmates-notify$")" = 1 ]'
check "uninstall: stop hook kept" '[ "$(count "$s" "^~/bin/my-stop.sh$")" = 1 ]'
check "uninstall: empty events gone" '[ "$(jq -c ".hooks | keys" "$s")" = "[\"PreToolUse\",\"Stop\"]" ]'

# A settings file linked into dotfiles stays a link; its target gets the hooks and keeps its mode.
fresh_home
mkdir -p "$HOME/.claude" "$HOME/dotfiles/claude"
echo '{}' > "$HOME/dotfiles/claude/settings.json"
chmod 600 "$HOME/dotfiles/claude/settings.json"
ln -s ../dotfiles/claude/settings.json "$HOME/.claude/settings.json"
"$claude/install.sh" > /dev/null
check "link: still a link" '[ -L "$(settings)" ]'
check "link: target has ours" '[ "$(count "$HOME/dotfiles/claude/settings.json" "$OURS")" = 10 ]'
check "link: target mode kept" '[ "$(stat -f %Lp "$HOME/dotfiles/claude/settings.json")" = 600 ]'

# Settings that are not JSON are left alone.
fresh_home
mkdir "$HOME/.claude"
cp tests/install/claude-settings-bad.json "$(settings)"
"$claude/install.sh" > /dev/null 2>&1
rc=$?
check "bad: install fails" '[ "$rc" = 1 ]'
check "bad: file unchanged" 'cmp -s "$(settings)" tests/install/claude-settings-bad.json'

# Detect: an empty home has no Claude, ~/.claude/ means Claude.
fresh_home
check "detect: empty home" '! PATH=/usr/bin:/bin "$claude/detect.sh"'
mkdir "$HOME/.claude"
check "detect: ~/.claude" 'PATH=/usr/bin:/bin "$claude/detect.sh"'

# The library on its own: a missing file and its folder are created; hooks_present sees ours.
fresh_home
lib="$HOME/nested/hooks.json"
check "lib: merge creates folder" '(. hook/install-lib.sh; hooks_merge "$lib" "$claude/hooks.json") && [ "$(count "$lib" "$OURS")" = 10 ]'
check "lib: present" '(. hook/install-lib.sh; hooks_present "$lib")'
check "lib: absent after remove" '(. hook/install-lib.sh; hooks_remove "$lib" && ! hooks_present "$lib")'
check "lib: remove missing file" '(. hook/install-lib.sh; hooks_remove "$HOME/none.json") && [ ! -e "$HOME/none.json" ]'

rm -rf "$HOME_DIR"
[ "$failed" = 0 ] && echo "install: ok"
exit "$failed"
