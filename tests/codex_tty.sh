#!/bin/sh
# Codex runs its hooks with no terminal: the hook finds the codex process working in the session's folder.
# Two sessions in one folder: each takes a terminal no other session has claimed. pgrep, ps and lsof are fakes:
# terminals ttys011 and ttys012 run codex; ttys060 runs cursor-agent; ttys050 runs only a shell; ttys099 has
# nothing running any more.
cd "$(dirname "$0")/.." || exit 1
failed=0
work=$(mktemp -d)
folder=$(cd "$work" && pwd -P)
mkdir -p "$work/bin" "$work/home/.deskmates"
# Deskmates runs: its marker names a live process (this test).
echo "$$" > "$work/home/.deskmates/on"
# pgrep finds the codex processes, or none while the file "none" is there (then only a remembered terminal can
# give the session its own).
cat > "$work/bin/pgrep" <<X
#!/bin/sh
[ -e "$work/none" ] && exit 1
printf '11\\n12\\n13\\n'
X
cat > "$work/bin/ps" <<'X'
#!/bin/sh
case "$*" in
  *"-t ttys099"*) ;;
  *"-t ttys050"*) case "$*" in *comm=*) echo -zsh ;; *) echo 50 ;; esac ;;
  *"comm= -t ttys060"*) echo -zsh; echo /usr/local/bin/cursor-agent ;;
  *"comm= -t "*) echo -zsh; echo /opt/homebrew/bin/codex ;;
  *tty=*) case "$*" in *" 11") echo ttys011 ;; *" 12") echo ttys012 ;; *) echo '??' ;; esac ;;
  *) echo 1 ;;
esac
X
cat > "$work/bin/lsof" <<X
#!/bin/sh
echo p1; echo "n$folder"
X
chmod +x "$work/bin/"*
run() {
  printf '{"session_id":"%s","cwd":"%s","hook_event_name":"UserPromptSubmit","prompt":"hello"}' "$1" "$folder" |
    HOME="$work/home" PATH="$work/bin:/usr/bin:/bin" PUPPET_NOW=0 harnesses/codex/translate.sh
  tail -n 1 "$work/home/.deskmates/events" | cut -d'|' -f11
}
check() { if [ "$2" != "$3" ]; then echo "codex tty: $1: got '$2', expected '$3'"; failed=1; fi; }
check "first session" "$(run s1)" /dev/ttys011
check "second session in the same folder" "$(run s2)" /dev/ttys012
check "first session keeps its terminal" "$(run s1)" /dev/ttys011
rm "$work/home/.deskmates/tty-"*
echo /dev/ttys011 > "$work/home/.deskmates/tty-s1"
echo /dev/ttys012 > "$work/home/.deskmates/tty-s2"
check "all claimed: the first match" "$(run s3)" /dev/ttys011

# A remembered terminal with nothing running in it any more is not trusted: the hook looks again.
rm "$work/home/.deskmates/tty-"*
echo /dev/ttys099 > "$work/home/.deskmates/tty-s1"
check "a terminal gone from the cache is found again" "$(run s1)" /dev/ttys011
check "and remembered" "$(cat "$work/home/.deskmates/tty-s1")" /dev/ttys011

# Nor is one that runs something else now: Codex quit there without SessionEnd and the session was resumed in
# another tab, whose codex is the one to find.
echo /dev/ttys050 > "$work/home/.deskmates/tty-s1"
check "a cached terminal no longer running codex is found again" "$(run s1)" /dev/ttys011

# With no codex process to find, only a remembered terminal gives the session one: it counts while it runs codex
# (ps may give its whole path), and not once it runs only a shell.
touch "$work/none"
echo /dev/ttys011 > "$work/home/.deskmates/tty-s1"
check "a cached terminal running codex, by its whole path, is trusted" "$(run s1)" /dev/ttys011
echo /dev/ttys050 > "$work/home/.deskmates/tty-s1"
check "a cached terminal running only a shell is not" "$(run s1)" ""

