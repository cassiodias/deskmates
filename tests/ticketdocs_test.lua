-- Finding a ticket's documents for its card: the key a branch names, the one search for the ticket's folder beside
-- the repo (its command, its hits, its time limit), and which document each step wrote.

local root = arg[0]:match("^(.*)/tests/") or "."
package.path = root .. "/Deskmates.spoon/lib/?.lua;" .. root .. "/Deskmates.spoon/lib/?/init.lua;" .. package.path
local stub = dofile(root .. "/tests/support/hs_stub.lua")
local check = dofile(root .. "/tests/support/check.lua")
local ticketdocs = require("puppet.terminals.ticketdocs")

local work = os.tmpname()
os.remove(work)
os.execute("mkdir -p '" .. work .. "'")
local function sh(cmd) os.execute(cmd) end
local function write(path, text)
  local f = io.open(path, "w")
  f:write(text)
  f:close()
end

-- The key a branch names: from .git/HEAD, or the HEAD of the worktree .git points to.
local function repoOn(name, head)
  local repo = work .. "/" .. name
  sh("mkdir -p '" .. repo .. "/.git'")
  write(repo .. "/.git/HEAD", head)
  return repo
end
check("branch: its key", ticketdocs.branchKey(repoOn("r1", "ref: refs/heads/ABC-12-export-limit\n")) == "ABC-12")
check("branch: lower case is no key", ticketdocs.branchKey(repoOn("r2", "ref: refs/heads/feature/abc-12\n")) == nil)
check("branch: a word that only looks like one", ticketdocs.branchKey(repoOn("r3", "ref: refs/heads/UTF-8-fix\n")) == nil)
check("branch: detached", ticketdocs.branchKey(repoOn("r4", "0123456789abcdef0123456789abcdef01234567\n")) == nil)
check("branch: inside a word", ticketdocs.branchKey(repoOn("r5", "ref: refs/heads/xABC-12\n")) == nil)
sh("mkdir -p '" .. work .. "/main/.git/worktrees/wt'")
write(work .. "/main/.git/worktrees/wt/HEAD", "ref: refs/heads/feature/ABC-34-docs\n")
sh("mkdir -p '" .. work .. "/wt'")
write(work .. "/wt/.git", "gitdir: " .. work .. "/main/.git/worktrees/wt\n")
check("branch: a worktree's", ticketdocs.branchKey(work .. "/wt") == "ABC-34")
sh("mkdir -p '" .. work .. "/plain'")
check("branch: no .git", ticketdocs.branchKey(work .. "/plain") == nil)

