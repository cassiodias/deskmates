-- Reading a session's repo with git for its card: which git runs, the four commands in their order with an env
-- that never takes the agent's index.lock, the raw texts handed back, and the one line said when git cannot
-- answer (base gone, a failure, or 3 seconds passing).

local root = arg[0]:match("^(.*)/tests/") or "."
package.path = root .. "/Deskmates.spoon/lib/?.lua;" .. root .. "/Deskmates.spoon/lib/?/init.lua;" .. package.path
local stub = dofile(root .. "/tests/support/hs_stub.lua")
local check = dofile(root .. "/tests/support/check.lua")
local git = require("puppet.terminals.git")

local function same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

-- Which git: the first of the known paths there is; /usr/bin/git only once the command line tools are in.
local function present(paths)
  local set = {}
  for _, p in ipairs(paths) do set[p] = true end
  return function(p) return set[p] == true end
end
check("find: Homebrew's git first", git.find(present({ "/opt/homebrew/bin/git", "/usr/bin/git" })) == "/opt/homebrew/bin/git")
check("find: then /usr/local", git.find(present({ "/usr/local/bin/git", "/usr/bin/git" })) == "/usr/local/bin/git")
check("find: /usr/bin/git alone is the tools' stub, no git", git.find(present({ "/usr/bin/git" })) == nil)
check("find: /usr/bin/git with the command line tools",
  git.find(present({ "/usr/bin/git", "/Library/Developer/CommandLineTools/usr/bin/git" })) == "/usr/bin/git")
check("find: /usr/bin/git with Xcode", git.find(present({ "/usr/bin/git", "/Applications/Xcode.app" })) == "/usr/bin/git")
check("find: nothing there", git.find(present({})) == nil)

-- The real read finds git through hs.fs.attributes; here only Homebrew's git is there.
hs.fs.attributes = function(p) if p == "/opt/homebrew/bin/git" then return { mode = "file" } end end

local BASE = "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678"
local calls
local function start()
  stub.tasks = {}
  calls = {}
  git.read("/build/my-app", BASE, function(result, err) calls[#calls + 1] = { result = result, err = err } end)
end

-- Success: four commands, one after another, each started only once the one before finished.
start()
check("one command at a time", #stub.tasks == 1)
stub.finishTask(1, 0, "3\n", "")
check("the second starts after the first", #stub.tasks == 2)
stub.finishTask(2, 0, "M\0src/app.js\0", "")
stub.finishTask(3, 0, "src/app.js\0", "")
stub.finishTask(4, 0, "docs/notes.md\0", "")
check("four commands in all", #stub.tasks == 4)
for i, task in ipairs(stub.tasks) do check("command " .. i .. " runs Homebrew's git", task.path == "/opt/homebrew/bin/git") end
check("1: commits since the base", same((stub.tasks[1] or {}).args, { "-C", "/build/my-app", "rev-list", "--count", BASE .. "..HEAD" }))
check("2: the diff from the base", same((stub.tasks[2] or {}).args,
  { "-C", "/build/my-app", "diff", "--name-status", "-M", "-z", BASE, "--" }))
check("3: what is not committed", same((stub.tasks[3] or {}).args, { "-C", "/build/my-app", "diff", "--name-only", "-z", "HEAD", "--" }))
check("4: what git does not track", same((stub.tasks[4] or {}).args,
  { "-C", "/build/my-app", "ls-files", "--others", "--exclude-standard", "-z" }))
for i, task in ipairs(stub.tasks) do
  check("command " .. i .. " never takes the index lock", task.env.GIT_OPTIONAL_LOCKS == "0")
  check("command " .. i .. " has git's folder first on PATH (for git-lfs and helpers beside it), then PATH, and HOME",
    task.env.PATH == "/opt/homebrew/bin:" .. os.getenv("PATH") and task.env.HOME == os.getenv("HOME"))
end
check("done once", #calls == 1)
check("done with the raw texts", calls[1] and same(calls[1].result,
  { commits = 3, diff = "M\0src/app.js\0", uncommitted = "src/app.js\0", untracked = "docs/notes.md\0" }) and calls[1].err == nil)
stub.advance(5)
check("the budget's timer says nothing after done", #calls == 1)

-- The base is gone (history rewritten): said with the short base.
for _, stderr in ipairs({
  "fatal: bad revision 'a1b2c3d4e5f60718293a4b5c6d7e8f9012345678..HEAD'\n",
  "fatal: ambiguous argument 'x..HEAD': unknown revision or path not in the working tree.\n",
  "fatal: Invalid revision range a1b2c3d4e5f60718293a4b5c6d7e8f9012345678..HEAD\n",
}) do
  start()
  stub.finishTask(1, 128, "", stderr)
  local name = "base gone: " .. stderr:gsub("\n$", "")
  check(name, #calls == 1 and calls[1].result == nil and calls[1].err == "base a1b2c3d no longer exists")
  check(name .. ", nothing more runs", #stub.tasks == 1)
end

-- Any other failure, at any step: git did not answer.
start()
stub.finishTask(1, 128, "", "fatal: not a git repository (or any of the parent directories): .git\n")
check("not a repo: did not answer", #calls == 1 and calls[1].result == nil and calls[1].err == "git did not answer")
start()
stub.finishTask(1, 0, "3\n", "")
stub.finishTask(2, 0, "", "")
stub.finishTask(3, 1, "", "error: something\n")
check("a later step failing: did not answer", #calls == 1 and calls[1].err == "git did not answer" and #stub.tasks == 3)
start()
stub.finishTask(1, 0, "", "")
check("no count: did not answer", #calls == 1 and calls[1].err == "git did not answer")

-- 3 seconds pass: the running command is stopped, said once, and its late finish calls nothing.
start()
stub.finishTask(1, 0, "3\n", "")
stub.advance(2.9)
check("not before 3 s", #calls == 0)
stub.advance(0.2)
check("3 s: did not answer", #calls == 1 and calls[1].err == "git did not answer")
check("3 s: the running command is stopped", stub.tasks[2] ~= nil and stub.tasks[2].terminated)
stub.finishTask(2, 15, "", "")
check("a late finish calls nothing and starts nothing", #calls == 1 and #stub.tasks == 2)

-- No git at all.
hs.fs.attributes = function() return nil end
start()
check("no git: did not answer, nothing run", #calls == 1 and calls[1].err == "git did not answer" and #stub.tasks == 0)
stub.advance(5)
check("no git: said once", #calls == 1)

check.done("git")
