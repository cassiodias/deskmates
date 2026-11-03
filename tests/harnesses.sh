#!/bin/sh
# Runs every harness translator on its fixtures and compares each written line (without its time) with the
# expected one. No agent and no Hammerspoon needed.
cd "$(dirname "$0")/.."
failed=0
work=$(mktemp -d)
for payload in harnesses/*/fixtures/*.json; do
  harness=$(echo "$payload" | cut -d/ -f2)
  expected="${payload%.json}.line"
  rm -rf "$work/.deskmates" "$work/.codex"
  # <name>.home holds files the case needs in its home (like Codex's session index).
  [ -d "${payload%.json}.home" ] && cp -R "${payload%.json}.home/." "$work/"
  stdout=$(HOME="$work" PUPPET_NOW=0 PUPPET_TTY=/dev/ttys009 TERM_PROGRAM=iTerm.app "harnesses/$harness/translate.sh" < "$payload")
  got=$(cut -d'|' -f2- "$work/.deskmates/events" 2>/dev/null)
  if [ ! -s "$expected" ] && [ -e "$work/.deskmates/events" ]; then
    echo "harness $harness: $(basename "$payload") wrote a line, expected none"
    failed=1
  elif [ -s "$expected" ] && [ "$got" != "$(cat "$expected")" ]; then
    echo "harness $harness: $(basename "$payload") wrote"
    echo "  $got"
    echo "  expected"
    echo "  $(cat "$expected")"
    failed=1
  fi
  if [ -e "${payload%.json}.stdout" ] && [ "$stdout" != "$(cat "${payload%.json}.stdout")" ]; then
    echo "harness $harness: $(basename "$payload") printed '$stdout'"
    failed=1
  fi
done
rm -rf "$work"
[ "$failed" = 0 ] && echo "harnesses: ok"
exit "$failed"
