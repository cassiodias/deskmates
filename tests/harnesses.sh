#!/bin/sh
# Runs every harness translator on its fixtures and compares each written line (without its time) with the
# expected one. No agent and no Hammerspoon needed.
cd "$(dirname "$0")/.." || exit 1
failed=0
for payload in harnesses/*/fixtures/*.json; do
  harness=$(echo "$payload" | cut -d/ -f2)
  expected="${payload%.json}.line"
  # Each case gets a home of its own, so nothing one leaves behind reaches the next.
  work=$(mktemp -d)
  # <name>.home holds files the case needs in its home (like Codex's session index).
  [ -d "${payload%.json}.home" ] && cp -R "${payload%.json}.home/." "$work/"
  # LC_ALL=C: hooks may run from a background process, with no locale.
  stdout=$(LC_ALL=C HOME="$work" PUPPET_NOW=0 PUPPET_TTY=/dev/ttys009 TERM_PROGRAM=iTerm.app "harnesses/$harness/translate.sh" < "$payload")
  got=$(cut -d'|' -f2- "$work/.deskmates/events" 2>/dev/null)
  if [ ! -e "$expected" ]; then
    echo "harness $harness: $(basename "$payload") has no .line file"
    failed=1
  elif [ ! -s "$expected" ] && [ -e "$work/.deskmates/events" ]; then
    echo "harness $harness: $(basename "$payload") wrote a line, expected none"
    failed=1
  elif [ -s "$expected" ] && [ "$got" != "$(cat "$expected")" ]; then
    echo "harness $harness: $(basename "$payload") wrote"
    echo "  $got"
    echo "  expected"
    echo "  $(cat "$expected")"
    failed=1
  fi
  # Without a .stdout file the translator must print nothing: agents may read what it prints.
  expected_stdout=""
  [ -e "${payload%.json}.stdout" ] && expected_stdout=$(cat "${payload%.json}.stdout")
  if [ "$stdout" != "$expected_stdout" ]; then
    echo "harness $harness: $(basename "$payload") printed '$stdout'"
    failed=1
  fi
  rm -rf "$work"
done
[ "$failed" = 0 ] && echo "harnesses: ok"
exit "$failed"
