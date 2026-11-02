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

# The command: bin/deskmates from this working copy, never reloading Hammerspoon or touching its settings.
export DESKMATES_NO_RELOAD=1 DESKMATES_NO_DEFAULTS=1
deskmates="$src/bin/deskmates"
init() { echo "$HOME/.hammerspoon/init.lua"; }
spoon_link() { echo "$HOME/.hammerspoon/Spoons/Deskmates.spoon"; }
ours_init='hs.loadSpoon("Deskmates")
spoon.Deskmates:bindHotkeys({ toggle = { { "ctrl", "alt", "cmd" }, "p" } })
spoon.Deskmates:start()'
mine_init='-- mine
-- mine too'

# An old ~/.claude-puppet install moves over: events kept, old Spoon link gone, init.lua lines swapped.
fresh_home
mkdir -p "$HOME/.claude" "$HOME/.claude-puppet/src" "$HOME/.hammerspoon/Spoons"
echo '1|Stop|s1' > "$HOME/.claude-puppet/events"
ln -s "$HOME/.claude-puppet/src/ClaudePuppet.spoon" "$HOME/.hammerspoon/Spoons/ClaudePuppet.spoon"
printf -- '-- mine\nhs.loadSpoon("ClaudePuppet")\nspoon.ClaudePuppet:start()\n-- mine too\n' > "$(init)"
"$deskmates" install claude > /dev/null
check "migrate: events moved" '[ "$(cat "$HOME/.deskmates/events")" = "1|Stop|s1" ]'
check "migrate: old folder gone" '[ ! -e "$HOME/.claude-puppet" ]'
check "migrate: old link gone" '[ ! -e "$HOME/.hammerspoon/Spoons/ClaudePuppet.spoon" ] && [ ! -L "$HOME/.hammerspoon/Spoons/ClaudePuppet.spoon" ]'
check "migrate: Spoon linked" '[ "$(readlink "$(spoon_link)")" = "$src/Deskmates.spoon" ]'
check "migrate: init.lua swapped" '[ "$(cat "$(init)")" = "$mine_init
$ours_init" ]'
check "migrate: hooks on" '[ "$(count "$(settings)" "$OURS")" = 10 ]'
check "migrate: init.lua backed up" '[ "$(cat "$(init).bak")" = "$(printf -- "-- mine\nhs.loadSpoon(\"ClaudePuppet\")\nspoon.ClaudePuppet:start()\n-- mine too")" ]'

# Installing twice adds the init.lua lines once.
"$deskmates" install claude > /dev/null
check "install twice: init.lua lines once" '[ "$(cat "$(init)")" = "$mine_init
$ours_init" ]'

# status: the moved line has no harness field, so it was Claude's.
check "migrate: status counts the old line" '"$deskmates" status | grep -Eq "^claude +detected +hooks on +last event [0-9]+m ago$"'

# uninstall with no ids: hooks, Spoon link, init.lua lines and ~/.deskmates go; the working copy stays.
"$deskmates" uninstall > /dev/null
check "uninstall all: no ~/.deskmates" '[ ! -e "$HOME/.deskmates" ]'
check "uninstall all: no Spoon link" '[ ! -L "$(spoon_link)" ] && [ ! -e "$(spoon_link)" ]'
check "uninstall all: init.lua mine only" '[ "$(cat "$(init)")" = "$mine_init" ]'
check "uninstall all: init.lua backed up" '[ "$(cat "$(init).bak")" = "$mine_init
$ours_init" ]'
check "uninstall all: no ours" '[ "$(count "$(settings)" "$OURS")" = 0 ]'
check "uninstall all: working copy kept" '[ -x "$deskmates" ] && [ -d "$src/Deskmates.spoon" ]'
check "uninstall all: status hooks off" '"$deskmates" status | grep -Eq "^claude +detected +hooks off +last event never$"'

# Run from inside the old folder, the command follows its copy to ~/.deskmates/src.
fresh_home
mkdir "$HOME/.claude"
git clone -q "$src" "$HOME/.claude-puppet/src"
cp -R bin harnesses hook "$HOME/.claude-puppet/src/"
"$HOME/.claude-puppet/src/bin/deskmates" install claude > /dev/null
rc=$?
check "migrate self: exit 0" '[ "$rc" = 0 ]'
check "migrate self: Spoon linked to the moved copy" '[ "$(readlink "$(spoon_link)")" = "$HOME/.deskmates/src/Deskmates.spoon" ]'
check "migrate self: hooks on" '[ "$(count "$(settings)" "$OURS")" = 10 ]'

