#!/bin/sh
# The helpers in hook/puppet-lib.sh on their own: what a translator keeps from a payload, and what it drops.
# shellcheck disable=SC2034 # PUPPET_PAYLOAD is read by the library this sources
cd "$(dirname "$0")/.." || exit 1
failed=0
HOME=$(mktemp -d) || exit 1
export HOME
. hook/puppet-lib.sh

expect() {
  if [ "$2" != "$3" ]; then
    echo "puppet-lib: $1"
    echo "  got      '$2'"
    echo "  expected '$3'"
    failed=1
  fi
}

# deskmates_on: the marker the Spoon writes, naming a process that still runs.
mkdir -p "$HOME/.deskmates"
expect "no marker: off" "$(deskmates_on && echo on)" ""
sh -c 'exit 0' & dead=$!
wait "$dead"
echo "$dead" > "$HOME/.deskmates/on"
expect "a marker of a process that ended: off" "$(deskmates_on && echo on)" ""
echo "not a pid" > "$HOME/.deskmates/on"
expect "a marker with no pid: off" "$(deskmates_on && echo on)" ""
# puppet_exit_if_off: ends the shell while off, still printing what respond set; goes on while on.
expect "off: exits, respond still printed" "$(respond '{}'; puppet_exit_if_off; echo after)" "{}"
echo "$$" > "$HOME/.deskmates/on"
expect "a marker of a running process: on" "$(deskmates_on && echo on)" on
expect "on: goes on" "$(puppet_exit_if_off; echo after)" after
rm "$HOME/.deskmates/on"

# leading_command: a /command's name only, never a path or anything after it.
expect "a /command" "$(leading_command "/review the docs")" "/review"
expect "a /command alone" "$(leading_command "/my-coding-skill")" "/my-coding-skill"
expect "a plugin's /command" "$(leading_command "/plugin:do_it now")" "/plugin:do_it"
expect "a /command before a tab" "$(leading_command "/build	now")" "/build"
expect "no slash" "$(leading_command "review /build")" ""
expect "a path is not a command" "$(leading_command "/Users/me/my-app/notes.pdf summarise")" ""
expect "a path with a dot is not a command" "$(leading_command "/notes.pdf summarise")" ""
expect "a lone slash" "$(leading_command "/ hello")" ""

# is_test_command: a test runner in a command's place, not a word that merely contains one.
for command in "pytest -q" "python -m pytest tests" "python3 -m unittest discover" "npm test" "npm run test:unit" \
  "yarn test" "pnpm test" "pnpm run test" "pnpm vitest run" "bun test" "npx jest --watch=false" "go test ./..." \
  "cargo test" "mvn test" "./gradlew test" "make test" "tox -e py312" "bundle exec rspec spec" \
  "./node_modules/.bin/vitest run" "cd app && npm test" "cd app
  npm test" "CI=1 npm test" "uv run pytest" "timeout 300 pytest" "timeout -k 5 300 pytest" "nohup pytest &" \
  "npm run test-unit" "yarn test_e2e" "uv run --frozen pytest" "npx --yes jest" "FOO=\"a b\" pytest" \
  "bash -c \"npm test\"" "sh -lc 'cd app && pytest'" "nice -n 10 pytest" "env -i CI=1 npm test" \
  "cat > notes.txt <<EOF
hello
EOF
pytest -q" \
  "git commit -m \"\$(cat <<'EOF'
Fix the parser.
EOF
)\" && npm test" "python -c \"x=1<<y\"
npm test" "timeout -s KILL 300 pytest" \
  "sudo -u bob pytest" "npm --prefix app test" "make -C sub test" "make -j 4 test" "cargo +nightly test" \
  "pnpm --filter web test"; do
  expect "a test command: $command" "$(is_test_command "$command" && echo yes)" yes
done
for command in "cat jest.config.js" "grep -r pytest src" "npm install" "go build ./..." "cargo build" \
  "vim tests/test_api.py" "ls pytest.ini" "echo make test" "git commit -m 'npm test passes'" "pnpm install" \
  "cat > notes.txt <<EOF
pytest
EOF" "cat > notes.txt <<EOF
hello
npm test
EOF" "cat <<-'EOF' > plan.md
	npm test
	EOF" "npm run testing-docs-build" "echo \"a; pytest\"" \
  "bash -c \"echo pytest\"" "git commit -m \"\$(cat <<'EOF'
npm test
EOF
)\"" \
  "make -C test build" "sudo -u test ls" "cat <<\"1\" > notes.txt
npm test
1"; do
  expect "not a test command: $command" "$(is_test_command "$command" && echo yes)" ""
