-- A session's facts as the hooks write them (hook/facts-lib.sh), read back: what is kept, what is dropped, and
-- that a broken file is no facts at all.

local root = arg[0]:match("^(.*)/tests/") or "."
package.path = root .. "/Deskmates.spoon/lib/?.lua;" .. root .. "/Deskmates.spoon/lib/?/init.lua;" .. package.path
local check = dofile(root .. "/tests/support/check.lua")
local facts = require("puppet.model.facts")

local dir = os.tmpname()
os.remove(dir)
os.execute("mkdir -p '" .. dir .. "'")
local function file(name, text)
  local f = io.open(dir .. "/" .. name, "w")
  f:write(text)
  f:close()
  return dir .. "/" .. name
end

local example = file("s1.json", [[{
  "current": "ABC-12",
  "tickets": {
    "ABC-12": { "phase": "review", "phaseAt": 300, "phases": { "plan": 100, "dev": 200, "review": 300 },
                "jira": { "status": "In Dev", "at": 250 }, "seen": 310 },
    "ABC-34": { "phase": "review", "phases": { "review": 50 }, "seen": 60 }
  },
  "timeline": [
    { "at": 310, "ticket": "ABC-12", "kind": "reply", "text": "ABC-12 is built.", "phase": "review" },
    { "at": 300, "ticket": "ABC-12", "kind": "phase", "text": "review", "phase": "review" },
    { "at": 250, "ticket": "ABC-12", "kind": "jira", "text": "In Dev", "phase": null }
  ],
  "updatedAt": 310
}]])
local f = facts.load(example)
check("load: current", f and f.current == "ABC-12")
local t = f and f.tickets["ABC-12"]
check("load: a ticket's phase and times", t and t.phase == "review" and t.phaseAt == 300 and t.seen == 310)
check("load: its phases", t and t.phases.plan == 100 and t.phases.dev == 200 and t.phases.review == 300)
check("load: its Jira status", t and t.jira and t.jira.status == "In Dev" and t.jira.at == 250)
check("load: the other ticket", f and f.tickets["ABC-34"] and f.tickets["ABC-34"].phases.review == 50)
check("load: the timeline in order", f and #f.timeline == 3 and f.timeline[1].text == "ABC-12 is built."
  and f.timeline[1].kind == "reply" and f.timeline[1].phase == "review" and f.timeline[3].phase == nil)
check("load: updatedAt", f and f.updatedAt == 310)
check("hasContent: tickets", facts.hasContent(f))

