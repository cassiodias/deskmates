# Contributing

Thanks for helping. The puppets are a small Hammerspoon Spoon fed by agent hooks; the design is in
[docs/architecture.md](docs/architecture.md). This page is the practical part.

## Layout

```
harnesses/<agent>/            the hook side of one coding agent
  hooks.json                  registers translate.sh for that agent's events
  translate.sh                the agent's payload → one event line (uses hook/puppet-lib.sh)
  fixtures/*.json, *.line     payload samples and the exact line each must produce
hook/puppet-lib.sh            shared by translators; the only code that writes the events file
ClaudePuppet.spoon/
  init.lua                    the Spoon's public variables, start/stop, and wiring
  lib/puppet/
    config.lua                sizes, timings, colours
    events/                   parse (line → event), reader (follows the file)
    model/                    sessions (state per session), mapping (command → animation), status (in words)
    harnesses/                the Spoon side of each agent, and the registry
    render/                   pixels, text, sprites, and scenes/ (one file per animation)
    stage/                    the puppet windows and their bubbles
    terminals/                bringing a session's terminal forward (iTerm tabs)
    ui/menu.lua               the menu bar menu
tests/                        run.sh runs them all
```

Rules that keep it easy to change:

- `events`, `model` and `render` never call Hammerspoon (`hs.*`), except text styling; they get what they need
  passed in, so they run in the tests.
- The core never asks which agent it is; it asks the session's harness (`toolKind`, `capabilities`, `focus`).
- The event line format lives in `hook/puppet-lib.sh` and `events/parse.lua` only.

## Run the tests

You need Lua 5.4 (`brew install lua@5.4`), the version Hammerspoon runs.

```sh
tests/run.sh
```

- `scenario_test.lua` drives the whole Spoon through every scene with a stand-in for Hammerspoon and compares
  every frame with `tests/snapshots/scenario.txt`. If you changed a drawing on purpose, record it again with
  `UPDATE=1 lua5.4 tests/scenario_test.lua` and check the diff.
- `sessions_test.lua` runs the session model with a fake agent.
- `status_test.lua` checks the status line and the card's text.
- `harness_contract_test.lua` checks every harness has what the Spoon expects.
- `harnesses.sh` runs every translator on its fixtures.

To try your copy for real, link it instead of the installed one and click Reload Config in Hammerspoon:

```sh
ln -sfn "$PWD/ClaudePuppet.spoon" ~/.hammerspoon/Spoons/ClaudePuppet.spoon
```

## Add an agent (a harness)

Use `claude` as the example; each part is small.

1. **Hook side**, `harnesses/<agent>/`:
   - `translate.sh`: source `hook/puppet-lib.sh`, read the payload, map the agent's event names to Claude Code's
     (`UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`,
     `SubagentStart`, `SubagentStop`, `Notification`, `Stop`, `SessionEnd`), and call `write_event <agent> ...`.
     Print whatever the agent needs in order not to block (Cursor wants `{}`), and always exit 0.
   - `hooks.json`: the agent's own hook registration, pointing at
     `~/.claude-puppet/src/harnesses/<agent>/translate.sh`.
   - `fixtures/`: real payloads, ideally from a live run of the agent, and the line each must produce.
2. **Spoon side**, `ClaudePuppet.spoon/lib/puppet/harnesses/<agent>.lua`: `id`, `name`, `capabilities`,
   `character.body` and `character.palette`, `toolKind(tool)` and `focus(session, terminals)`; then add it to
   `harnesses/init.lua`. The body is one of `BODIES` in `render/sprites.lua` (`claude`, `owl`, `cat`), or a new one
   drawn there in the same four poses and sizes: each agent gets its own creature and colours, never a logo.
3. **Install steps** in INSTALL.md: where the agent's hooks file lives and how to merge `hooks.json` into it.
4. Run `tests/run.sh`.

Missing events are fine: an agent without permission events simply never shows the permission sign.

## Add an animation

1. A scene is one file in `render/scenes/` with `draw(buf, texts, session, ctx)`; a new monitor screen is one file
   like `matrix.lua`, registered in `monitor.lua`.
2. To let people map commands to it, add it to `Mapping.SCENES` in `model/mapping.lua` (and to
   `CONVERSATION_CHOICES` if the main conversation may use it).
3. Add moments to `tests/scenario_test.lua`, record the snapshots, and check them by eye.

## Pull requests

- Keep each change focused, with tests passing (`tests/run.sh`).
- No logos or brand mascots in the drawings.
- Do not log prompts, commands or code: translators keep only a leading `/command`, a skill name, a notification,
  the first sentence of a reply, and the short names the agent gives its work (the session's title, a
  subagent's description).