done

# The 4000-byte cut can split a character in two: the command is still read, and nothing goes to the agent.
long=$(printf '%3985s' '' | tr ' ' a)
expect "a cut inside a character still reads the command" \
  "$(LC_ALL=en_US.UTF-8 is_test_command "pytest; echo \"${long}ééé\"" && echo yes)" yes
expect "a cut inside a character prints nothing" \
  "$(LC_ALL=en_US.UTF-8 is_test_command "pytest; echo \"${long}ééé\"" 2>&1 >/dev/null)" ""
# An arithmetic shift is not a here-document: the next line is still read.
expect "a shift in \$((…)) is not a here-document" "$(is_test_command "echo \$((1<<3))
pytest" && echo yes)" yes

# A huge command (a script pasted inline) is judged by its first 4000 bytes, as jq would have cut it, and soon:
# reading a whole megabyte would keep the agent waiting minutes.
expect "a test command past 4000 bytes is not seen" \
  "$(is_test_command "echo $(printf '%5000s' '' | tr ' ' x); npm test" && echo yes)" ""
big=$(head -c 1000000 /dev/zero | tr '\0' x)
(is_test_command "$big pytest"; echo judged > "$HOME/big.judged") &
watched=$!
waited=0
while [ ! -e "$HOME/big.judged" ] && [ "$waited" -lt 60 ]; do sleep 1; waited=$((waited + 1)); done
pkill -P "$watched" 2> /dev/null; kill "$watched" 2> /dev/null
expect "a 1 MB command is judged within a minute" "$(cat "$HOME/big.judged" 2> /dev/null)" judged

# Text is cut by characters, never inside one, even when the hook runs with the C locale (a background process).
a119=$(printf '%119s' '' | tr ' ' a)
PUPPET_PAYLOAD="{\"message\":\"${a119}éèê\",\"last_assistant_message\":\"$(printf '%89s' '' | tr ' ' b)€€ more\"}"
expect "field cuts at 120 characters" "$(export LC_ALL=C; field message)" "${a119}é"
expect "first_sentence cuts at 90 characters" "$(export LC_ALL=C; first_sentence last_assistant_message)" \
  "$(printf '%89s' '' | tr ' ' b)€"
# A byte that is not UTF-8 is dropped; the characters around it stay.
expect "cut_chars drops a stray byte" "$(printf 'abc\351def' | cut_chars 5)" abcde
expect "cut_chars drops a stray byte before the last character" "$(printf 'a\303\251\351x' | cut_chars 5)" "$(printf 'a\303\251x')"
expect "cut_chars keeps a text without one" "$(printf '\303\251t\303\251' | LC_ALL=C cut_chars 2)" "$(printf '\303\251t')"
mkdir -p "$HOME/.deskmates"
(export LC_ALL=C PUPPET_NOW=0 PUPPET_TTY=; write_event claude Stop s1 "" "" "" "" "/Users/me/${a119}ü✓" "" "")
expect "the folder is cut at 120 characters" "$(LC_ALL=C cut -d'|' -f8 "$HOME/.deskmates/events")" "${a119}ü"

# The payload is parsed once per event: with jq, one jq run and no plutil, even for a 5 MB tool result (each
# field read used to pipe the whole payload into its own plutil, keeping the agent waiting a second).
found_jq=$PUPPET_JQ
if [ -n "$found_jq" ]; then
  mkdir -p "$HOME/bin"
  printf '#!/bin/sh\necho run >> "%s/plutil.log"\nexec /usr/bin/plutil "$@"\n' "$HOME" > "$HOME/bin/plutil"
  printf '#!/bin/sh\necho run >> "%s/jq.log"\nexec "%s" "$@"\n' "$HOME" "$found_jq" > "$HOME/bin/jq"
  chmod +x "$HOME/bin/plutil" "$HOME/bin/jq"
  runs() { cat "$HOME/$1.log" 2>/dev/null | wc -l | tr -d ' '; }
  PATH="$HOME/bin:$PATH" PUPPET_JQ="$HOME/bin/jq" PUPPET_NOW=0 PUPPET_TTY=/dev/ttys009 \
    harnesses/claude/translate.sh < harnesses/claude/fixtures/tool-tests.json
  expect "with jq, plutil runs for no field" "$(runs plutil)" 0
  expect "with jq, one jq run for the payload" "$(runs jq)" 1
  rm -f "$HOME/plutil.log" "$HOME/jq.log"
  head -c 3700000 /dev/zero | tr '\0' x | fold -w 100 | "$found_jq" -Rs '{session_id: "big", cwd: "/Users/dev/my-app",
    hook_event_name: "PostToolUse", tool_name: "Read", tool_input: {file_path: "/Users/dev/my-app/big.txt"},
    tool_response: {type: "text", file: {filePath: "/Users/dev/my-app/big.txt", content: ., numLines: 37000}}}' \
    > "$HOME/big.json"
  # Deskmates runs: off, the translator would stop before writing.
  echo "$$" > "$HOME/.deskmates/on"
  PATH="$HOME/bin:$PATH" PUPPET_JQ="$HOME/bin/jq" PUPPET_NOW=0 PUPPET_TTY=/dev/ttys009 \
    harnesses/claude/translate.sh < "$HOME/big.json"
  expect "a 5 MB payload: no plutil" "$(runs plutil)" 0
  expect "a 5 MB payload: one jq run" "$(runs jq)" 1
  expect "a 5 MB payload: its line is written" "$(tail -n 1 "$HOME/.deskmates/events")" \
    "0|PostToolUse|big||Read|||my-app|${TERM_PROGRAM:-}||/dev/ttys009|claude|"
