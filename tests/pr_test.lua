-- Reading the PR of a session's branch with gh for its card: which gh runs, the one command in the repo, the one
-- line it says (number, state, checks), and nothing at all when there is no PR, no gh, an error or no answer.

local root = arg[0]:match("^(.*)/tests/") or "."
package.path = root .. "/Deskmates.spoon/lib/?.lua;" .. root .. "/Deskmates.spoon/lib/?/init.lua;" .. package.path
local stub = dofile(root .. "/tests/support/hs_stub.lua")
local check = dofile(root .. "/tests/support/check.lua")
local pr = require("puppet.terminals.pr")

local function present(paths)
  local set = {}
  for _, p in ipairs(paths) do set[p] = true end
  return function(p) return set[p] == true end
end
check("find: Homebrew's gh first", pr.find(present({ "/opt/homebrew/bin/gh", "/usr/local/bin/gh" })) == "/opt/homebrew/bin/gh")
check("find: then /usr/local", pr.find(present({ "/usr/local/bin/gh" })) == "/usr/local/bin/gh")
check("find: none", pr.find(present({})) == nil)

local function lineOf(json)
  local p = pr.parse(json)
  return p and pr.line(p)
end
local MERGED = '{"number":5,"state":"MERGED","isDraft":false,"url":"https://github.com/me/my-app/pull/5",'
  .. '"statusCheckRollup":[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"}]}'
check("the PR's page", pr.parse(MERGED).url == "https://github.com/me/my-app/pull/5")
check("a page that is not https is not kept", pr.parse('{"number":5,"state":"OPEN","url":"file:///etc/passwd"}').url == nil
  and pr.parse('{"number":5,"state":"OPEN","url":"javascript:alert(1)"}').url == nil)
check("no page: none", pr.parse('{"number":5,"state":"OPEN"}').url == nil)
check("merged, checks passed", lineOf(MERGED) == "PR #5 · merged · checks passed")
check("one check failing", lineOf('{"number":7,"state":"OPEN","isDraft":false,"statusCheckRollup":['
  .. '{"__typename":"CheckRun","status":"COMPLETED","conclusion":"FAILURE"},'
  .. '{"__typename":"StatusContext","state":"SUCCESS"}]}') == "PR #7 · open · 1 check failing")
check("two checks failing", lineOf('{"number":7,"state":"OPEN","isDraft":false,"statusCheckRollup":['
  .. '{"__typename":"CheckRun","status":"COMPLETED","conclusion":"TIMED_OUT"},'
  .. '{"__typename":"StatusContext","state":"ERROR"}]}') == "PR #7 · open · 2 checks failing")
for _, failing in ipairs({ "FAILURE", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE" }) do
  check("failing conclusion " .. failing, lineOf('{"number":7,"state":"OPEN","isDraft":false,"statusCheckRollup":['
    .. '{"__typename":"CheckRun","status":"COMPLETED","conclusion":"' .. failing .. '"}]}') == "PR #7 · open · 1 check failing")
end
check("a check still running", lineOf('{"number":7,"state":"OPEN","isDraft":false,"statusCheckRollup":['
  .. '{"__typename":"CheckRun","status":"IN_PROGRESS","conclusion":""},'
  .. '{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"}]}') == "PR #7 · open · checks running")
check("a status pending", lineOf('{"number":7,"state":"OPEN","isDraft":false,"statusCheckRollup":['
  .. '{"__typename":"StatusContext","state":"PENDING"}]}') == "PR #7 · open · checks running")
check("a status expected", lineOf('{"number":7,"state":"OPEN","isDraft":false,"statusCheckRollup":['
  .. '{"__typename":"StatusContext","state":"EXPECTED"}]}') == "PR #7 · open · checks running")
check("failing wins over running", lineOf('{"number":7,"state":"OPEN","isDraft":false,"statusCheckRollup":['
  .. '{"__typename":"CheckRun","status":"QUEUED"},'
  .. '{"__typename":"CheckRun","status":"COMPLETED","conclusion":"FAILURE"}]}') == "PR #7 · open · 1 check failing")
check("skipped and neutral pass", lineOf('{"number":7,"state":"OPEN","isDraft":false,"statusCheckRollup":['
  .. '{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SKIPPED"},'
  .. '{"__typename":"CheckRun","status":"COMPLETED","conclusion":"NEUTRAL"}]}') == "PR #7 · open · checks passed")
check("a draft, no checks", lineOf('{"number":8,"state":"OPEN","isDraft":true,"statusCheckRollup":[]}') == "PR #8 · draft")
check("closed", lineOf('{"number":9,"state":"CLOSED","isDraft":false,"statusCheckRollup":[]}') == "PR #9 · closed")
check("no rollup at all", lineOf('{"number":9,"state":"OPEN","isDraft":false}') == "PR #9 · open")
for _, junk in ipairs({ "", "junk", "[]", '{"state":"OPEN"}', '{"number":"5","state":"OPEN"}', '{"number":5,"state":"WEIRD"}' }) do
  check("junk: " .. junk, pr.parse(junk) == nil)
end
check("no text", pr.parse(nil) == nil)

-- The read: one gh command in the repo, its answer as the line.
hs.fs.attributes = function(p) if p == "/opt/homebrew/bin/gh" then return { mode = "file" } end end
local calls
local function start()
  stub.tasks = {}
  calls = {}
  pr.read("/build/my-app", function(line, url) calls[#calls + 1] = { line = line, url = url } end)
end
start()
local t = stub.tasks[1]
check("one command", #stub.tasks == 1 and t.started)
check("Homebrew's gh", t and t.path == "/opt/homebrew/bin/gh")
local args = t and table.concat(t.args, " ")
check("pr view with the fields", args == "pr view --json number,state,isDraft,url,statusCheckRollup")
check("run in the repo", t and t.cwd == "/build/my-app")
check("env: gh's folder first on PATH, HOME, no prompt, no colour", t and t.env
  and t.env.PATH == "/opt/homebrew/bin:" .. os.getenv("PATH") and t.env.HOME == os.getenv("HOME")
  and t.env.GH_PROMPT_DISABLED == "1" and t.env.NO_COLOR == "1")
stub.finishTask(1, 0, MERGED, "")
check("the line and its page, once", #calls == 1 and calls[1].line == "PR #5 · merged · checks passed"
  and calls[1].url == "https://github.com/me/my-app/pull/5")
stub.advance(20)
check("the time limit says nothing after done", #calls == 1)

start()
stub.finishTask(1, 1, "", 'no pull requests found for branch "main"\n')
check("no PR: nothing", #calls == 1 and calls[1].line == nil)
start()
stub.finishTask(1, 0, "not json", "")
check("junk answer: nothing", #calls == 1 and calls[1].line == nil)

start()
stub.advance(9.9)
check("not before 10 s", #calls == 0)
stub.advance(0.2)
check("10 s: nothing, once", #calls == 1 and calls[1].line == nil)
check("10 s: gh is stopped", stub.tasks[1].terminated)
stub.finishTask(1, 0, MERGED, "")
check("a late answer calls nothing", #calls == 1)

hs.fs.attributes = function() return nil end
start()
check("no gh: nothing at once, nothing run", #calls == 1 and calls[1].line == nil and #stub.tasks == 0)

check.done("pr")
