#!/bin/sh
# Runs every harness translator on its fixtures and compares each written line (without its time) with the
# expected one. No agent and no Hammerspoon needed. Each fixture runs twice: reading the payload with jq, and
# with plutil alone (macOS 13 and 14 without jq).
cd "$(dirname "$0")/.." || exit 1
failed=0
# The jq the hooks would find (hook/puppet-lib.sh); without one, only the plutil pass runs, and it says so.
unset PUPPET_JQ
found_jq=$(HOME=/nonexistent sh -c '. hook/puppet-lib.sh; printf "%s" "$PUPPET_JQ"')
parsers="jq plutil"
if [ -z "$found_jq" ]; then
  echo "harnesses: no jq on this Mac: the jq pass is skipped, the plutil pass runs"
  parsers=plutil
fi
for parser in $parsers; do
  if [ "$parser" = plutil ]; then export PUPPET_JQ=; else export PUPPET_JQ="$found_jq"; fi
  for payload in harnesses/*/fixtures/*.json; do
    harness=$(echo "$payload" | cut -d/ -f2)
    name="$harness ($parser): $(basename "$payload")"
    expected="${payload%.json}.line"
    # Without jq there is no plan, so a plan change writes its line without the plan flag: <name>.nojq.line.
    [ "$parser" = plutil ] && [ -e "${payload%.json}.nojq.line" ] && expected="${payload%.json}.nojq.line"
    # Each case gets a home of its own, so nothing one leaves behind reaches the next.
    work=$(mktemp -d)
    # <name>.home holds files the case needs in its home (like Codex's session index).
    [ -d "${payload%.json}.home" ] && cp -R "${payload%.json}.home/." "$work/"
    # Deskmates runs: its marker names a live process (this runner).
    mkdir -p "$work/.deskmates" && echo "$$" > "$work/.deskmates/on"
    # @HOME@ in a payload is the case's home (a path the agent names there, like a plan file).
    sed "s|@HOME@|$work|g" "$payload" > "$work.payload"
    # LC_ALL=C: hooks may run from a background process, with no locale.
    stdout=$(LC_ALL=C HOME="$work" PUPPET_NOW=0 PUPPET_TTY=/dev/ttys009 TERM_PROGRAM=iTerm.app \
      "harnesses/$harness/translate.sh" < "$work.payload")
    got=$(cut -d'|' -f2- "$work/.deskmates/events" 2>/dev/null)
    if [ ! -e "$expected" ]; then
      echo "harness $name has no .line file"
      failed=1
    elif [ ! -s "$expected" ] && [ -e "$work/.deskmates/events" ]; then
      echo "harness $name wrote a line, expected none"
      failed=1
    elif [ -s "$expected" ] && [ "$got" != "$(cat "$expected")" ]; then
      echo "harness $name wrote"
      echo "  $got"
      echo "  expected"
      echo "  $(cat "$expected")"
      failed=1
    fi
    # <name>.plan is the plan the jq pass must leave in the plans folder (its time left out), and an empty one
    # means none may be left; without it the folder must hold no plan the case did not start with. Without jq
    # (the plutil pass) a case may delete a plan but never write one.
    expected_plan="${payload%.json}.plan"
    plans=$(cd "$work/.deskmates/plans" 2>/dev/null && ls)
    started=$(cd "${payload%.json}.home/.deskmates/plans" 2>/dev/null && ls)
    if [ "$parser" = jq ] && [ -e "$expected_plan" ] && [ ! -s "$expected_plan" ]; then
      if [ -n "$plans" ]; then
        echo "harness $name left plans, expected none: '$plans'"
        failed=1
      fi
    elif [ "$parser" = jq ] && [ -e "$expected_plan" ]; then
      got_plan=$("$found_jq" -S 'del(.updatedAt)' "$work/.deskmates/plans/"*.json 2>/dev/null)
      if [ "$plans" != "$(ls "$work/.deskmates/plans/" 2>/dev/null | head -n 1)" ] ||
        [ "$got_plan" != "$("$found_jq" -S . "$expected_plan")" ]; then
        echo "harness $name left the plan"
        echo "$got_plan" | sed 's/^/  /'
        echo "  expected"
        "$found_jq" -S . "$expected_plan" | sed 's/^/  /'
        failed=1
      fi
    elif [ "$parser" = plutil ] && [ -n "$(printf '%s\n' "$plans" | grep -vxF -e "$started" -e '')" ]; then
      echo "harness $name wrote a plan without jq: '$plans'"
      failed=1
    elif [ "$parser" = jq ] && [ ! -e "$expected_plan" ] && [ -n "$plans" ] && [ "$plans" != "$started" ]; then
      echo "harness $name left plans it should not have: '$plans'"
      failed=1
    fi
    # <name>.facts is the facts file the jq pass must leave in the facts folder (its time left out), and an empty
    # one means none may be left; without it the folder must hold no facts the case did not start with. Without
    # jq (the plutil pass) a case may delete facts but never write them.
    expected_facts="${payload%.json}.facts"
    facts=$(cd "$work/.deskmates/facts" 2>/dev/null && ls)
    facts_started=$(cd "${payload%.json}.home/.deskmates/facts" 2>/dev/null && ls)
    if [ "$parser" = jq ] && [ -e "$expected_facts" ] && [ ! -s "$expected_facts" ]; then
      if [ -n "$facts" ]; then
        echo "harness $name left facts, expected none: '$facts'"
        failed=1
      fi
    elif [ "$parser" = jq ] && [ -e "$expected_facts" ]; then
      got_facts=$("$found_jq" -S 'del(.updatedAt)' "$work/.deskmates/facts/"*.json 2>/dev/null)
      if [ "$facts" != "$(ls "$work/.deskmates/facts/" 2>/dev/null | head -n 1)" ] ||
        [ "$got_facts" != "$("$found_jq" -S . "$expected_facts")" ]; then
        echo "harness $name left the facts"
        echo "$got_facts" | sed 's/^/  /'
        echo "  expected"
        "$found_jq" -S . "$expected_facts" | sed 's/^/  /'
        failed=1
      fi
    elif [ "$parser" = plutil ] && [ -n "$facts" ] && [ "$facts" != "$facts_started" ]; then
      echo "harness $name wrote facts without jq: '$facts'"
      failed=1
    elif [ "$parser" = plutil ] && [ -n "$facts" ] &&
      ! cmp -s "$work/.deskmates/facts/$facts" "${payload%.json}.home/.deskmates/facts/$facts"; then
      echo "harness $name changed facts without jq"
      failed=1
    elif [ "$parser" = jq ] && [ ! -e "$expected_facts" ] && [ -n "$facts" ] && [ "$facts" != "$facts_started" ]; then
      echo "harness $name left facts it should not have: '$facts'"
      failed=1
    fi
    # Without a .stdout file the translator must print nothing: agents may read what it prints.
    expected_stdout=""
    [ -e "${payload%.json}.stdout" ] && expected_stdout=$(cat "${payload%.json}.stdout")
    if [ "$stdout" != "$expected_stdout" ]; then
      echo "harness $name printed '$stdout'"
      failed=1
    fi
    rm -rf "$work" "$work.payload"
  done
done
[ "$failed" = 0 ] && echo "harnesses: ok"
exit "$failed"
