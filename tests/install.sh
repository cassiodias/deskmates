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

# Codex: hooks in ~/.codex/hooks.json.
codex="$src/harnesses/codex"
codex_cmd='~/.deskmates/src/harnesses/codex/translate.sh'
chooks() { echo "$HOME/.codex/hooks.json"; }
fresh_home
mkdir "$HOME/.codex"
"$codex/install.sh" > /dev/null
h=$(chooks)
check "codex fresh: config path" '[ "$("$codex/config.sh")" = "$HOME/.codex/hooks.json" ]'
check "codex fresh: 9 events" '[ "$(jq ".hooks | length" "$h")" = 9 ]'
check "codex fresh: one ours per event" \
  '[ "$(jq --arg c "$codex_cmd" "[.hooks[] | (map(.hooks[].command) == [\$c])] | all" "$h")" = true ]'
check "codex fresh: no matcher" '[ "$(jq "[.hooks[][] | has(\"matcher\")] | any" "$h")" = false ]'
check "codex fresh: no Notification" '[ "$(jq ".hooks | has(\"Notification\")" "$h")" = false ]'

fresh_home
mkdir "$HOME/.codex"
echo '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"~/bin/my-stop.sh"}]}]}}' > "$(chooks)"
"$codex/install.sh" > /dev/null
h=$(chooks)
check "codex user: hook kept" '[ "$(count "$h" "^~/bin/my-stop.sh$")" = 1 ]'
check "codex user: 9 ours" '[ "$(count "$h" "$OURS")" = 9 ]'
cp "$h" "$HOME/once.json"
"$codex/install.sh" > /dev/null
check "codex twice: same file" 'cmp -s "$h" "$HOME/once.json"'
"$codex/uninstall.sh" > /dev/null
check "codex uninstall: none of ours" '[ "$(count "$h" "$OURS")" = 0 ]'
check "codex uninstall: user hook kept" '[ "$(count "$h" "^~/bin/my-stop.sh$")" = 1 ]'
check "codex detect: ~/.codex" 'PATH=/usr/bin:/bin "$codex/detect.sh"'
fresh_home
check "codex detect: empty home" '! PATH=/usr/bin:/bin "$codex/detect.sh"'

# Cursor: a flat hooks file, ~/.cursor/hooks.json. Cursor reads a command as a path (relative ones from
# ~/.cursor/), so ours are written with the home spelled out.
cursor="$src/harnesses/cursor"
fresh_home
check "cursor detect: empty home" '! PATH=/usr/bin:/bin "$cursor/detect.sh"'
mkdir "$HOME/.cursor"
check "cursor detect: ~/.cursor" 'PATH=/usr/bin:/bin "$cursor/detect.sh"'
"$cursor/install.sh" > /dev/null
h="$HOME/.cursor/hooks.json"
check "cursor fresh: config path" '[ "$("$cursor/config.sh")" = "$h" ]'
check "cursor fresh: version 1" '[ "$(jq .version "$h")" = 1 ]'
check "cursor fresh: 7 events" '[ "$(jq ".hooks | length" "$h")" = 7 ]'
check "cursor fresh: no sessionStart (the translator drops it)" '[ "$(jq ".hooks | has(\"sessionStart\")" "$h")" = false ]'
check "cursor fresh: every command is ours, home spelled out" \
  '[ "$(jq -r "[.hooks[][].command] | unique | join(\" \")" "$h")" = "$HOME/.deskmates/src/harnesses/cursor/translate.sh" ]'

# The library on its own: a missing file and its folder are created; hooks_present sees ours.
fresh_home
lib="$HOME/nested/hooks.json"
check "lib: merge creates folder" '(. hook/install-lib.sh; hooks_merge "$lib" "$claude/hooks.json") && [ "$(count "$lib" "$OURS")" = 10 ]'
check "lib: present" '(. hook/install-lib.sh; hooks_present "$lib")'
check "lib: absent after remove" '(. hook/install-lib.sh; hooks_remove "$lib" && ! hooks_present "$lib")'
check "lib: remove missing file" '(. hook/install-lib.sh; hooks_remove "$HOME/none.json") && [ ! -e "$HOME/none.json" ]'

