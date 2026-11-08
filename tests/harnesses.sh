#!/bin/sh
# Runs every harness translator on its fixtures and compares each written line (without its time) with the
# expected one. No agent and no Hammerspoon needed. Each fixture runs twice: reading the payload with jq, and
# with plutil alone (macOS 13 and 14 without jq).
cd "$(dirname "$0")/.." || exit 1
failed=0

# Makes a repo at <home $1>/repo with the paths listed in file $2 committed, and prints its folder as git spells
# it (the real path: mktemp's folders sit behind a symlink).
repo_with() {
  mkdir -p "$1/repo" && (cd -P "$1/repo" && pwd -P) || return 1
  while IFS= read -r path; do
    mkdir -p "$1/repo/$(dirname "$path")" && echo "$path" > "$1/repo/$path"
  done < "$2"
  HOME=$1 GIT_CONFIG_NOSYSTEM=1 git -C "$1/repo" init -q &&
    HOME=$1 GIT_CONFIG_NOSYSTEM=1 git -C "$1/repo" add -A &&
    HOME=$1 GIT_CONFIG_NOSYSTEM=1 git -C "$1/repo" -c user.email=t@t -c user.name=t commit -q -m "Start"
}

# Stdin with @REPO@ and @BASE@ filled in from the case's repo and base, and back (unfill), for the facts
# compared; as it is when the case has no repo.
fill() {
  if [ -n "$repo" ]; then sed -e "s|@REPO@|$repo|g" -e "s|@BASE@|$base|g"; else cat; fi
}
unfill() {
  if [ -n "$repo" ]; then sed -e "s|$repo|@REPO@|g" -e "s|$base|@BASE@|g"; else cat; fi
}

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
    # <name>.repo lists the paths (one per line) of a repo made at <home>/repo with them committed: @REPO@ is
    # its folder (as git spells it) and @BASE@ its commit, in the payload and in the files of <name>.home.
    repo="" base=""
    if [ -e "${payload%.json}.repo" ]; then
      repo=$(repo_with "$work" "${payload%.json}.repo") && base=$(git -C "$repo" rev-parse HEAD) ||
        { echo "harness $name: no repo made"; failed=1; }
      grep -rlF --exclude-dir=.git -e @REPO@ -e @BASE@ "$work" | while IFS= read -r file; do
        fill < "$file" > "$file.filled" && mv "$file.filled" "$file"
      done
    fi
    # Deskmates runs: its marker names a live process (this runner).
    mkdir -p "$work/.deskmates" && echo "$$" > "$work/.deskmates/on"
    # @HOME@ in a payload is the case's home (a path the agent names there, like a plan file).
    sed "s|@HOME@|$work|g" "$payload" | fill > "$work.payload"
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
      got_facts=$("$found_jq" -S 'del(.updatedAt)' "$work/.deskmates/facts/"*.json 2>/dev/null | unfill)
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
      ! fill < "${payload%.json}.home/.deskmates/facts/$facts" | cmp -s - "$work/.deskmates/facts/$facts"; then
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
# Deskmates off (no marker naming a live process): a translator stops right after reading the payload. Nothing is
# written; Codex still gets the {} it waits for after Stop.
for case in claude/stop:'' codex/stop:'{}' cursor/prompt:''; do
  payload="harnesses/${case%%/*}/fixtures/${case#*/}"
  payload="${payload%%:*}.json"
  want=${case#*:}
  want=${want#\'}; want=${want%\'}
  work=$(mktemp -d)
  for marker in none dead; do
    rm -rf "$work/.deskmates"
    # A marker left by a Hammerspoon that crashed names no live process.
    [ "$marker" = dead ] && mkdir -p "$work/.deskmates" && echo 999999 > "$work/.deskmates/on"
    stdout=$(sed "s|@HOME@|$work|g" "$payload" | LC_ALL=C HOME="$work" PUPPET_NOW=0 PUPPET_TTY=/dev/ttys009 \
      TERM_PROGRAM=iTerm.app "harnesses/${case%%/*}/translate.sh")
    if [ -e "$work/.deskmates/events" ] || [ -e "$work/.deskmates/facts" ] || [ -e "$work/.deskmates/plans" ] ||
      [ -n "$(ls "$work/.deskmates" 2>/dev/null | grep -vx on)" ]; then
      echo "harness off ($marker marker): ${case%%:*} wrote: $(ls "$work/.deskmates")"
      failed=1
    fi
    if [ "$stdout" != "$want" ]; then
      echo "harness off ($marker marker): ${case%%:*} printed '$stdout', expected '$want'"
      failed=1
    fi
  done
  rm -rf "$work"
done
[ "$failed" = 0 ] && echo "harnesses: ok"
exit "$failed"
