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
-- passes: the steps in the order they happened, read with every field checked; junk dropped alone.
local stepped = facts.load(file("passes.json", [[{"current": "ABC-12", "tickets": {"ABC-12": {"phase": "dev", "seen": 9,
  "phases": {"dev": 1, "review": 3}, "ends": {"review": {"at": 2}},
  "passes": [ {"phase": "dev", "at": 5, "by": "Implement ABC-12 fixes"},
              {"phase": "dev", "at": 1, "endAt": 3, "by": "my-developer"},
              {"phase": "review", "at": 3, "endAt": 5, "verdict": "CHANGES_REQUESTED", "by": "QA ABC-12 review"},
              {"phase": "qa", "at": 2}, {"phase": "dev"}, {"phase": "dev", "at": "4"}, 7, "x",
              {"phase": "review", "at": 6, "endAt": "later", "by": 3, "verdict": false} ]}}, "timeline": []}]]))
local ps = stepped and stepped.tickets["ABC-12"].passes
check("passes: sorted by start, junk dropped alone", ps and #ps == 4 and ps[1].at == 1 and ps[2].at == 3
  and ps[3].at == 5 and ps[4].at == 6)
check("passes: their fields", ps and ps[1].phase == "dev" and ps[1].endAt == 3 and ps[1].by == "my-developer"
  and ps[2].phase == "review" and ps[2].verdict == "CHANGES_REQUESTED" and ps[3].endAt == nil
  and ps[3].by == "Implement ABC-12 fixes")
check("passes: bad optional fields dropped, the pass kept", ps and ps[4].phase == "review" and ps[4].endAt == nil
  and ps[4].by == nil and ps[4].verdict == nil)
-- Facts written before passes (or passes all junk): one pass per lane started, by its start; its end and verdict
-- from the lane's end when that is not before the start.
local old = facts.load(file("oldfacts.json", [[{"current": "ABC-12", "tickets": {"ABC-12": {"phase": "review", "seen": 9,
  "phases": {"plan": 1, "dev": 4, "review": 2},
  "ends": {"plan": {"at": 2, "outcome": "Plan approved"}, "review": {"at": 3, "outcome": "Two findings.", "verdict": "CHANGES_REQUESTED"},
           "dev": {"at": 5}},
  "passes": [7]}}, "timeline": []}]]))
local ops = old and old.tickets["ABC-12"].passes
check("passes from old facts: one per lane started, by its start", ops and #ops == 3 and ops[1].phase == "plan"
  and ops[2].phase == "review" and ops[3].phase == "dev" and ops[1].at == 1 and ops[2].at == 2 and ops[3].at == 4)
check("passes from old facts: ends and verdicts from the lanes' ends", ops and ops[1].endAt == 2 and ops[2].endAt == 3
  and ops[2].verdict == "CHANGES_REQUESTED" and ops[3].endAt == 5 and ops[1].verdict == nil)
check("passes from old facts: no by", ops and ops[1].by == nil and ops[2].by == nil)
local early = facts.load(file("early.json", [[{"tickets": {"ABC-12": {"phase": "dev", "phases": {"dev": 5},
  "ends": {"dev": {"at": 4, "verdict": "DONE"}}}}, "timeline": []}]]))
local eps = early and early.tickets["ABC-12"].passes
check("passes from old facts: an end before the start is not its end", eps and #eps == 1 and eps[1].endAt == nil
  and eps[1].verdict == nil)