else
  echo "puppet-lib: no jq on this Mac: its checks are skipped, plutil's run"
fi

# Without jq (macOS 13 and 14), plutil reads each field: the same helpers, the same answers.
PUPPET_PAYLOAD='{"a":{"b":"one|two\nthree"},"n":3,"t":true,"z":null,"list":["x","y"],"cwd":"/Users/me/my-app"}'
for jq in "$PUPPET_JQ" ""; do
  PUPPET_JQ=$jq
  puppet_parse_payload
  mode=${jq:+jq}
  mode=${mode:-plutil}
  expect "$mode: a nested field, on one line without |" "$(field a.b)" "one two three"
  expect "$mode: a number" "$(field n)" 3
  expect "$mode: true" "$(field t)" true
  expect "$mode: null is nothing" "$(field z)" ""
  expect "$mode: a missing key is nothing" "$(field nope)" ""
  [ -n "$jq" ] && expect "jq: an object is nothing" "$(field a)" ""
  expect "$mode: an array item" "$(path_field list.1)" y
  expect "$mode: a path" "$(path_field cwd)" /Users/me/my-app
  expect "$mode: json_value" "$(printf '{"x":{"y":"deep"}}' | json_value x.y)" deep
  expect "$mode: json_value of a missing key" "$(printf '{"x":1}' | json_value y)" ""
done

# With jq, what the table holds (CONTRIBUTING.md, "Helpers"): 4 keys deep, 16 items of an array, 4000 characters
# of a text.
if [ -n "$found_jq" ]; then
  PUPPET_JQ=$found_jq
  PUPPET_PAYLOAD=$("$found_jq" -n '{a: {b: {c: {d: "four", e: {f: "five"}}}}, list: [range(20) | tostring],
    text: ([range(4100)] | map("x") | join(""))}')
  puppet_parse_payload
  expect "jq: 4 keys deep" "$(field a.b.c.d)" four
  expect "jq: not 5" "$(field a.b.c.e.f)" ""
  expect "jq: the 16th item" "$(field list.15)" 15
  expect "jq: not the 17th" "$(field list.16)" ""
  expect "jq: a text up to 4000 characters" "$(payload_value text | wc -c | tr -d ' ')" 4001
fi