# The library on a flat hooks file ({"version": 1, "hooks": {event: [{command}]}}): the same round trip.
fresh_home
flat="$HOME/flat.json"
printf '%s' '{"version":1,"hooks":{"stop":[{"command":"~/.deskmates/src/harnesses/x/translate.sh"}],"start":[{"command":"~/.deskmates/src/harnesses/x/translate.sh"}]}}' > "$HOME/flat-snippet.json"
printf '%s' '{"hooks":{"stop":[{"command":"~/bin/mine"}]}}' > "$flat"
check "flat: merge" '(. hook/install-lib.sh; hooks_merge "$flat" "$HOME/flat-snippet.json")'
check "flat: ours in, user kept" '[ "$(jq -c "[.hooks.stop[].command, .hooks.start[].command]" "$flat")" = "[\"~/bin/mine\",\"~/.deskmates/src/harnesses/x/translate.sh\",\"~/.deskmates/src/harnesses/x/translate.sh\"]" ]'
check "flat: version added" '[ "$(jq .version "$flat")" = 1 ]'
check "flat: present" '(. hook/install-lib.sh; hooks_present "$flat")'
cp "$flat" "$HOME/flat-once.json"
check "flat: twice, same file" '(. hook/install-lib.sh; hooks_merge "$flat" "$HOME/flat-snippet.json") && cmp -s "$flat" "$HOME/flat-once.json"'
check "flat: remove keeps the user's" '(. hook/install-lib.sh; hooks_remove "$flat" && ! hooks_present "$flat") && [ "$(jq -c .hooks "$flat")" = "{\"stop\":[{\"command\":\"~/bin/mine\"}]}" ]'