check("load: a missing file", facts.load(dir .. "/nope.json") == nil)
check("load: half a file", facts.load(file("half.json", '{"tickets": {')) == nil)
check("load: not an object", facts.load(file("array.json", "[1]")) == nil)
check("load: no tickets table", facts.load(file("none.json", '{"timeline": []}')) == nil)
local empty = facts.load(file("empty.json", '{"tickets": []}'))
check("load: an empty tickets list is no tickets", empty and next(empty.tickets) == nil and #empty.timeline == 0)
check("hasContent: no tickets", not facts.hasContent(empty))
check("hasContent: nil", not facts.hasContent(nil))
local odd = facts.load(file("odd.json", [[{
  "current": "ABC-99",
  "tickets": { "ABC-12": { "phase": 3, "phases": { "dev": "soon", "plan": 5 }, "jira": { "status": 1 }, "seen": 10 },
               "ABC-13": "junk" },
  "timeline": [ { "ticket": "ABC-12", "kind": "reply", "text": "no time" },
                { "at": 5, "ticket": "ABC-12", "kind": "reply", "text": "kept" }, 7 ]
}]]))
check("load: a bad phase is dropped, its ticket kept", odd and odd.tickets["ABC-12"] and odd.tickets["ABC-12"].phase == nil)
check("load: bad phase times dropped", odd and odd.tickets["ABC-12"].phases.dev == nil and odd.tickets["ABC-12"].phases.plan == 5)
check("load: a bad Jira status dropped", odd and odd.tickets["ABC-12"].jira == nil)
check("load: a ticket that is not a table dropped", odd and odd.tickets["ABC-13"] == nil)
check("load: entries without a time dropped", odd and #odd.timeline == 1 and odd.timeline[1].text == "kept")
check("load: current naming no ticket dropped", odd and odd.current == nil)

local ended = facts.load(file("ends.json", [[{"current": "ABC-12", "tickets": {"ABC-12": {"phase": "review", "seen": 5,
  "phases": {"dev": 1, "review": 3}, "ends": {"dev": {"at": 2, "outcome": "Applied."}, "review": {"at": 4, "outcome": "Two findings.",
  "verdict": "CHANGES_REQUESTED"}, "plan": {"outcome": "no time"}, "qa": {"at": 1, "outcome": "not a lane"}}}}, "timeline": []}]]))
local ends = ended and ended.tickets["ABC-12"].ends
check("load: a lane's end", ends and ends.dev.at == 2 and ends.dev.outcome == "Applied." and ends.dev.verdict == nil)
check("load: its verdict", ends and ends.review.verdict == "CHANGES_REQUESTED")
check("load: an end without a time, or of no lane, dropped", ends and ends.plan == nil and ends.qa == nil)
-- git, seen and turns: the session's edits as the hooks record them.
local full = facts.load(file("git.json", [[{
  "git": { "root": "/work/my-app", "base": "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678", "dirtyAtStart": ["src/a.js", "docs/ção.md"],
           "folder": "/work/my-app", "prefix": "", "top": null },
  "seen": { "src/app.js": true, "src/my file.js": true },
  "tickets": {}, "timeline": [],
  "turns": [
    { "at": 200, "head": "ffff", "files": ["src/app.js"], "tests": { "ran": 2, "passed": 1, "failed": 1 },
      "commits": [ { "hash": "a1b2c3d", "subject": "Fixed the typo." } ] },
    { "at": 100, "endAt": 150, "files": [], "tests": { "ran": 0, "passed": 0, "failed": 0 }, "commits": [] }
  ]
}]]))
check("git: root and base", full and full.git and full.git.root == "/work/my-app"
  and full.git.base == "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678")
check("git: dirty at start as a set", full and full.git.dirtyAtStart["src/a.js"] == true
  and full.git.dirtyAtStart["docs/ção.md"] == true and not full.git.dirtyAtStart["x"])
check("seen: a set of paths", full and full.seen["src/app.js"] == true and full.seen["src/my file.js"] == true)
local t1, t2 = full and full.turns[1], full and full.turns[2]
check("turns: newest first, as written", t1 and t2 and t1.at == 200 and t2.at == 100)
check("turns: open turn has no end, closed has", t1 and t1.endAt == nil and t2.endAt == 150)
check("turns: files", t1 and #t1.files == 1 and t1.files[1] == "src/app.js" and #t2.files == 0)
check("turns: tests", t1 and t1.tests.ran == 2 and t1.tests.passed == 1 and t1.tests.failed == 1)
check("turns: commits", t1 and #t1.commits == 1 and t1.commits[1].hash == "a1b2c3d"
  and t1.commits[1].subject == "Fixed the typo.")
check("hasGit: with git", facts.hasGit(full))
check("hasContent: git alone is no content", not facts.hasContent(full))

local gitOnly = facts.load(file("gitonly.json", '{"git": {"root": "/r", "base": "abcdef1"}}'))
check("git only: loads with no tickets", gitOnly and next(gitOnly.tickets) == nil and #gitOnly.timeline == 0)
check("git only: hasGit, no content, no turns", gitOnly and facts.hasGit(gitOnly) and not facts.hasContent(gitOnly)
  and #gitOnly.turns == 0 and next(gitOnly.seen) == nil and next(gitOnly.git.dirtyAtStart) == nil)
check("hasGit: nil and old facts", not facts.hasGit(nil) and not facts.hasGit(f))
check("load: old facts have no git, seen or turns", f and f.git == nil and next(f.seen) == nil and #f.turns == 0)

local function gitOf(json) local g = facts.load(file("g.json", '{"tickets": {}, "git": ' .. json .. "}")) return g and g.git end
check("git: a base that is not hex, no git", gitOf('{"root": "/r", "base": "main"}') == nil)
check("git: a base too short or too long, no git", gitOf('{"root": "/r", "base": "abc12"}') == nil
  and gitOf('{"root": "/r", "base": "' .. string.rep("a", 41) .. '"}') == nil)
check("git: a short 7-hex base is fine", gitOf('{"root": "/r", "base": "ABCDEF1"}') ~= nil)
check("git: no root, no git", gitOf('{"base": "abcdef1"}') == nil)
check("git: root not a string, no git", gitOf('{"root": 5, "base": "abcdef1"}') == nil)
check("git: not a table, no git", gitOf('"x"') == nil)
local dirty = gitOf('{"root": "/r", "base": "abcdef1", "dirtyAtStart": ["a.js", 3, {"x": 1}, "b.js"]}')
check("git: junk dirty entries dropped alone", dirty and dirty.dirtyAtStart["a.js"] and dirty.dirtyAtStart["b.js"]
  and not dirty.dirtyAtStart[3])
check("git: dirtyAtStart not a list is empty", next(gitOf('{"root": "/r", "base": "abcdef1", "dirtyAtStart": "a.js"}').dirtyAtStart) == nil)

local odd2 = facts.load(file("odd2.json", [[{
  "tickets": {},
  "git": "junk",
  "seen": { "a.js": true, "b.js": false, "c.js": "yes", "d.js": true },
  "turns": [ 7, { "files": ["no-time.js"] },
    { "at": 5, "endAt": "later", "files": ["a.js", 3, "b.js"], "tests": { "ran": "2", "passed": 1 },
      "commits": [ { "hash": "a1b2c3d" }, { "subject": "no hash" }, { "hash": "e4f5a6b", "subject": "Kept." }, "x" ] },
    { "at": 4, "files": "a.js", "tests": 3, "commits": "none" } ]
}]]))
check("load: a git that is not a table dropped, file kept", odd2 and odd2.git == nil and not facts.hasGit(odd2))
check("seen: only true entries kept", odd2 and odd2.seen["a.js"] and odd2.seen["d.js"] and not odd2.seen["b.js"]
  and not odd2.seen["c.js"])
check("turns: entries without a time dropped", odd2 and #odd2.turns == 2 and odd2.turns[1].at == 5)
local o1, o2 = odd2 and odd2.turns[1], odd2 and odd2.turns[2]
check("turns: a bad endAt dropped", o1 and o1.endAt == nil)
check("turns: junk files dropped alone", o1 and #o1.files == 2 and o1.files[1] == "a.js" and o1.files[2] == "b.js")
check("turns: bad test counts are zero", o1 and o1.tests.ran == 0 and o1.tests.passed == 1 and o1.tests.failed == 0)
check("turns: bad commits dropped alone", o1 and #o1.commits == 1 and o1.commits[1].hash == "e4f5a6b")
check("turns: bad files, tests and commits give empty ones", o2 and #o2.files == 0 and #o2.commits == 0
  and o2.tests.ran == 0 and o2.tests.passed == 0 and o2.tests.failed == 0)
check("load: seen and turns not tables give none", (function()
  local g = facts.load(file("g2.json", '{"tickets": {}, "seen": [1], "turns": "x"}'))
  return g and next(g.seen) == nil and #g.turns == 0
end)())
check("load: no tickets and no git is not facts", facts.load(file("g3.json", '{"seen": {"a.js": true}}')) == nil)

check("path: a session's file", facts.path(dir, "s1") == dir .. "/s1.json")
check("path: refuses a path out", facts.path(dir, "../x") == nil and facts.path(dir, "..") == nil)

-- sweep: old files of sessions it no longer knows go; kept sessions and fresh files stay.
file("old.json", '{"tickets": {}, "timeline": [], "updatedAt": 10}')
file("kept.json", '{"tickets": {}, "timeline": [], "updatedAt": 10}')
file("fresh.json", '{"tickets": {}, "timeline": [], "updatedAt": 990}')
facts.sweep(dir, { kept = true }, 1000, 100)
local function exists(name) local h = io.open(dir .. "/" .. name) if h then h:close() end return h ~= nil end
check("sweep: an old file goes", not exists("old.json"))
check("sweep: a broken file goes", not exists("half.json"))
check("sweep: a kept session's stays", exists("kept.json"))
check("sweep: a fresh one stays", exists("fresh.json"))

os.execute("rm -rf '" .. dir .. "'")
check.done("facts")