local none = facts.load(file("nopass.json", [[{"tickets": {"ABC-12": {"seen": 1, "ends": {"dev": {"at": 4}}}}, "timeline": []}]]))
check("passes: none for a ticket with no lane started", none and #none.tickets["ABC-12"].passes == 0)

-- Live (6 Nov): facts written before passes, a session that went Dev and Review yesterday and again today. One
-- pass per lane, sorted by its first start, made Review run from yesterday to now: the Review step held today's
-- Dev lines. The timeline (its newest 30 lines) tells what happened today; the lanes' starts before it, the rest.
local function day(d, h, m) return os.time({ year = 2026, month = 11, day = d, hour = h, min = m, sec = 0 }) end
local lines, oldest = {}, {}
local function line(at, kind, text, phase) oldest[#oldest + 1] = { at = at, kind = kind, text = text, phase = phase } end
line(day(6, 14, 20), "subagent", "Implement ABC-12", "dev")
line(day(6, 14, 30), "done", "done", "dev")
line(day(6, 14, 31), "subagent", "Implement ABC-12 fixes", "dev")
for m = 32, 52 do line(day(6, 14, m), "reply", "Fixed one more test.", "dev") end
line(day(6, 14, 54), "subagent", "Implement the last fix", "dev")
line(day(6, 14, 55), "done", "done", "dev")
line(day(6, 14, 56), "phase", "review", "review")
line(day(6, 14, 56), "subagent", "Review phase steps diff", "review")
line(day(6, 14, 58), "reply", "Two findings, both fixed.", "review")
line(day(6, 14, 59), "done", "Approved.", "review")
for i = #oldest, 1, -1 do
  local l = oldest[i]
  lines[#lines + 1] = string.format('{"at": %d, "ticket": "ABC-12", "kind": "%s", "text": "%s", "phase": "%s"}',
    l.at, l.kind, l.text, l.phase)
end
local real = facts.load(file("yesterday.json", string.format([[{"current": "ABC-12", "tickets": {"ABC-12": {
  "phase": "review", "seen": %d, "phases": {"dev": %d, "review": %d},
  "ends": {"dev": {"at": %d}, "review": {"at": %d, "outcome": "Approved.", "verdict": "APPROVED"}}}},
  "timeline": [%s]}]], day(6, 14, 59), day(5, 15, 31), day(5, 15, 37), day(6, 14, 55), day(6, 14, 59),
  table.concat(lines, ","))))
local rps = real and real.tickets["ABC-12"].passes or {}
check("passes from old facts: the fixture is 30 lines", #lines == 30)
check("passes from old facts: yesterday's lanes before the timeline, each up to the next start", #rps == 4
  and rps[1].phase == "dev" and rps[1].at == day(5, 15, 31) and rps[1].endAt == day(5, 15, 37)
  and rps[2].phase == "review" and rps[2].at == day(5, 15, 37) and rps[2].endAt == day(6, 14, 20))
check("passes from old facts: today's Dev from its first line to its last end", rps[3] and rps[3].phase == "dev"
  and rps[3].at == day(6, 14, 20) and rps[3].endAt == day(6, 14, 55) and rps[3].by == "Implement ABC-12")
check("passes from old facts: today's Review from its start, with the lane's verdict", rps[4] and rps[4].phase == "review"
  and rps[4].at == day(6, 14, 56) and rps[4].endAt == day(6, 14, 59) and rps[4].verdict == "APPROVED"
  and rps[4].by == "Review phase steps diff")
-- An end whose start is not in the timeline is a step of no length; a start after it closes nothing.
local missed = facts.load(file("missed.json", string.format([[{"tickets": {"ABC-12": {"phase": "dev",
  "phases": {"review": %d, "dev": %d}}}, "timeline": [
  {"at": %d, "ticket": "ABC-12", "kind": "skill", "text": "my-developer", "phase": "dev"},
  {"at": %d, "ticket": "ABC-12", "kind": "done", "text": "done", "phase": "review"},
  {"at": %d, "ticket": "ABC-34", "kind": "phase", "text": "plan", "phase": "plan"}]}]],
  day(6, 9, 0), day(6, 9, 5), day(6, 9, 5), day(6, 9, 0), day(6, 8, 0))))
local mps = missed and missed.tickets["ABC-12"].passes or {}
check("passes from old facts: an end with no start is a step of its own; another ticket's lines are not this one's",
  #mps == 2 and mps[1].phase == "review" and mps[1].at == day(6, 9, 0) and mps[1].endAt == day(6, 9, 0)
  and mps[2].phase == "dev" and mps[2].at == day(6, 9, 5) and mps[2].endAt == nil and mps[2].by == "my-developer")

-- The phase a skill's name or a subagent's description names, by the hooks' word rules (hook/facts-lib.sh, phase).
check("phaseOf: a developer", facts.phaseOf("my-developer") == "dev")
check("phaseOf: QA", facts.phaseOf("QA ABC-12 lens break") == "review")
check("phaseOf: review wins over plan", facts.phaseOf("Review the plan") == "review")
check("phaseOf: dev wins over plan", facts.phaseOf("Implement the plan") == "dev")
check("phaseOf: only whole words", facts.phaseOf("rebuild the planet") == nil)
check("phaseOf: an engineer plans", facts.phaseOf("my-engineer") == "plan")
check("phaseOf: none", facts.phaseOf("commit") == nil and facts.phaseOf("") == nil)
-- Review (6 Nov): every line carries the ticket's phase at the time, a skill with no phase word too. Such a line
-- starts nothing: Review stays done with its verdict; a Dev ticket gets no extra step.
local function derive(name, phase, lines, ends)
  local out = {}
  for i = #lines, 1, -1 do
    local l = lines[i]
    out[#out + 1] = string.format('{"at": %d, "ticket": "ABC-12", "kind": "%s", "text": "%s", "phase": "%s"}', l[1], l[2], l[3], l[4])
  end
  local f = facts.load(file(name, '{"tickets": {"ABC-12": {"phase": "' .. phase .. '", "phases": {}' .. (ends or "")
    .. '}}, "timeline": [' .. table.concat(out, ",") .. "]}"))
  return f and f.tickets["ABC-12"].passes or {}
end
local afterDone = derive("afterdone.json", "review", { { 200, "subagent", "Review ABC-12", "review" },
  { 300, "done", "Approved.", "review" }, { 400, "skill", "commit", "review" } },
  ', "ends": {"review": {"at": 300, "verdict": "APPROVED"}}')
check("passes from old facts: a skill with no phase word after a done keeps the step done", #afterDone == 1
  and afterDone[1].endAt == 300 and afterDone[1].verdict == "APPROVED")
local devTicket = derive("devticket.json", "dev", { { 100, "subagent", "Implement ABC-12", "dev" },
  { 200, "done", "Two findings.", "review" }, { 300, "skill", "commit", "dev" } })
check("passes from old facts: a skill with no phase word starts no step", #devTicket == 2 and devTicket[1].phase == "dev"
  and devTicket[1].endAt == nil and devTicket[2].phase == "review" and devTicket[2].endAt == 200)
local named = derive("named.json", "dev", { { 100, "skill", "my-developer", "review" } })
check("passes from old facts: a skill's phase from its name, not the line's", #named == 1 and named[1].phase == "dev")
-- A lane started before the timeline in the phase the timeline starts with is one step, from its earlier start.
local joined = facts.load(file("joined.json", [[{"tickets": {"ABC-12": {"phase": "dev", "phases": {"dev": 50}}}, "timeline": [
  {"at": 100, "ticket": "ABC-12", "kind": "subagent", "text": "Implement ABC-12", "phase": "dev"}]}]]))
local jps = joined and joined.tickets["ABC-12"].passes or {}
check("passes from old facts: a lane before the timeline joins the same phase after it", #jps == 1 and jps[1].at == 50
  and jps[1].endAt == nil and jps[1].by == "Implement ABC-12")

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
  and gitOf('{"root": "/r", "base": "' .. string.rep("a", 65) .. '"}') == nil)
check("git: a SHA-256 repo's 64-hex base is fine", (gitOf('{"root": "/r", "base": "' .. string.rep("a1", 32) .. '"}') or {}).base
  == string.rep("a1", 32))
check("git: a short 7-hex base is fine", gitOf('{"root": "/r", "base": "ABCDEF1"}') ~= nil)
check("git: no root, no git", gitOf('{"base": "abcdef1"}') == nil)
check("git: root not a string, no git", gitOf('{"root": 5, "base": "abcdef1"}') == nil)
check("git: not a table, no git", gitOf('"x"') == nil)
local dirty = gitOf('{"root": "/r", "base": "abcdef1", "dirtyAtStart": ["a.js", 3, {"x": 1}, "b.js"]}')
check("git: junk dirty entries dropped alone", dirty and dirty.dirtyAtStart["a.js"] and dirty.dirtyAtStart["b.js"]
  and not dirty.dirtyAtStart[3])
-- prefix: the session folder's place in the repo, where its relative paths start; "" when it is not one.
local function prefixOf(v) local g = gitOf('{"root": "/r", "base": "abcdef1", "prefix": ' .. v .. "}") return g and g.prefix end
check("git: the prefix kept", prefixOf('"packages/web/"') == "packages/web/" and prefixOf('"src/"') == "src/")
check("git: an empty prefix kept", prefixOf('""') == "")
check("git: no prefix, or one not a string, is empty", prefixOf("null") == "" and prefixOf("5") == ""
  and gitOf('{"root": "/r", "base": "abcdef1"}').prefix == "")
for _, junk in ipairs({ '"src"', '"/src/"', '"./src/"', '"src/../"', '"../x/"', '"src//"', '"/"', '"a/./b/"' }) do
  check("git: a prefix no rule can place is empty: " .. junk, prefixOf(junk) == "")
end
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

-- The hook <-> Spoon seam: the facts the Claude Code hook really writes (its fixtures, as tests/harnesses.sh pins
-- them), with @REPO@ and @BASE@ filled in, read back.
local SHA = "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678"
local function fixture(name)
  local h = assert(io.open(root .. "/harnesses/claude/fixtures/" .. name .. ".facts"))
  local text = h:read("a"):gsub("@REPO@", "/work/my-app"):gsub("@BASE@", SHA)
  h:close()
  return facts.load(file(name .. ".json", text))
end
local stop, edit = fixture("actual-stop"), fixture("actual-edit")
check("fixture stop: has git, its root, base and prefix", facts.hasGit(stop) and stop.git.root == "/work/my-app"
  and stop.git.base == SHA and stop.git.prefix == "" and next(stop.git.dirtyAtStart) == nil)
check("fixture stop: one ended turn, nothing in it", stop and #stop.turns == 1 and stop.turns[1].at == 0
  and stop.turns[1].endAt == 0 and #stop.turns[1].files == 0 and #stop.turns[1].commits == 0
  and stop.turns[1].tests.ran == 0 and next(stop.seen) == nil)
check("fixture edit: has git", facts.hasGit(edit) and edit.git.base == SHA)
check("fixture edit: the open turn holds the edited path, seen too", edit and #edit.turns == 1
  and edit.turns[1].endAt == nil and #edit.turns[1].files == 1 and edit.turns[1].files[1] == "src/app.js"
  and edit.seen["src/app.js"] == true)

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

-- A ticket's page (the hooks keep it): only a Jira or Linear https page of that very ticket.
local function page(key, url) local u, kind = facts.ticketUrl(key, url) return tostring(u) .. "|" .. tostring(kind) end
check("ticketUrl: Jira", page("ABC-12", "https://acme.atlassian.net/browse/ABC-12")
  == "https://acme.atlassian.net/browse/ABC-12|Jira")
check("ticketUrl: Linear", page("ABC-12", "https://linear.app/acme/issue/ABC-12") == "https://linear.app/acme/issue/ABC-12|Linear")
for _, bad in ipairs({ "http://acme.atlassian.net/browse/ABC-12", "https://acme.atlassian.net/browse/ABC-123",
  "https://acme.atlassian.net/browse/XYZ-9", "https://linear.app.evil.com/acme/issue/ABC-12",
  "https://acme.atlassian.net/browse/ABC-12 x", 'https://acme.atlassian.net/browse/ABC-12"', "javascript:alert(1)" }) do
  check("ticketUrl: refused " .. bad, page("ABC-12", bad) == "nil|nil")
end
check("ticketUrl: not a string", page("ABC-12", 12) == "nil|nil" and page(nil, "https://linear.app/acme/issue/ABC-12") == "nil|nil")
local withUrl = facts.load(file("url.json", '{"tickets":{"ABC-12":{"url":"https://acme.atlassian.net/browse/ABC-12"},'
  .. '"ABC-34":{"url":"https://evil.example/browse/ABC-12"}},"timeline":[]}'))
check("load: a ticket's page kept", withUrl.tickets["ABC-12"].url == "https://acme.atlassian.net/browse/ABC-12")
check("load: a page of another ticket dropped", withUrl.tickets["ABC-34"].url == nil)

os.execute("rm -rf '" .. dir .. "'")
check.done("facts")
