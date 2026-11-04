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
