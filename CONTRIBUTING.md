# Contributing

Thanks for helping. This page is for changing Deskmates: how it fits together, how to run the tests, and the
steps to add an agent, a creature or an animation. Paths are from the root of this repo.

## How it fits together

```
agent ──hook──▶ harnesses/<agent>/translate.sh ──▶ ~/.deskmates/events ──▶ Deskmates.spoon ──▶ puppets
                (agent's JSON → one line)          (one line per event)    (reads, draws)
```

- **Hook side** (shell). Each agent runs `harnesses/<agent>/translate.sh` on its events. The translator turns
  the agent's JSON payload into one line, written by `write_event` in `hook/puppet-lib.sh`, and maps the agent's
  event names to a shared list: Claude Code's names (the table below).
- **The events file.** One line per event, 13 fields separated by `|`:
  `time|event|session|agent id|tool|agent type|text|folder|terminal app|flag|tty|harness|title`. Only
  `hook/puppet-lib.sh` writes it and only `Deskmates.spoon/lib/puppet/events/parse.lua` reads it.
- **Spoon side** (Lua, in Hammerspoon). It follows the file, keeps one session per `session`, and draws one
  puppet per busy session. The core never asks which agent it is: it asks the session's harness module
  (`Deskmates.spoon/lib/puppet/harnesses/<agent>.lua`) what a tool means, how the puppet looks, and how to
  bring its terminal forward.

## Layout

```
bin/deskmates                 install, uninstall, status, update
harnesses/<agent>/            the hook side of one coding agent
  translate.sh                the agent's payload → one event line (sources hook/puppet-lib.sh)
  hooks.json                  the agent's own hook registration, pointing at translate.sh
  detect.sh, config.sh        is the agent on this Mac; which file holds its hooks
  install.sh, uninstall.sh    add and remove our hooks in that file (source hook/install-lib.sh)
  present.sh                  optional: are our hooks on, for a hooks file install-lib cannot read
  fixtures/                   payload samples and the exact line each must produce
hook/puppet-lib.sh            shared by translators; the only code that writes the events file
hook/install-lib.sh           shared by install scripts: backups, merging and removing hooks in JSON files
Deskmates.spoon/
  init.lua                    the Spoon's public variables, start/stop, and wiring
  lib/puppet/
    config.lua                sizes, timings, colours
    events/                   parse (line → event), reader (follows the file)
    model/                    sessions (state per session), mapping (command → animation), status (in words)
    harnesses/                the Spoon side of each agent, and the registry
    render/                   pixels, text, sprites (the creatures), and scenes/ (one file per animation)
    stage/                    the puppet windows and their bubbles
    terminals/                bringing a session's terminal forward; the programs each terminal runs
    ui/menu.lua               the menu bar menu
tests/                        run.sh runs them all
tools/screenshots/            makes the README's pictures
```

Rules that keep it easy to change:

- `events`, `model` and `render` never call Hammerspoon (`hs.*`), except text styling; they get what they need
  passed in, so they run in the tests.
- The core never asks which agent it is; it asks the session's harness (`toolKind`, `character`, `focus`,
  `program`).
- The event line format lives in `hook/puppet-lib.sh` and `events/parse.lua` only.

## Run the tests

You need Lua 5.4 (`brew install lua@5.4`, the version Hammerspoon runs) and `jq`.

```sh
tests/run.sh
```

- `scenario_test.lua` and `codex_scenario_test.lua` drive the whole Spoon through every scene with a stand-in
  for Hammerspoon and compare every frame with `tests/snapshots/`. If you changed a drawing on purpose, record
  it again with `UPDATE=1 lua5.4 tests/scenario_test.lua` and check the diff.
- `sessions_test.lua` runs the session model with a fake agent; `status_test.lua` checks the status line and
  the card's text; `settings_test.lua` checks the saved settings carry over from the old name.
- `harness_contract_test.lua` checks every harness and every creature (see "What the tests check for you").
- `harnesses.sh` runs every translator on its fixtures; `codex_tty.sh` checks how Codex finds its terminal;
  `cursor_turns.sh` replays Cursor's end-of-turn events in the orders it sends them.
- `install.sh` runs the installer against a fake `HOME`, for every harness; it never touches your real files.

