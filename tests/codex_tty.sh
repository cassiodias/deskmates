#!/bin/sh
# Codex runs its hooks with no terminal: the hook finds the codex process working in the session's folder.
# Two sessions in one folder: each takes a terminal no other session has claimed. pgrep, ps and lsof are fakes:
# terminals ttys011 and ttys012 run codex; ttys099 has nothing running any more.
cd "$(dirname "$0")/.." || exit 1
failed=0
work=$(mktemp -d)
folder=$(cd "$work" && pwd -P)
mkdir -p "$work/bin" "$work/home/.deskmates"
cat > "$work/bin/pgrep" <<'X'
#!/bin/sh
printf '11\n12\n13\n'
X
cat > "$work/bin/ps" <<'X'
#!/bin/sh
case "$*" in
  *"-t ttys099"*) ;;
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

# What sessions leave behind expires after the Spoon's 2 hours: Codex and Cursor often skip SessionEnd.
rm "$work/home/.deskmates/tty-"*
old=$(date -v-3H +%Y%m%d%H%M)
for name in tty-gone cursor-gone.turn cursor-gone.g1.reply myagent-gone.state events; do
  echo /dev/ttys011 > "$work/home/.deskmates/$name"
  touch -t "$old" "$work/home/.deskmates/$name"
done
echo /dev/ttys005 > "$work/home/.deskmates/tty-recent"
check "an old claim does not hold a terminal" "$(run s4)" /dev/ttys011
for name in tty-gone cursor-gone.turn cursor-gone.g1.reply myagent-gone.state; do
  check "$name expired" "$(ls "$work/home/.deskmates/$name" 2>/dev/null)" ""
done
check "a recent cache stays" "$(cat "$work/home/.deskmates/tty-recent")" /dev/ttys005
check "the events file stays, however old" "$(head -n 1 "$work/home/.deskmates/events")" /dev/ttys011
rm -rf "$work"
[ "$failed" = 0 ] && echo "codex tty: ok"
exit "$failed"
