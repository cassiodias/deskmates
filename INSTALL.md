# Install

**You need:** macOS 13 or later, [Homebrew](https://brew.sh), `git` (run `xcode-select --install` if `git --version` asks for it), `jq` (comes with macOS 15 and later; on macOS 13 or 14, run `brew install jq`) and Claude Code, Codex and/or Cursor's command-line agent (`agent`). iTerm2 is optional; with it, a click on a puppet selects its exact tab.

Steps 1 to 3 are copy and paste into a terminal. Step 4 is a few clicks in macOS that no script can do for you. It takes about 5 minutes.

## 1. Install Hammerspoon

[Hammerspoon](https://www.hammerspoon.org) is a free macOS automation app; it draws the puppets.

```sh
brew install --cask hammerspoon
```

## 2. Get the files

```sh
git clone https://github.com/cassiodias/deskmates.git ~/.deskmates/src
```

## 3. Install

```sh
~/.deskmates/src/bin/deskmates install
```

This one command:

- links `~/.hammerspoon/Spoons/Deskmates.spoon` to the source, so an update is a `git pull`;
- adds three lines to `~/.hammerspoon/init.lua` (Hammerspoon's config, created if you have none), unless they are there already, after saving a copy the same way as below (`init.lua.bak`, `init.lua.last.bak`); anything else in that file stays;
- adds Deskmates' hooks for each agent it finds on your Mac: Claude Code in `~/.claude/settings.json`, Codex in `~/.codex/hooks.json`, Cursor in `~/.cursor/hooks.json`. Before changing a file it saves a copy beside it: `.bak` is the file as it was before Deskmates first changed it, and is never overwritten (empty when there was no file before Deskmates); `.last.bak` is the file as it was just before the latest change, install, update or uninstall. A `.bak` that is already there is kept as it is, whatever it holds: older versions of Deskmates rewrote it on every run, so if you installed more than once with one of those, yours may hold Deskmates' hooks rather than your file from before. Everything else in the file (your other hooks included) is kept, and Deskmates' own hooks are replaced, so it is safe to run again.

To install for one agent only, name it: `~/.deskmates/src/bin/deskmates install codex` (or `claude`, `cursor`).

## 4. Things only you can do

1. **Open Hammerspoon:** run `open -a Hammerspoon`. It loads its config, and a puppet appears in the bottom right corner of your main screen, with a `▟▙` icon in the menu bar. On the very first launch Hammerspoon also shows a setup window.
2. **Allow Accessibility:** System Settings → Privacy & Security → **Accessibility** → turn on **Hammerspoon**. Without it you cannot drag the puppets or click them. If Hammerspoon is listed and already on but dragging does not work, the switch belongs to an older copy of the app: select Hammerspoon, remove it with **–**, add it again with **+** (Applications → Hammerspoon), turn it on, then quit and reopen Hammerspoon.
3. **Allow iTerm2 control** (iTerm2 only): the first time an agent session runs in iTerm2, macOS asks *"Hammerspoon wants to control iTerm2"*. Click **OK**: it is how each puppet shows its tab number and how a click selects that tab. If you clicked Don't Allow: System Settings → Privacy & Security → **Automation** → Hammerspoon → turn on iTerm2.
4. **Launch at login:** click the Hammerspoon icon in the menu bar → **Preferences** → tick **Launch Hammerspoon at login**. Otherwise the puppets are gone after you restart your Mac.
5. **Codex: trust the hooks.** Run `codex`, type `/hooks` and trust the Deskmates hooks. Codex asks again whenever the hooks change, for example after an update.
6. **Start a new session** (`claude`, `codex` or `agent` in a new terminal tab), so it surely reads the new hooks.

## 5. Try it

Ask the agent anything in the new session. The puppet thinks, then types and shoots invaders; when the agent finishes, it says the first sentence of the answer. Click the puppet to jump to that terminal.

To see ping pong, ask for two subagents at once, for example: *"Use two subagents in parallel: one lists this folder, the other prints today's date."*

Run an agent in a second tab and a second puppet, in another colour, sits down next to the first.

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

- **Coder**, **Matrix** and **Ping pong:** click one, and type the slash commands or skills whose turns show that animation, comma separated, with or without the slash. A command is on one list only: adding it to one takes it off the others. A ping pong turn goes back to the coder once all its subagents are done and the agent carries on alone.
- **Main conversation:** every other turn, like chatting with the agent, or a command on neither list. **Off** keeps those turns quiet, so only your listed commands get a puppet.

A turn plays from when you type a listed command, or from when the agent calls a listed skill. Changes apply at once to every tab, and Hammerspoon keeps them across restarts.

Menu bar icon hidden behind the notch? Hold ⌘ and drag it to the right of the notch; macOS keeps it there. Or **Option-click any puppet** to open the same menu.

**Hide puppets** (or ⌃⌥⌘P) takes every puppet off the screen until you show them again, even after a restart; the `▟▙` icon dims meanwhile. To use other keys, change the `bindHotkeys` line in `~/.hammerspoon/init.lua`.

If you prefer a file, set the starting choice in `~/.hammerspoon/init.lua`, before the `start()` line. Once you change the choice in the menu, the menu's choice is used instead:

```lua
spoon.Deskmates.coder = { "my-coding-skill" }
spoon.Deskmates.matrix = { "my-planner" }
spoon.Deskmates.pingpong = { "my-reviewer" }
spoon.Deskmates.conversation = "off"  -- or "coder", "matrix", "auto"
```

`spoon.Deskmates.pixel = 5` makes the puppets bigger (the default is 4).

## Update

```sh
~/.deskmates/src/bin/deskmates update
```

This pulls the latest source, installs again for the agents that have Deskmates' hooks, and reloads Hammerspoon; the puppets come back where they were, with your menu choices. Then start new agent sessions, and for Codex trust the hooks again with `/hooks`.

## Uninstall

```sh
~/.deskmates/src/bin/deskmates uninstall
```

This removes Deskmates' hooks from Claude Code's, Codex's and Cursor's settings (keeping a backup of each), the Spoon link, the three lines in `~/.hammerspoon/init.lua`, the menu choices, position and hidden state Hammerspoon kept, and `~/.deskmates`. To remove one agent's hooks only, name it: `deskmates uninstall codex`. Then click **Reload Config** in the Hammerspoon menu.

Hammerspoon itself stays: `brew uninstall --cask hammerspoon` removes it, and you can turn its Accessibility and Automation switches off in System Settings.

## Installed as claude-puppet before?

Update the copy you have and install from it, instead of steps 2 and 3:

```sh
cd ~/.claude-puppet/src && git pull && bin/deskmates install
```

It moves the old folder to `~/.deskmates` (keeping your puppets' recent events) and switches the Spoon link, the Hammerspoon lines and the hooks to the new paths; your own `spoon.ClaudePuppet` settings in `init.lua` carry over, renamed (a copy is in `init.lua.bak`). Then reload Hammerspoon and start new agent sessions.

## If something does not work

- **See where things stand:** run `~/.deskmates/src/bin/deskmates status`. For each agent it says whether it was found, whether its hooks are on, and when its last event came.
- **No puppet at all:** click the Hammerspoon icon → **Console**. A red line names the problem; a common one is a typo in `~/.hammerspoon/init.lua`.
- **The puppet does not move while the agent works:** run `tail -f ~/.deskmates/events`. A line per event means the hooks run and the problem is on the Hammerspoon side (see Console). No lines: first check that Hammerspoon is running and shows its puppets (while Deskmates is not running, hooks write only a short line when a turn ends); then start a new session, and check that `/hooks` in Claude Code or Codex lists `~/.deskmates/src/harnesses/<agent>/translate.sh` (for Codex, trusted); for Cursor, that `~/.cursor/hooks.json` names `…/.deskmates/src/harnesses/cursor/translate.sh`.
- **Cannot drag or click it:** Accessibility, step 4.2, including the remove-and-add-again fix.
- **No tab number, or a click does not reach the right tab:** in iTerm2, check the Automation switch (step 4.3). Inside tmux or Zellij the puppet cannot see iTerm's tab, so it falls back to the next rule.
- **A click does not reach the right window:** outside iTerm2 the puppet knows Terminal, Ghostty, WezTerm, Warp, VS Code, Hyper, Tabby and Zed. It brings the app forward and picks the window whose title has the project folder's name; in other terminals a click does nothing.