To try your copy for real, link it instead of the installed one and click Reload Config in Hammerspoon:

```sh
ln -sfn "$PWD/Deskmates.spoon" ~/.hammerspoon/Spoons/Deskmates.spoon
```

The hooks run `~/.deskmates/src`, so to try a translator, link that to your copy too, or copy your files there.

## Add an agent

Use the agent closest to yours as the example, under `harnesses/<id>/` and
`Deskmates.spoon/lib/puppet/harnesses/<id>.lua`: Codex for hooks that run away from the terminal and a failure
hidden in a tool's result; Cursor for its own event names, a flat hooks file, subagents seen only as a tool,
and a reply that comes on its own event. Work in this order.

### 1. Capture real payloads

Point **every** event the agent documents at a throwaway script that saves what it receives: agents often fire
only some of their documented events, and the capture is how you find out which. Use absolute paths in the
agent's hooks file (some agents read a relative path from their own folder, and not every one expands `~`).
Before the run, check what the agent does when a hook prints nothing: if silence blocks it, print what it
expects. Then make the script executable (`chmod +x ~/capture.sh`).

```sh
#!/bin/sh
# ~/capture.sh: appends each payload, then a "#" line with the time, the hook's terminal and its parents.
p=$(cat)
chain=""; pid=$$
while [ -n "$pid" ] && [ "$pid" -gt 1 ]; do
  chain="$chain > $(ps -o tty=,comm= -p "$pid" | awk '{n=split($2,a,"/"); print $1":"a[n]}')"
  pid=$(ps -o ppid= -p "$pid" | tr -d ' ')
done
{ printf '%s\n' "$p"
  printf '# time=%s tty=%s TERM_PROGRAM=%s chain=%s\n' "$(date +%s)" "$(ps -o tty= -p $$ | tr -d ' ')" \
    "$TERM_PROGRAM" "$chain"
} >> ~/agent-payloads.jsonl
```

Use the agent for a few minutes, one thing at a time, noting the time of each: a prompt, a `/command`, reading
a file, an edit, a command that works and one that fails, a test run, a subagent, a question, a permission
(approve one, refuse one), interrupting a turn (Ctrl-C) and sending one more prompt, quitting, and closing a
tab with the agent still open. If the agent has an app too, send a prompt from the app's chat and from its
built-in terminal: both may fire the same hooks. Then turn the hooks off and read the file (`jq` helps: `grep -v '^#' file | jq
-r .hook_event_name | uniq -c` shows what fired, in order).

Payloads hold your prompts, commands and code. Keep the file to yourself; the fixtures you make from it keep
only the fields the translator reads, with neutral text (`my-app`, `Fixed the typo.`).

Note for each event: its name, where the session id, folder, tool name and reply text are, how a failed tool
looks, whether the agent waits for an answer on stdout, and where the hook runs. The `#` line's chain shows
it: a terminal (`ttys…`) on the hook or one of its parents means `write_event` finds it on its own; `??` all
the way up means the hooks run in a background process, and you need `puppet_tty_fallback` (step 3). Also note:

- the events that never fired, and what you did that fired nothing (a refused permission may leave no trace);
- the order of events at the end of a turn, and whether it changes from turn to turn;
- how a subagent shows: its own events, or only a tool call, and whether the subagent's own tool calls arrive
  under the main session or as a session of their own;
- where the session's title is, if anywhere (the transcript, or a file of the agent's).
- whether the agent also runs other agents' hooks. Cursor runs Claude Code's (`~/.claude/settings.json`) as
  well as its own, so with Deskmates installed for Claude Code, Cursor's events also reach Claude's translator.
  Look in `~/.deskmates/events` for lines from another harness with your session's id.

### 2. Fixtures

In `harnesses/<agent>/fixtures/`, one case per behaviour: `NAME.json` (a trimmed payload) and `NAME.line` (the
line it must write, without the time field). An empty `NAME.line` means "writes nothing" (an event you drop).
Add `NAME.stdout` when the translator must print something for the agent, and a `NAME.home/` folder for files
the case needs in its home (it is copied into a fresh fake `HOME`). The translator runs with
`PUPPET_TTY=/dev/ttys009 TERM_PROGRAM=iTerm.app`.

Have at least a Stop: without it the puppet never finishes a turn, and the contract test fails.

