-- terminals/backfill.lua: finding a Claude session's transcript, and running hook/backfill.sh for a card within
-- config.BACKFILL_SECONDS, its one-line answer handed back once.

local root = arg[0]:match("^(.*)/tests/") or "."
local stub = dofile(root .. "/tests/support/hs_stub.lua")
stub.spoonPath = root .. "/Deskmates.spoon/"
package.path = root .. "/Deskmates.spoon/lib/?.lua;" .. root .. "/Deskmates.spoon/lib/?/init.lua;" .. package.path
local check = dofile(root .. "/tests/support/check.lua")
local backfill = require("puppet.terminals.backfill")
local config = require("puppet.config")

-- find: the first project folder holding <session>.jsonl.
local listing = { "-work-other", "-work-my-app", ".", ".." }
local function dir() local i = 0 return function() i = i + 1 return listing[i] end end
local present = { ["/h/.claude/projects/-work-my-app/s1.jsonl"] = true }
local function exists(path) return present[path] == true end
check("find: the transcript", backfill.find("/h", "s1", dir, exists) == "/h/.claude/projects/-work-my-app/s1.jsonl")
check("find: none", backfill.find("/h", "s2", dir, exists) == nil)
check("find: no projects folder", backfill.find("/h", "s1", function() error("no such folder") end, exists) == nil)
check("find: an id that is no file name", backfill.find("/h", "../s1", dir, exists) == nil)

-- run: /bin/sh <script> <session>; the answer's first line.
local answers = {}
local function run(stdout, code)
  local n = #stub.tasks
  local got = {}
  backfill.run("/x/hook/backfill.sh", "s1", function(status, detail) got[#got + 1] = { status, detail } end)
  local t = stub.tasks[n + 1]
  if stdout then stub.finishTask(n + 1, code or 0, stdout, "") end
  return t, got
end
local t, got = run("ok 2\n")
check("run: the script, for the session", t.path == "/bin/sh" and t.args[1] == "/x/hook/backfill.sh" and t.args[2] == "s1"
  and t.started)
check("run: ok and how many", #got == 1 and got[1][1] == "ok" and got[1][2] == 2)
_, got = run("none\n")
check("run: none", got[1][1] == "none")
_, got = run("error transcript not readable\n", 1)
check("run: an error says why", got[1][1] == "error" and got[1][2] == "transcript not readable")
_, got = run("", 1)
check("run: nothing said", got[1][1] == "error" and got[1][2] == "transcript not readable")
t, got = run(nil)
stub.advance(config.BACKFILL_SECONDS + 0.1)
check("run: too long, stopped", t.terminated and #got == 1 and got[1][1] == "error" and got[1][2] == "transcript took too long")
stub.finishTask(#stub.tasks, 15, "", "")
check("run: answered once", #got == 1)

check.done("backfill task")