-- The search: one find under the repo's parent, links followed, .git, node_modules and hidden folders skipped.
local calls
local function start(repo, keys)
  stub.tasks, calls = {}, {}
  ticketdocs.find(repo, keys, function(found) calls[#calls + 1] = found end)
end
local parent = work .. "/wrap"
sh("mkdir -p '" .. parent .. "/my-app' '" .. parent .. "/z-kb/contracts/ABC-12' '" .. parent .. "/old/ABC-34'")
sh("ln -s z-kb/contracts '" .. parent .. "/contracts'")
start(parent .. "/my-app", { "ABC-12", "ABC-34" })
local t = stub.tasks[1]
check("one find", #stub.tasks == 1 and t.started and t.path == "/usr/bin/find")
check("its arguments", t and table.concat(t.args, " ") == "-L " .. parent .. " -mindepth 1 -maxdepth 3 ( -name .git -o "
  .. "-name node_modules -o -name .* ) -prune -o -type d ( -name ABC-12 -o -name ABC-34 ) -print")
stub.finishTask(1, 1, parent .. "/z-kb/contracts/ABC-12\n" .. parent .. "/contracts/ABC-12\n" .. parent
  .. "/old/ABC-34\n" .. parent .. "/z-kb/ABC-120\n", "find: loop detected\n")
check("hits even when find says no (a loop)", #calls == 1 and calls[1]["ABC-12"] ~= nil and calls[1]["ABC-34"] ~= nil)
check("one folder per ticket, the link and its target one", calls[1]["ABC-12"]
  == hs.fs.pathToAbsolute(parent .. "/z-kb/contracts/ABC-12"))
check("only exact names", calls[1]["ABC-120"] == nil)
stub.advance(5)
check("the time limit says nothing after done", #calls == 1)

start(parent .. "/my-app", { "ABC-12" })
stub.finishTask(1, 0, "", "")
check("no hits: empty", #calls == 1 and next(calls[1]) == nil)

start(parent .. "/my-app", { "ABC-12" })
stub.advance(1.9)
check("not before 2 s", #calls == 0)
stub.advance(0.2)
check("2 s: empty, once, find stopped", #calls == 1 and next(calls[1]) == nil and stub.tasks[1].terminated)
stub.finishTask(1, 0, parent .. "/z-kb/contracts/ABC-12\n", "")
check("a late answer calls nothing", #calls == 1)

start(os.getenv("HOME") .. "/my-app", { "ABC-12" })
check("the home folder is never searched", #stub.tasks == 0 and #calls == 1 and next(calls[1]) == nil)
start("/my-app", { "ABC-12" })
check("nor /", #stub.tasks == 0 and #calls == 1 and next(calls[1]) == nil)
start(parent .. "/my-app", {})
check("no keys: no search", #stub.tasks == 0 and #calls == 1 and next(calls[1]) == nil)
start(parent .. "/my-app", { "-", "abc; rm" })
check("only real keys are searched for", #stub.tasks == 0 and #calls == 1)

-- Two different folders for one ticket: the one changed last.
sh("mkdir -p '" .. work .. "/a/ABC-12' '" .. work .. "/b/ABC-12'")
sh("touch -t 202611080900.00 '" .. work .. "/a/ABC-12'")
sh("touch -t 202611081000.00 '" .. work .. "/b/ABC-12'")
check("pick: the newer", ticketdocs.pick({ work .. "/a/ABC-12", work .. "/b/ABC-12" })
  == hs.fs.pathToAbsolute(work .. "/b/ABC-12"))

-- A step's document: changed during the step, else named for it.
local folder = parent .. "/z-kb/contracts/ABC-12"
-- 8 Nov at hh:mm, local time, in seconds (the stub fixes os.time, so date says it).
local function at(hh, mm)
  local p = io.popen(string.format("date -j -f %%Y%%m%%d%%H%%M%%S 20261108%02d%02d00 +%%s", hh, mm))
  local out = tonumber(p:read("a"))
  p:close()
  return out
end
local function made(name, hh, mm)
  write(folder .. "/" .. name, "# " .. name .. "\n")
  sh(string.format("touch -t 20261108%02d%02d.00 '%s/%s'", hh, mm, folder, name))
end
made("contract.md", 12, 20)
made("review.md", 12, 37)
made("implementation-log.md", 13, 30)
made("notes.txt", 12, 25)
sh("mkdir -p '" .. folder .. "/sub.md'")
local files = ticketdocs.files(folder)
local names = {}
for _, f in ipairs(files) do names[#names + 1] = f.name end
table.sort(names)
check("files: the .md files only", table.concat(names, ",") == "contract.md,implementation-log.md,review.md")
check("files: each with its path and time", files[1].path == folder .. "/" .. files[1].name and files[1].modified ~= nil)
local function doc(phase, a, b, now)
  local p = ticketdocs.docFor({ phase = phase, at = a, endAt = b }, files, now or at(15, 0))
  return p and p:match("[^/]+$")
end
check("plan: the file changed in its window", doc("plan", at(12, 0), at(12, 30)) == "contract.md")
check("review: its window", doc("review", at(12, 30), at(12, 40)) == "review.md")
check("dev: its window", doc("dev", at(12, 40), at(13, 35)) == "implementation-log.md")
check("two in the window: the name that fits", doc("review", at(12, 0), at(12, 40)) == "review.md")
check("two in the window, none fits: the newer", doc("dev", at(12, 0), at(12, 40)) == "review.md")
check("nothing in the window: the name that fits", doc("dev", at(14, 0), at(14, 30)) == "implementation-log.md")
check("an open step runs to now", doc("dev", at(13, 0), nil, at(13, 40)) == "implementation-log.md")
made("design.md", 9, 0)
files = ticketdocs.files(folder)
check("nothing in the window, two plan names: the newer", doc("plan", at(8, 0), at(8, 30)) == "contract.md")
os.remove(folder .. "/contract.md")
os.remove(folder .. "/design.md")
files = ticketdocs.files(folder)
check("no file in the window, none named for it: none", doc("plan", at(8, 0), at(8, 30)) == nil)

os.execute("rm -rf '" .. work .. "'")
check.done("ticket docs")