# Cursor's CLI the same way: a remembered terminal counts while it runs cursor-agent (or agent).
cursor_sid=11111111-2222-4333-8444-555555555555
echo /dev/ttys060 > "$work/home/.deskmates/tty-$cursor_sid"
HOME="$work/home" PATH="$work/bin:/usr/bin:/bin" PUPPET_NOW=0 harnesses/cursor/translate.sh \
  < harnesses/cursor/fixtures/prompt.json
check "a cached terminal running cursor-agent is trusted" \
  "$(tail -n 1 "$work/home/.deskmates/events" | cut -d'|' -f11)" /dev/ttys060
echo /dev/ttys050 > "$work/home/.deskmates/tty-$cursor_sid"
HOME="$work/home" PATH="$work/bin:/usr/bin:/bin" PUPPET_NOW=0 harnesses/cursor/translate.sh \
  < harnesses/cursor/fixtures/prompt.json
check "a cached terminal running only a shell is not, for Cursor either" \
  "$(tail -n 1 "$work/home/.deskmates/events" | cut -d'|' -f11)" ""
rm "$work/none"

# What sessions leave behind expires after the Spoon's 2 hours: Codex and Cursor often skip SessionEnd.
rm "$work/home/.deskmates/tty-"*
old=$(date -v-3H +%Y%m%d%H%M)
for name in tty-gone cursor-gone.turn cursor-gone.g1.reply myagent-gone.state events on; do
  echo /dev/ttys011 > "$work/home/.deskmates/$name"
  touch -t "$old" "$work/home/.deskmates/$name"
done
echo "$$" > "$work/home/.deskmates/on"
touch -t "$old" "$work/home/.deskmates/on"
# The source copy in ~/.deskmates/src is never touched, however old its files.
mkdir -p "$work/home/.deskmates/src/bin"
echo old > "$work/home/.deskmates/src/bin/deskmates"
touch -t "$old" "$work/home/.deskmates/src/bin/deskmates" "$work/home/.deskmates/src/README.md" "$work/home/.deskmates/src"
echo /dev/ttys005 > "$work/home/.deskmates/tty-recent"
check "an old claim does not hold a terminal" "$(run s4)" /dev/ttys011
for name in tty-gone cursor-gone.turn cursor-gone.g1.reply myagent-gone.state; do
  check "$name expired" "$(ls "$work/home/.deskmates/$name" 2>/dev/null)" ""
done
check "a recent cache stays" "$(cat "$work/home/.deskmates/tty-recent")" /dev/ttys005
check "the events file stays, however old" "$(head -n 1 "$work/home/.deskmates/events")" /dev/ttys011
# Found 7 Nov: the Spoon writes its marker once, at start; two hours on, a hook deleted it and every hook after
# took Deskmates for off (no facts, no plans, no card on a double click).
check "the marker that says Deskmates runs stays, however old" "$(cat "$work/home/.deskmates/on" 2>/dev/null)" "$$"
check "a file inside src stays" "$(cat "$work/home/.deskmates/src/bin/deskmates")" old
check "a file at the top of src stays" "$(ls "$work/home/.deskmates/src/README.md")" "$work/home/.deskmates/src/README.md"

# ~/.deskmates/src may be a link to a clone elsewhere: the link stays too.
mkdir -p "$work/clone" "$work/linked/.deskmates"
ln -s "$work/clone" "$work/linked/.deskmates/src"
touch -h -t "$old" "$work/linked/.deskmates/src"
echo "$$" > "$work/linked/.deskmates/on"
printf '{"session_id":"s9","cwd":"%s","hook_event_name":"UserPromptSubmit","prompt":"hello"}' "$folder" |
  HOME="$work/linked" PATH="$work/bin:/usr/bin:/bin" PUPPET_NOW=0 harnesses/codex/translate.sh
check "a linked src stays" "$([ -L "$work/linked/.deskmates/src" ] && echo link)" link
rm -rf "$work"
[ "$failed" = 0 ] && echo "codex tty: ok"
exit "$failed"