# Claude Code's daemon: a session run by one of its workers (`claude bg-spare`) sends hooks from the worker's own
# pty, which no tab shows. The daemon names the claude that started it (`--spawned-by {…"pid":N}`): the session's
# terminal is N's. A fake process tree, by ps: the hook (its own pid) on ttys001, under the worker 500 on ttys001,
# under the pty host 400, under the daemon 300 started by the claude 200 on ttys002. `owner` says whether the
# claude 200 still runs (else it has no terminal). In a plain tab (`plain`), the hook's parent is the claude 200.
fake_tree() {
  tree_mode=$1
  hook_tty=${2:-}
  hook=$$
  ps() {
    case "$*" in
      *"ppid=,command= -t ttys001"*)
        case "$tree_mode" in
          plain) echo "100 -zsh" ;;
          direct) echo "400 /Users/me/.local/share/claude/versions/2.1.319 --session-id f1 --fork-session --resume /x.jsonl" ;;
          agent) echo "400 /Users/me/.local/share/claude/versions/2.1.319 --session-id a1 --agent claude --inherit-permission-mode auto" ;;
          *) echo "400 claude bg-spare --bg-spare /tmp/cc/spare/a.claim.sock" ;;
        esac ;;
      *"ppid=,command= -t ttys002"*) echo "1 -zsh"; echo "150 claude" ;;
      *"-t ttys001"*)
        case "$tree_mode" in
          plain) echo -zsh ;;
          direct) echo "/Users/me/.local/share/claude/versions/2.1.319 --session-id f1 --fork-session --resume /x.jsonl" ;;
          agent) echo "/Users/me/.local/share/claude/versions/2.1.319 --session-id a1 --agent claude --inherit-permission-mode auto" ;;
          *) echo "claude bg-spare --bg-spare /tmp/cc/spare/a.claim.sock" ;;
        esac ;;
      *"-t ttys002"*) echo -zsh; echo claude ;;
      *"tty= -p $hook") if [ "$hook_tty" = notty ]; then echo '??'; elif [ "$tree_mode" = plain ]; then echo ttys002; else echo ttys001; fi ;;
      *"tty= -p 500") echo ttys001 ;;
      *"tty= -p 200") [ "$tree_mode" = gone ] && echo '??' || echo ttys002 ;;
      *"tty= -p "*) echo '??' ;;
      *"ppid=,command= -p $hook") [ "$tree_mode" = plain ] && echo "200 /bin/sh translate.sh" || echo "500 /bin/sh translate.sh" ;;
      *"ppid=,command= -p 500") [ "$tree_mode" = direct ] &&
          echo "400 /Users/me/.local/share/claude/versions/2.1.319 --session-id f1 --fork-session --resume /x.jsonl" ||
          echo "400 claude bg-spare --bg-spare /tmp/cc/spare/a.claim.sock" ;;
      *"ppid=,command= -p 400") echo "300 claude bg-pty-host --bg-pty-host /tmp/cc/spare/a.pty.sock 200 50" ;;
      *"ppid=,command= -p 300") echo '1 /Users/me/.local/bin/claude daemon run --origin transient --spawned-by {"label":"claude","cwd":"/Users/me/my-app","pid":200}' ;;
      *" command= -p 400") [ "$tree_mode" = direct ] || [ "$tree_mode" = agent ] &&
          echo "/Applications/ClaudeCode.app/Contents/MacOS/claude --bg-pty-host /tmp/cc/pty/f1.sock 171 44 -- /x" ||
          echo "claude bg-pty-host --bg-pty-host /tmp/cc/spare/a.pty.sock 200 50" ;;
      *" command= -p 100"|*" command= -p 150"|*" command= -p 1") echo "-zsh" ;;
      *"ppid= -p $hook") [ "$tree_mode" = plain ] && echo 200 || echo 500 ;;
      *"ppid= -p 500") echo 400 ;;
      *"ppid= -p 400") echo 300 ;;
      *"ppid= -p "*) echo 1 ;;
      *) echo 1 ;;
    esac
  }
}
mkdir -p "$HOME/.deskmates"
PUPPET_DIR="$HOME/.deskmates"
expect "a daemon's session: the terminal of the claude that started the daemon" \
  "$(fake_tree daemon; puppet_tty d1)" /dev/ttys002
expect "and remembered" "$(cat "$PUPPET_DIR/tty-d1")" /dev/ttys002
rm -f "$PUPPET_DIR/tty-d1"
expect "a daemon whose claude is gone: no terminal, never the worker's" "$(fake_tree gone; puppet_tty d2)" ""
# Live (5 Nov): a z-kb puppet stayed for good. Its claude was gone, and the terminal remembered for the session (the
# worker's pty, from before the daemon was understood) still ran the idle worker, which ps names claude.
printf '%s' /dev/ttys001 > "$PUPPET_DIR/tty-d4"
expect "a daemon whose claude is gone: not the worker's pty remembered for it" "$(fake_tree gone; puppet_tty d4)" ""
printf '%s' /dev/ttys002 > "$PUPPET_DIR/tty-d5"
expect "a daemon whose claude is gone: not a tab remembered for it either" "$(fake_tree gone; puppet_tty d5)" ""
expect "a plain tab: its own terminal" "$(fake_tree plain; puppet_tty d3)" /dev/ttys002
# Live (7 Nov, Claude Code 2.1.319): the daemon also runs a session itself on its pty, under a `--bg-pty-host`
# (a session forked from a tab's): no bg-spare there, and the tab went on in that session.
expect "a session the daemon runs itself: the terminal of the claude that started the daemon" \
  "$(fake_tree direct; puppet_tty d6)" /dev/ttys002
