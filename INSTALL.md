# Install

**You need:** macOS 13 or later, [Homebrew](https://brew.sh), `git` (run `xcode-select --install` if `git --version` asks for it) and Claude Code. iTerm2 is optional; with it, a click on a puppet selects its exact tab.

Steps 1 to 4 are copy and paste into a terminal. Step 5 is a few clicks in macOS that no script can do for you. It takes about 5 minutes.

## 1. Install Hammerspoon

[Hammerspoon](https://www.hammerspoon.org) is a free macOS automation app; it draws the puppets.

```sh
brew install --cask hammerspoon
```

## 2. Get the files

```sh
git clone https://github.com/cassiodias/claude-puppet-overlay.git ~/.claude-puppet/src
mkdir -p ~/.hammerspoon/Spoons
ln -sfn ~/.claude-puppet/src/ClaudePuppet.spoon ~/.hammerspoon/Spoons/ClaudePuppet.spoon
```

This puts the source in `~/.claude-puppet/src` and links Hammerspoon's `~/.hammerspoon/Spoons/ClaudePuppet.spoon` to it, so an update is a `git pull`. If `~/.claude-puppet/src` already exists, you installed before: follow [Update](#update) instead.

## 3. Load the puppets in Hammerspoon

```sh
grep -qs 'ClaudePuppet' ~/.hammerspoon/init.lua || cat >> ~/.hammerspoon/init.lua <<'LUA'
hs.loadSpoon("ClaudePuppet")
spoon.ClaudePuppet:bindHotkeys({ toggle = { { "ctrl", "alt", "cmd" }, "p" } })
spoon.ClaudePuppet:start()
LUA
```

This adds three lines to `~/.hammerspoon/init.lua` (Hammerspoon's config, created if you have none), unless they are there already. Anything else in that file stays.

## 4. Connect Claude Code

`jq` comes with macOS 15 and later; on macOS 13 or 14, run `brew install jq` first.

```sh
cd ~/.claude-puppet/src
[ -f ~/.claude/settings.json ] || echo '{}' > ~/.claude/settings.json
cp ~/.claude/settings.json ~/.claude/settings.json.bak
jq '.hooks |= ((. // {}) | with_entries(.value |= map(select(all(.hooks[]; .command | test("claude-puppet") | not)))) | with_entries(select(.value | length > 0)))' \
  ~/.claude/settings.json > /tmp/claude-puppet-clean.json
jq -s '.[0] as $mine | .[1].hooks as $add | $mine | .hooks = (reduce ($add | keys[]) as $e (($mine.hooks // {}); .[$e] = ((.[$e] // []) + $add[$e])))' \
  /tmp/claude-puppet-clean.json harnesses/claude/hooks.json > ~/.claude/settings.json
rm /tmp/claude-puppet-clean.json
```

This adds the puppet's hook, `~/.claude-puppet/src/harnesses/claude/translate.sh`, to your user settings, `~/.claude/settings.json`, for these Claude Code events: prompt submitted, before and after each tool call, tool failure, permission request, subagent start and stop, notification, stop and session end. It saves a backup to `~/.claude/settings.json.bak` first, keeps everything else in the file (your other hooks included), and replaces any puppet hooks already there, so it is safe to run again.

## 5. Things only you can do

1. **Open Hammerspoon:** run `open -a Hammerspoon`. It loads its config, and a puppet appears in the bottom right corner of your main screen, with a `▟▙` icon in the menu bar. On the very first launch Hammerspoon also shows a setup window.
2. **Allow Accessibility:** System Settings → Privacy & Security → **Accessibility** → turn on **Hammerspoon**. Without it you cannot drag the puppets or click them. If Hammerspoon is listed and already on but dragging does not work, the switch belongs to an older copy of the app: select Hammerspoon, remove it with **–**, add it again with **+** (Applications → Hammerspoon), turn it on, then quit and reopen Hammerspoon.
3. **Allow iTerm2 control** (iTerm2 only): the first time a Claude session runs in iTerm2, macOS asks *"Hammerspoon wants to control iTerm2"*. Click **OK**: it is how each puppet shows its tab number and how a click selects that tab. If you clicked Don't Allow: System Settings → Privacy & Security → **Automation** → Hammerspoon → turn on iTerm2.
4. **Launch at login:** click the Hammerspoon icon in the menu bar → **Preferences** → tick **Launch Hammerspoon at login**. Otherwise the puppets are gone after you restart your Mac.
5. **Start a new Claude Code session** (`claude` in a new terminal tab), so it surely reads the new hooks.

## 6. Try it

Ask Claude anything in the new session. The puppet thinks, then types and shoots invaders; when Claude finishes, it says the first sentence of the answer. Click the puppet to jump to that terminal.

To see ping pong, ask Claude for two subagents at once, for example: *"Use two subagents in parallel: one lists this folder, the other prints today's date."*

Run Claude in a second tab and a second puppet, in another colour, sits down next to the first.

## Choose what plays

There are three animations: **Coder** (the puppet shoots invaders on its monitor), **Matrix** (the same desk, with green code rain on the monitor) and **Ping pong** (two puppets, one per subagent). By default every turn plays: the coder, or ping pong while subagents run. To choose, click the `▟▙` icon in the menu bar:

```
Hide puppets
Animation to Commands Mapping
    Coder:      my-coding-skill  …
    Matrix:     my-planner  …
    Ping pong:  my-reviewer  …
Main conversation:
      Coder
      Matrix
    ✓ Ping pong while subagents run, else coder
      Off
Move to <each of your screens>
```

- **Coder**, **Matrix** and **Ping pong:** click one, and type the slash commands or skills whose turns show that animation, comma separated, with or without the slash. A command is on one list only: adding it to one takes it off the others. A ping pong turn goes back to the coder once all its subagents are done and Claude carries on alone.
- **Main conversation:** every other turn, like chatting with Claude, or a command on neither list. **Off** keeps those turns quiet, so only your listed commands get a puppet.

A turn plays from when you type a listed command, or from when Claude calls a listed skill. Changes apply at once to every tab, and Hammerspoon keeps them across restarts.

Menu bar icon hidden behind the notch? Hold ⌘ and drag it to the right of the notch; macOS keeps it there. Or **Option-click any puppet** to open the same menu.

**Hide puppets** (or ⌃⌥⌘P) takes every puppet off the screen until you show them again, even after a restart; the `▟▙` icon dims meanwhile. To use other keys, change the `bindHotkeys` line in `~/.hammerspoon/init.lua`.

If you prefer a file, set the starting choice in `~/.hammerspoon/init.lua`, before the `start()` line. Once you change the choice in the menu, the menu's choice is used instead:

```lua
spoon.ClaudePuppet.coder = { "my-coding-skill" }
spoon.ClaudePuppet.matrix = { "my-planner" }
spoon.ClaudePuppet.pingpong = { "my-reviewer" }
spoon.ClaudePuppet.conversation = "off"  -- or "coder", "matrix", "auto"
```

`spoon.ClaudePuppet.pixel = 5` makes the puppets bigger (the default is 4).

## Update

```sh
git -C ~/.claude-puppet/src pull
```

Then:

1. Run [step 4](#4-connect-claude-code) again: a new version may listen to more events.
2. Click the Hammerspoon icon → **Reload Config**. The puppets come back where they were, with your menu choices.
3. Start new Claude Code sessions.

**Do you have a `~/.claude-puppet/hook.sh`?** Then you installed the older layout, where the Spoon was copied. After the `git pull`, switch to the linked layout once, then do the three steps above:

```sh
rm -rf ~/.hammerspoon/Spoons/ClaudePuppet.spoon ~/.claude-puppet/hook.sh
ln -sfn ~/.claude-puppet/src/ClaudePuppet.spoon ~/.hammerspoon/Spoons/ClaudePuppet.spoon
```

Step 4 then swaps the old hook for the new one in your Claude Code settings.

## Uninstall

```sh
cp ~/.claude/settings.json ~/.claude/settings.json.bak
jq '.hooks |= ((. // {}) | with_entries(.value |= map(select(all(.hooks[]; .command | test("claude-puppet") | not)))) | with_entries(select(.value | length > 0)))' \
  ~/.claude/settings.json > /tmp/claude-puppet-clean.json && mv /tmp/claude-puppet-clean.json ~/.claude/settings.json
rm -rf ~/.hammerspoon/Spoons/ClaudePuppet.spoon ~/.claude-puppet
defaults delete org.hammerspoon.Hammerspoon ClaudePuppet.choice 2>/dev/null
defaults delete org.hammerspoon.Hammerspoon ClaudePuppet.position 2>/dev/null
defaults delete org.hammerspoon.Hammerspoon ClaudePuppet.hidden 2>/dev/null
```

This removes the puppet's hooks from your Claude Code settings (keeping a backup), its files and the link in `~/.hammerspoon/Spoons`, and the menu choices, position and hidden state Hammerspoon kept for it. Then delete the three `ClaudePuppet` lines from `~/.hammerspoon/init.lua` and click **Reload Config**.

Hammerspoon itself stays: `brew uninstall --cask hammerspoon` removes it, and you can turn its Accessibility and Automation switches off in System Settings.

## If something does not work

- **No puppet at all:** click the Hammerspoon icon → **Console**. A red line names the problem; a common one is a typo in `~/.hammerspoon/init.lua`.
- **The puppet does not move while Claude works:** run `tail -f ~/.claude-puppet/events`. A line per event means the hook runs and the problem is on the Hammerspoon side (see Console). No lines: start a new Claude Code session, and check that `/hooks` in Claude Code lists `~/.claude-puppet/src/harnesses/claude/translate.sh`.
- **Cannot drag or click it:** Accessibility, step 5.2, including the remove-and-add-again fix.
- **No tab number, or a click does not reach the right tab:** in iTerm2, check the Automation switch (step 5.3). Inside tmux or Zellij the puppet cannot see iTerm's tab, so it falls back to the next rule.
- **A click does not reach the right window:** outside iTerm2 the puppet knows Terminal, Ghostty, WezTerm, Warp, VS Code, Hyper, Tabby and Zed. It brings the app forward and picks the window whose title has the project folder's name; in other terminals a click does nothing.