A translator that keeps something between events (step 3) gets one fixture per step, with the state it starts
from in `NAME.home/.deskmates/`. To check the steps chained in the orders you saw, add a script like
`tests/cursor_turns.sh` that feeds fixtures in turn into one home, and a line for it in `tests/run.sh` (which
runs each script by name).

### 3. translate.sh

The agent runs it with the payload on stdin. Source the library, read the payload, map the event, call
`write_event`, exit 0:

```sh
#!/bin/sh
. "$(dirname "$0")/../../hook/puppet-lib.sh"
puppet_read_payload
event=$(field hook_event_name)
case "$event" in
  prompt_sent) event=UserPromptSubmit; text=$(leading_command "$(field prompt)") ;;
  turn_done) event=Stop; text=$(first_sentence reply) ;;
  *) exit 0 ;;     # events with no counterpart are dropped
esac
write_event myagent "$event" "$(field session_id)" "" "$(field tool_name)" "" "$text" "$(path_field cwd)" "" ""
exit 0
```

`write_event harness event session agent_id tool agent_type text cwd flag title` takes its arguments in that
order (it adds the time, the terminal app and the tty itself). What each event must carry:

| Event | Send it when | Fields the Spoon reads | Without it |
| --- | --- | --- | --- |
| `UserPromptSubmit` | you send a prompt | `text`: the prompt's leading `/command` only (`leading_command`); `title` | each turn carries on the last one (score, subagents, reply), command animations never play, and a session judged closed never comes back |
| `PreToolUse` | a tool is about to run | `tool`; `text`: the skill's name for a skill tool, the subagent's short description for a subagent tool; `flag=test` for a test command | the puppet never types or shoots |
| `PostToolUse` | a tool succeeded | `tool`, `flag` (same as its `PreToolUse`) | a test never shows its ✓, and a permission sign stays up until the next tool call |
| `PostToolUseFailure` | a tool failed | `tool`, `flag` | a failed test shows as passed |
| `PermissionRequest` | the agent waits for your approval | `tool` | no "May I use…?" sign |
| `SubagentStart` | a subagent starts | `agent_id` (not empty), `agent_type`, `text`: its description | no ping pong |
| `SubagentStop` | a subagent ends | the same `agent_id` | ping pong never ends |
| `Notification` | the agent wants your attention | `text` | no bubble |
| `Stop` | the turn ends | `text`: the reply's first sentence (`first_sentence`); `title` | **required**: the puppet keeps working for 2 hours |
| `SessionEnd` | the session closes | nothing | the puppet stays until its tab closes |

On every event: `session` is a stable id per session, `cwd` the project folder, and `agent_id` is empty on
the main conversation and set to the subagent's id inside one. `title` is the name the agent gives the
session, when it has one. Never pass prompts, commands or code: only what the table names.

Helpers in `hook/puppet-lib.sh`:

- `field key.path` (one line, `|` removed, cut to 120 characters), `path_field key` (a whole path),
  `first_sentence key`, `leading_command text`, `is_test_command command`, `json_value key` (JSON on stdin).
- `respond json`: prints `json` when the translator exits, however it exits, for agents that wait for an
  answer (Codex wants `{}` after `Stop`). Call it before anything that may exit, including the `exit 0` that
  drops an event, when the agent waits on that event. Print nothing otherwise: the tests expect no output
  without a `.stdout` file.
- `puppet_tty_fallback`: define it when the agent runs hooks in a background process with no terminal; it
  prints the session's terminal. `puppet_tty_fallback() { tty_from_program codex; }` finds the agent's
  process working in the session's folder.

A failure that the agent reports as a normal tool result (Codex: `Exit code: 1` in the output) is your
translator's to spot and turn into `PostToolUseFailure`.

When the agent's events do not line up with the table (`harnesses/cursor/translate.sh` handles each of these):

- **The folder is not in `cwd`.** Pass whatever holds it; `path_field` reads array items too
  (`path_field workspace_roots.0`).
- **No subagent events, only a subagent tool.** Turn the tool's start into `SubagentStart` and its result into
  `SubagentStop`, with the tool call's id as `agent_id` and its description as `text`.
- **A subagent's own events arrive as a session of their own.** Drop them, or they draw a second puppet; find
  what tells them apart in the capture (Cursor: the generation id equals the session id).