# The command: bin/deskmates from this working copy, never reloading Hammerspoon or touching its settings.
export DESKMATES_NO_RELOAD=1 DESKMATES_NO_DEFAULTS=1
deskmates="$src/bin/deskmates"
init() { echo "$HOME/.hammerspoon/init.lua"; }
spoon_link() { echo "$HOME/.hammerspoon/Spoons/Deskmates.spoon"; }
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
check "migrate: init.lua renamed" '[ "$(cat "$(init)")" = "-- mine
hs.loadSpoon(\"Deskmates\")
spoon.Deskmates:start()
-- mine too" ]'
check "migrate: hooks on" '[ "$(count "$(settings)" "$OURS")" = 10 ]'
check "migrate: init.lua backed up" '[ "$(cat "$(init).bak")" = "$(printf -- "-- mine\nhs.loadSpoon(\"ClaudePuppet\")\nspoon.ClaudePuppet:start()\n-- mine too")" ]'

# Installing twice adds the init.lua lines once.
"$deskmates" install claude > /dev/null
check "install twice: init.lua unchanged" '[ "$(cat "$(init)")" = "-- mine
hs.loadSpoon(\"Deskmates\")
spoon.Deskmates:start()
-- mine too" ]'

# status: the moved line has no harness field, so it was Claude's.
check "migrate: status counts the old line" '"$deskmates" status | grep -Eq "^claude +detected +hooks on +last event [0-9]+m ago$"'

# uninstall with no ids: hooks, Spoon link, init.lua lines and ~/.deskmates go; the working copy stays.
"$deskmates" uninstall > /dev/null
check "uninstall all: no ~/.deskmates" '[ ! -e "$HOME/.deskmates" ]'
check "uninstall all: no Spoon link" '[ ! -L "$(spoon_link)" ] && [ ! -e "$(spoon_link)" ]'
check "uninstall all: init.lua mine only" '[ "$(cat "$(init)")" = "$mine_init" ]'
check "uninstall all: init.lua backed up" '[ "$(cat "$(init).bak")" = "-- mine
hs.loadSpoon(\"Deskmates\")
spoon.Deskmates:start()
-- mine too" ]'
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

# An old install moves over and Codex is installed too: Claude's hooks come back pointing at ~/.deskmates.
fresh_home
mkdir -p "$HOME/.claude" "$HOME/.codex" "$HOME/.claude-puppet/src"
echo '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"~/.claude-puppet/src/hook/puppet-hook.sh"}]}]}}' > "$(settings)"
"$deskmates" install codex > /dev/null
check "migrate codex: claude hooks on" '[ "$(count "$(settings)" "$OURS")" = 10 ] && [ "$(count "$(settings)" "claude-puppet")" = 0 ]'
check "migrate codex: claude hooks at ~/.deskmates" '[ "$(count "$(settings)" "^~/\\.deskmates/src/harnesses/claude/")" = 10 ]'
check "migrate codex: codex hooks on" '[ "$(count "$(chooks)" "^~/\\.deskmates/src/harnesses/codex/")" = 9 ]'
rm -rf "$HOME/.deskmates"

# A migration with a plain install installs each harness once, and the first backup keeps the old hooks.
fresh_home
mkdir -p "$HOME/.claude" "$HOME/.codex" "$HOME/.claude-puppet/src"
echo '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"~/.claude-puppet/src/hook/puppet-hook.sh"}]}]}}' > "$(settings)"
out=$(PATH=/usr/bin:/bin:$(dirname "$(command -v jq)") "$deskmates" install)
check "migrate all: each harness once" 'echo "$out" | grep -qx "✓ hooks installed for: claude codex"'
check "migrate all: backup has the old hooks" 'grep -q claude-puppet "$(settings).bak"'
rm -rf "$HOME/.deskmates"

# A plain install finds both agents by their folders and installs both.
fresh_home
mkdir -p "$HOME/.claude" "$HOME/.codex"
PATH=/usr/bin:/bin:$(dirname "$(command -v jq)") "$deskmates" install > /dev/null
check "detect both: claude hooks on" '[ "$(count "$(settings)" "$OURS")" = 10 ]'
check "detect both: codex hooks on" '[ "$(count "$(chooks)" "$OURS")" = 9 ]'
rm -rf "$HOME/.deskmates"

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

# A user's own ClaudePuppet settings in init.lua carry over: renamed, not dropped, no defaults added on top.
fresh_home
mkdir -p "$HOME/.claude" "$HOME/.hammerspoon"
cat > "$(init)" <<'LUA'
hs.loadSpoon("ClaudePuppet")
spoon.ClaudePuppet.pixel = 5
spoon.ClaudePuppet.coder = {
  "a",
}
spoon.ClaudePuppet:bindHotkeys({ toggle = { {"cmd"}, "j" } })
spoon.ClaudePuppet:start()
LUA
cp "$(init)" "$HOME/init.orig"
out=$("$deskmates" install claude)
check "init rename: no ClaudePuppet left" '! grep -q ClaudePuppet "$(init)"'
check "init rename: settings kept" 'grep -qx "spoon.Deskmates.pixel = 5" "$(init)" && grep -qx "spoon.Deskmates.coder = {" "$(init)" && grep -qx "  \"a\"," "$(init)"'
check "init rename: own hotkey kept, no default" '[ "$(grep -c bindHotkeys "$(init)")" = 1 ] && grep -q "\"cmd\"" "$(init)"'
check "init rename: one loadSpoon" '[ "$(grep -c "loadSpoon(\"Deskmates\")" "$(init)")" = 1 ]'
check "init rename: backup is the original" 'cmp -s "$(init).bak" "$HOME/init.orig"'
check "init rename: said so" 'echo "$out" | grep -q "init.lua: ClaudePuppet lines renamed to Deskmates"'
if command -v luac > /dev/null 2>&1; then
  check "init rename: parses" 'luac -p "$(init)"'
fi
# Uninstall points at the backup.
out=$("$deskmates" uninstall)
check "init uninstall: names the backup" 'echo "$out" | grep -q "init.lua.bak"'

# Only this Spoon's names change: another Spoon whose name holds the word, and comments, stay as they are.
fresh_home
mkdir -p "$HOME/.claude" "$HOME/.hammerspoon"
cat > "$(init)" <<'LUA'
-- I used ClaudePuppet before
hs.loadSpoon("MyClaudePuppetTheme")
hs.loadSpoon("ClaudePuppet")
spoon.ClaudePuppet:start()
LUA
"$deskmates" install claude > /dev/null
check "init narrow: comment kept" 'grep -qx -- "-- I used ClaudePuppet before" "$(init)"'
check "init narrow: other Spoon kept" 'grep -qx "hs.loadSpoon(\"MyClaudePuppetTheme\")" "$(init)"'
check "init narrow: ours renamed" 'grep -qx "hs.loadSpoon(\"Deskmates\")" "$(init)" && grep -qx "spoon.Deskmates:start()" "$(init)"'
"$deskmates" uninstall > /dev/null
check "init narrow: uninstall keeps the other Spoon" 'grep -q "MyClaudePuppetTheme" "$(init)" && ! grep -q "Deskmates" "$(init)" && grep -q "I used ClaudePuppet" "$(init)"'

# Both names already there: the old Spoon's load and calls go, so Deskmates starts once; settings carry over.
fresh_home
mkdir -p "$HOME/.claude" "$HOME/.hammerspoon"
cat > "$(init)" <<'LUA'
hs.loadSpoon("ClaudePuppet")
spoon.ClaudePuppet.pixel = 5
spoon.ClaudePuppet:start()
hs.loadSpoon("Deskmates")
spoon.Deskmates:start()
LUA
"$deskmates" install claude > /dev/null
check "init both: one loadSpoon" '[ "$(grep -c "loadSpoon" "$(init)")" = 1 ]'
check "init both: one start" '[ "$(grep -c ":start()" "$(init)")" = 1 ]'
check "init both: setting kept" 'grep -qx "spoon.Deskmates.pixel = 5" "$(init)"'

# An init.lua linked into dotfiles stays a link and keeps its mode through the rename.
fresh_home
mkdir -p "$HOME/.claude" "$HOME/.hammerspoon" "$HOME/dotfiles"
printf 'hs.loadSpoon("ClaudePuppet")\n' > "$HOME/dotfiles/init.lua"
chmod 600 "$HOME/dotfiles/init.lua"
ln -s ../dotfiles/init.lua "$(init)"
"$deskmates" install claude > /dev/null
check "init link: still a link" '[ -L "$(init)" ]'
check "init link: renamed in target" 'grep -q "loadSpoon(\"Deskmates\")" "$HOME/dotfiles/init.lua"'
check "init link: mode kept" '[ "$(stat -f %Lp "$HOME/dotfiles/init.lua")" = 600 ]'

# Run from a clone outside ~/.deskmates/src: the hooks run ~/.deskmates/src, so say so.
fresh_home
mkdir "$HOME/.claude"
out=$("$deskmates" install claude)
check "elsewhere: warned" 'echo "$out" | grep -q "hooks run ~/.deskmates/src"'
mkdir -p "$HOME/.deskmates"
ln -s "$src" "$HOME/.deskmates/src"
out=$("$deskmates" install claude)
check "elsewhere: no warning when ~/.deskmates/src is this copy" '! echo "$out" | grep -q "hooks run ~/.deskmates/src"'

# No jq: nothing is migrated or changed.
if [ ! -x /usr/bin/jq ] && [ ! -x /bin/jq ]; then
  fresh_home
  mkdir -p "$HOME/.claude" "$HOME/.claude-puppet/src"
  out=$(PATH=/usr/bin:/bin "$deskmates" install claude 2>&1)
  rc=$?
  check "no jq: exit 1" '[ "$rc" = 1 ]'
  check "no jq: says so" 'echo "$out" | grep -q "jq is needed"'
  check "no jq: nothing migrated" '[ -d "$HOME/.claude-puppet/src" ] && [ ! -e "$HOME/.deskmates" ]'
fi

# An id given twice installs once.
fresh_home
mkdir "$HOME/.claude"
out=$("$deskmates" install claude claude)
check "dedupe: installed once" '[ "$(echo "$out" | grep -c "hooks installed for: claude$")" = 1 ]'

# A backup keeps the mode of the file it copies.
fresh_home
echo '{}' > "$HOME/s.json"
chmod 600 "$HOME/s.json"
check "backup: mode kept" '(. hook/install-lib.sh; backup "$HOME/s.json") && [ "$(stat -f %Lp "$HOME/s.json.bak")" = 600 ]'

# Every harness, with nothing written for it here: its hooks file holding a hook of the user's for each of its
# events, install, install again, status, uninstall. Harnesses with their own present.sh are not JSON-based and
# only get the install, status and uninstall exit codes checked.
for dir in harnesses/*/; do
  id=$(basename "$dir")
  [ -f "$dir/detect.sh" ] || continue
  fresh_home
  f=$("$dir/config.sh")
  if [ -x "$dir/present.sh" ]; then
    check "$id: hooks.json points at its translator" 'grep -q "harnesses/$id/translate.sh" "$dir/hooks.json"'
  else
    check "$id: hooks.json points at its translator" \
      '[ "$(jq -r "[$(. hook/install-lib.sh; echo "$COMMANDS")] | unique | join(\" \")" "$dir/hooks.json")" = "~/.deskmates/src/harnesses/$id/translate.sh" ]'
  fi
  mkdir -p "$(dirname "$f")"
  if [ ! -x "$dir/present.sh" ]; then
    jq 'walk(if type == "object" and has("command") then .command = "~/bin/my-hook" else . end)' "$dir/hooks.json" > "$f"
    cp "$f" "$HOME/user.json"
  fi
  check "$id: install" '"$dir/install.sh" > /dev/null'
  check "$id: status says hooks on" '"$deskmates" status | grep -Eq "^$id +[a-z ]+ +hooks on"'
  if [ ! -x "$dir/present.sh" ]; then
    users=$(. hook/install-lib.sh; jq "[$COMMANDS | select(. == \"~/bin/my-hook\")] | length" "$HOME/user.json")
    check "$id: user hooks kept" '[ "$(. hook/install-lib.sh; jq "[$COMMANDS | select(. == \"~/bin/my-hook\")] | length" "$f")" = "$users" ]'
    cp "$f" "$HOME/once.json"
    check "$id: twice, same file" '"$dir/install.sh" > /dev/null && cmp -s "$f" "$HOME/once.json"'
  fi
  check "$id: uninstall" '"$dir/uninstall.sh" > /dev/null'
  check "$id: status says hooks off" '"$deskmates" status | grep -Eq "^$id +[a-z ]+ +hooks off"'
  [ -x "$dir/present.sh" ] || check "$id: uninstall gives the user's file back" '[ "$(jq -S . "$f")" = "$(jq -S . "$HOME/user.json")" ]'
done

rm -rf "$HOME_DIR"
[ "$failed" = 0 ] && echo "install: ok"
exit "$failed"