expect "is_daemon_pty: the daemon's own session" "$(fake_tree direct; is_daemon_pty /dev/ttys001 && echo yes)" yes
# Final review (7 Nov): the same daemon also ran a background agent of its own (`--agent claude`, no --resume): not
# the tab's conversation, so not the tab's terminal, or the two puppets would close each other.
# Live (7 Nov): in the daemon, Claude Code runs hooks with no terminal of their own. The session's pty came from the
# terminal remembered for it, or from an ancestor (the session itself), and no one asked whether it was the daemon's.
expect "a hook with no terminal, under the daemon: the tab's terminal" "$(fake_tree direct notty; puppet_tty d8)" /dev/ttys002
printf '%s' /dev/ttys001 > "$PUPPET_DIR/tty-d9"
expect "a hook with no terminal, the daemon's pty remembered: the tab's terminal" \
  "$(fake_tree direct notty; puppet_tty d9)" /dev/ttys002
expect "and the tab's is remembered instead" "$(cat "$PUPPET_DIR/tty-d9")" /dev/ttys002
expect "a daemon's own agent, not the tab's conversation: no terminal" "$(fake_tree agent; puppet_tty d7)" ""
expect "is_daemon_pty: a plain tab" "$(fake_tree plain; is_daemon_pty /dev/ttys002 && echo yes)" ""

# No helper leaves a variable behind: the shell's variables before and after each public helper (run in this
# shell, as a translator runs them) differ only in the helper-private names (_puppet_…) and the documented PUPPET_*.
snap_vars() {
  set | grep -E '^[A-Za-z_][A-Za-z0-9_]*=' |
    grep -Ev '^(_|BASH[A-Z_]*|RANDOM|SRANDOM|SECONDS|LINENO|PIPESTATUS|OLDPWD|EPOCH[A-Z]*|snap_[a-z]*)='
}
# leaks command…: runs the command here; nothing, or the names of the variables it changed that it should not.
leaks() {
  snap_vars > "$HOME/snap.before"
  "$@" > /dev/null 2>&1
  snap_vars > "$HOME/snap.after"
  cat "$HOME/snap.before" "$HOME/snap.after" | sort | uniq -u | cut -d= -f1 | sort -u |
    grep -Ev '^(_puppet_|PUPPET_)' | tr '\n' ' '
}
printf '{"cwd":"%s","text":"Fixed the typo. Then more.","session_id":"s1"}' "$HOME" > "$HOME/payload.json"
expect "leak: puppet_find_jq" "$(leaks puppet_find_jq)" ""
expect "leak: deskmates_on" "$(leaks deskmates_on)" ""
expect "leak: puppet_read_payload" "$(leaks puppet_read_payload < "$HOME/payload.json")" ""
puppet_read_payload < "$HOME/payload.json"
expect "leak: payload_value" "$(leaks payload_value cwd)" ""
expect "leak: json_value" "$(echo '{"a":1}' | { leaks json_value a; })" ""
expect "leak: field" "$(leaks field cwd)" ""
expect "leak: path_field" "$(leaks path_field cwd)" ""
expect "leak: first_sentence" "$(leaks first_sentence text)" ""
expect "leak: leading_command" "$(leaks leading_command "/build now")" ""
expect "leak: terminal_of" "$(leaks terminal_of $$)" ""
expect "leak: daemon_owner_tty" "$(leaks daemon_owner_tty)" ""
expect "leak: puppet_tty" "$(unset PUPPET_TTY; leaks puppet_tty s1)" ""
expect "leak: puppet_tty, cached" "$(unset PUPPET_TTY; printf '%s' /dev/ttys999 > "$PUPPET_DIR/tty-s9"; leaks puppet_tty s9)" ""
expect "leak: tty_from_program" "$(leaks tty_from_program zsh)" ""
expect "leak: claimed_by_other" "$(printf '%s' /dev/ttys998 > "$PUPPET_DIR/tty-s8"; leaks claimed_by_other /dev/ttys997)" ""
expect "leak: write_event" "$(PUPPET_NOW=0; unset PUPPET_TTY; leaks write_event claude Stop s1 "" "" "" "" "$HOME/x" "" "")" ""
# A translator's own names survive the helpers it calls directly.
expect "a translator's tty, app and folder survive" \
  "$(tty=keep app=keep folder=keep; unset PUPPET_TTY; write_event claude Stop s1 "" "" "" "" "$HOME/x" "" ""
     tty_from_program zsh > /dev/null; printf '%s %s %s' "$tty" "$app" "$folder")" "keep keep keep"

rm -rf "$HOME"
[ "$failed" = 0 ] && echo "puppet-lib: ok"
exit "$failed"