# The old hooks already wrote ~/.deskmates/events: the copy still moves, the old lines go first.
fresh_home
mkdir -p "$HOME/.claude" "$HOME/.deskmates"
echo '2|Stop|s2' > "$HOME/.deskmates/events"
git clone -q "$src" "$HOME/.claude-puppet/src"
cp -R bin harnesses hook "$HOME/.claude-puppet/src/"
echo '1|Stop|s1' > "$HOME/.claude-puppet/events"
echo /dev/ttys001 > "$HOME/.claude-puppet/tty-s1"
"$HOME/.claude-puppet/src/bin/deskmates" install claude > /dev/null
check "events first: src moved" '[ -x "$HOME/.deskmates/src/bin/deskmates" ]'
check "events first: old lines first" '[ "$(cat "$HOME/.deskmates/events")" = "1|Stop|s1
2|Stop|s2" ]'
check "events first: tty cache moved" '[ "$(cat "$HOME/.deskmates/tty-s1")" = /dev/ttys001 ]'
check "events first: old folder gone" '[ ! -e "$HOME/.claude-puppet" ]'
check "events first: Spoon linked to the moved copy" '[ "$(readlink "$(spoon_link)")" = "$HOME/.deskmates/src/Deskmates.spoon" ]'
check "events first: hooks point at ~/.deskmates/src" '[ "$(count "$(settings)" "^~/\\.deskmates/src/")" = 10 ] && [ "$(count "$(settings)" "claude-puppet")" = 0 ]'

# Real Spoon folders (not our links) are left alone and named.
fresh_home
mkdir -p "$HOME/.claude" "$HOME/.hammerspoon/Spoons/ClaudePuppet.spoon" "$HOME/.hammerspoon/Spoons/Deskmates.spoon"
touch "$HOME/.hammerspoon/Spoons/ClaudePuppet.spoon/init.lua" "$HOME/.hammerspoon/Spoons/Deskmates.spoon/init.lua"
out=$("$deskmates" install claude)
check "spoon folders: ClaudePuppet kept" '[ -f "$HOME/.hammerspoon/Spoons/ClaudePuppet.spoon/init.lua" ]'
check "spoon folders: Deskmates kept" '[ ! -L "$(spoon_link)" ] && [ -f "$(spoon_link)/init.lua" ]'
check "spoon folders: named" 'echo "$out" | grep -q "ClaudePuppet.spoon is a folder" && echo "$out" | grep -q "Deskmates.spoon is a folder"'
out=$("$deskmates" uninstall)
check "spoon folders: uninstall keeps them" '[ -f "$HOME/.hammerspoon/Spoons/ClaudePuppet.spoon/init.lua" ] && [ -f "$(spoon_link)/init.lua" ]'
check "spoon folders: uninstall names them" 'echo "$out" | grep -q "Deskmates.spoon is a folder"'

# Both folders: the old one is left alone and named.
fresh_home
mkdir -p "$HOME/.claude" "$HOME/.claude-puppet/src" "$HOME/.deskmates/src"
echo '1|Stop|s1' > "$HOME/.claude-puppet/events"
out=$("$deskmates" install claude)
rc=$?
check "both: exit 0" '[ "$rc" = 0 ]'
check "both: old folder untouched" '[ "$(cat "$HOME/.claude-puppet/events")" = "1|Stop|s1" ] && [ -d "$HOME/.claude-puppet/src" ]'
check "both: left over named" 'echo "$out" | grep -qF "~/.claude-puppet is left over"'

# install with no ids: each detected harness is installed, the others are named as skipped.
fresh_home
mkdir "$HOME/.claude"
out=$(PATH=/usr/bin:/bin:$(dirname "$(command -v jq)") "$deskmates" install)
check "install all: claude hooks" '[ "$(count "$(settings)" "$OURS")" = 10 ]'
for dir in "$src"/harnesses/*/; do
  id=$(basename "$dir")
  [ "$id" = claude ] || [ ! -f "$dir/detect.sh" ] && continue
  check "install all: $id skipped" 'echo "$out" | grep -q "$id.*skipped"'
done

# status: detected, hooks on, no event yet; then a Claude event just now.
out=$("$deskmates" status)
check "status: claude never" 'echo "$out" | grep -Eq "^claude +detected +hooks on +last event never$"'
mkdir -p "$HOME/.deskmates"
echo "$(date +%s)|Stop|s2|||||x|iTerm.app|||claude|" >> "$HOME/.deskmates/events"
out=$("$deskmates" status)
check "status: claude 0m ago" 'echo "$out" | grep -Eq "^claude +detected +hooks on +last event 0m ago$"'

# An unknown command or id: usage on stderr, exit 1.
for args in "install nope" "nope" ""; do
  err=$("$deskmates" $args 2>&1 > /dev/null)
  rc=$?
  check "usage ($args): exit 1" '[ "$rc" = 1 ]'
  check "usage ($args): on stderr" 'echo "$err" | grep -q "^usage: deskmates"'
done

# update from a clone: pulls, then installs only harnesses whose hooks are on.
fresh_home
mkdir "$HOME/.claude"
git clone -q "$src" "$HOME/clone"
cp -R bin harnesses hook "$HOME/clone/"
"$HOME/clone/bin/deskmates" update > /dev/null
check "update: hooks off stay off" '! (. hook/install-lib.sh; hooks_present "$(settings)")'
check "update: Spoon linked to the clone" '[ "$(readlink "$(spoon_link)")" = "$(cd -P "$HOME/clone" && pwd)/Deskmates.spoon" ]'
echo '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"~/.deskmates/src/harnesses/claude/translate.sh"}]}]}}' > "$(settings)"
"$HOME/clone/bin/deskmates" update > /dev/null
check "update: hooks on reinstalled" '[ "$(count "$(settings)" "$OURS")" = 10 ]'

rm -rf "$HOME_DIR"
[ "$failed" = 0 ] && echo "install: ok"
exit "$failed"