- **The reply comes on its own event, before or after the end of the turn, sometimes after the next prompt.**
  Pair them by the agent's own id for the turn (Cursor: `generation_id`), not by arrival order, and keep what
  came first in a file `$PUPPET_DIR/<agent>-<session>.<turn>.<what>`; remove the files on `SessionEnd`. Write
  `Stop` when the turn ends, so the puppet stops working then; a reply that comes later for the same turn may
  send a second `Stop` with its text (the bubble just changes), but drop one whose turn is over.
- **Another agent's payloads reach your translator** (step 1): drop them by a field only that agent sends
  (Claude's translator drops payloads with `cursor_version`).
- **Two end-of-turn events for one turn** (Cursor on Ctrl-C: `aborted`, then `error`): write one `Stop`.

### 4. hooks.json, detect.sh, config.sh, install.sh, uninstall.sh

- `hooks.json`: the agent's own hook registration, in its own format, with every command
  `~/.deskmates/src/harnesses/<agent>/translate.sh`.
  The tests want the `~` spelling here. If the agent runs a hook's command as a path rather than through a shell
  (Cursor), `~` may not be expanded: your `install.sh` then writes the home out in full (see Cursor's).
- `detect.sh`: exits 0 when the agent is on this Mac (`[ -d "$HOME/.myagent" ] || command -v myagent`). Skip a
  command name other tools may have (Cursor's CLI is also called `agent`; its `detect.sh` looks for
  `cursor-agent`).
- `config.sh`: prints the path of the file the agent keeps its hooks in.
- `install.sh`, `uninstall.sh`: copy Codex's and change the agent's name and the `todo` line (what the user
  still has to do by hand). They hand the file `config.sh` prints to `install_hooks` and `uninstall_hooks` in
  `hook/install-lib.sh`, which back it up (`.bak` keeps the file from before Deskmates, `.last.bak` the one
  from before the latest change), touch only our commands and say where the hooks went. A jq filter given to
  `install_hooks` rewrites `hooks.json` first (Cursor's spells out the home). The library understands a JSON
  file with an event map under `"hooks"`, either nested (`{"hooks": {event: [{"hooks": [{"command": …}]}]}}`,
  Claude Code and Codex) or flat (`{"version": 1, "hooks": {event: [{"command": …}]}}`). Other top-level keys
  in `hooks.json` (like `"version": 1`) are added to the user's file when it has none, and stay there on
  uninstall.
- An agent whose hooks are not in such a file writes its own `install.sh` and `uninstall.sh`, plus an
  executable `present.sh` that exits 0 when our hooks are on (`deskmates status` and `update` use it).

Make every script executable (`chmod +x`).

### 5. The Spoon module and the registry line

`Deskmates.spoon/lib/puppet/harnesses/<agent>.lua` returns a table; `claude.lua` documents every field:

- `id` (the name `write_event` writes) and `name` (shown in bubbles, like "Codex needs you").
- `capabilities`: which of `prompt`, `tools`, `toolFailure`, `subagents`, `permission`, `question`, `reply`,
  `sessionEnd`, `notification` the agent reports. Each `true` must have a fixture that shows it.
- `character = { body = "…", palette = { colours } }`: the creature, and its colours: each session's puppet takes the first one no
  other puppet wears (five is plenty).
- `toolKind(tool)`: `"reading"`, `"question"`, `"plan"`, `"skill"`, `"agent"` (starts a subagent) or `nil`.
- `focus(session, terminals)`: what a click does. `terminals.focus(session)` brings the terminal tab forward;
  `terminals.app(bundleId, session.folder)` brings an app's window forward, for an agent that runs in its own
  app. `session.app` is the `TERM_PROGRAM` the hook saw; when that is ambiguous for your agent, decide here
  (Cursor's terminal says `vscode`, like VS Code's, so `cursor.lua` brings Cursor forward). An agent with an app
  of its own may fire the same hooks from the app's chat, with no terminal at all. A line with no terminal app
  is read as a background session, which leaves once it rests; to keep its puppet at the desk, have the
  translator name the app when `TERM_PROGRAM` is empty (Cursor's writes `Cursor`), bring the app forward
  for it in `focus`, and name it in `apps` so the puppet leaves when the app quits. The contract test
  can check it with a stand-in `terminals` table.
- `program` (optional): the program name, or a list of names, its sessions run in their terminal (the last
  part of `ps -o comm`). The session ends once its terminal no longer runs it; for agents that report the end
  of a session late, or never.
- `apps` (optional): `{ [app on its lines] = bundle id }`, the apps its sessions run inside with no terminal
  (Cursor: `{ Cursor = "com.todesktop.230313mzl4w4u92" }`). Such a session ends once its app no longer runs;
  for an app that says nothing when it quits.

Then add the line in `Deskmates.spoon/lib/puppet/harnesses/init.lua`.

### 6. Check, then show it

- `tests/run.sh`. The install round trip, the fixture checks and the contract checks run for your agent with
  nothing added. Add install cases of your own to `tests/install.sh` only for what is special about it.
- Optional: a scenario test like `tests/codex_scenario_test.lua`, which records the creature frame by frame.
- `README.md` (the Agents table: what it shows and what it does not) and `INSTALL.md` (where its hooks go,
  anything the user must do by hand, `deskmates install <agent>`).
- A picture: add a scene to `tools/screenshots/shoot.sh` (see below).

### What the tests check for you

For every harness and creature, with nothing to add:

- every body has `SIDE` and `SMILE` (9 × 9) and `FRONT` and `FRONT_ASLEEP` (9 wide, up to 8 tall), in colours
  `config.COLORS` has; the harness's body exists;
- the harness has its fields, and its scripts are executable;
- every fixture line names this harness and one of the events above, and the Spoon takes them all without an
  error; there is a Stop among them; every `true` capability has a fixture that shows it; a translator prints
  nothing unless the case has a `.stdout` file;
- `hooks.json` points at its own translator; install, install again (same file), `deskmates status` (hooks
  on), uninstall (your hooks back as they were).

## Add a creature

A creature is one table in `BODIES` in `Deskmates.spoon/lib/puppet/render/sprites.lua`, independent of any
agent: four poses of rows of colour keys, where `c` is the session's colour and `.` is see-through. `SIDE` and
`SMILE` face the monitor on the right, and the desk scene draws the paws from column 9. Use the keys in
`config.COLORS`; a new colour goes there too. Then name it in a harness's `character.body`, and add it to
`tools/screenshots/bodies.lua` for a picture. Each agent gets its own creature and colours, never a logo or a
brand's mascot.

## Add an animation

Animations come in two kinds, and each is chosen per command in the menu (`model/mapping.lua`).

- **A new monitor screen**, shown on the desk like Matrix: one file like `render/scenes/matrix.lua` with
  `draw(buf, session, ctx)`, registered in `SCREENS` in `render/scenes/monitor.lua`. The Spoon picks the
  screen in `Deskmates.spoon/init.lua` (the `monitor =` line, which today chooses between `matrix` and
  `invaders`); add yours there.
- **A new whole scene**, like ping pong: one file in `render/scenes/` with `draw(buf, texts, session, ctx)`,
  a line in `SCENES` in `render/scenes/init.lua`, and a branch in `Sessions.sceneFor` in `model/sessions.lua`
  saying when a session plays it.

Then:

1. To let people map commands to it, add it to `Mapping.SCENES` in `model/mapping.lua` (and to
   `CONVERSATION_CHOICES` if the main conversation may use it).
2. Add moments to `tests/scenario_test.lua`, record the snapshots, and check them by eye.

## Refresh the screenshots

With Hammerspoon running your working copy (linked as above) and `require("hs.ipc")` in
`~/.hammerspoon/init.lua`:

```sh
tools/screenshots/shoot.sh
```

It plays each scene from a scratch events file, with neutral names and fake tabs, and saves it in
`docs/images/`; your real sessions and menu choice come back at the end. A new scene is a few lines in
`shoot.sh`. Check each picture before you commit it.

## Pull requests

- Keep each change focused, with `tests/run.sh` passing.
- No logos or brand mascots in the drawings.
- Do not log prompts, commands or code: translators keep only a leading `/command`, a skill's name, a
  notification, the first sentence of a reply, and the short names the agent gives its work (the session's
  title, a subagent's description). Fixtures use neutral text.
