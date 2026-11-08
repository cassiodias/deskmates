-- Finds a ticket's documents for its card: the folder named after the ticket beside the session's repo (in the
-- folder that holds the repo, config.DOCS_DEPTH levels at most), searched with one `find` off the main thread
-- within config.DOCS_SECONDS, and in it the document each step wrote: the .md file changed during the step, else
-- the one named for it. No ticket, no folder or no answer in time all say nothing: the card then shows no gist.

local config = require("puppet.config")

local ticketdocs = {}

-- Words that only look like a ticket key (as `tickets` in hook/facts-lib.sh).
local NOT_KEYS = { UTF = true, SHA = true, ISO = true, RFC = true, CVE = true, HTTP = true, TLS = true, AES = true,
  RSA = true, MD = true }

-- The first ticket key in `text` (a whole word: ABC-12), as the hooks find them; nil when it names none.
local function keyIn(text)
  for s, project, number, e in text:gmatch("()(%u[%u%d]*)%-(%d+)()") do
    local before, after = text:sub(s - 1, s - 1), text:sub(e, e)
    if not before:match("%w") and not after:match("%w") and #project >= 2 and #project <= 10
      and not NOT_KEYS[project] then
      return project .. "-" .. number
    end
  end
  return nil
end

-- Whether `key` is a ticket key and nothing more (so it is safe to hand to find as a name).
local function isKey(key)
  return type(key) == "string" and keyIn(key) == key
end

local function readAll(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local text = file:read("a")
  file:close()
  return text
end

-- The ticket key the branch checked out at `root` names (ABC-12-export-limit gives ABC-12), read from its
-- .git/HEAD, or from the HEAD of the worktree a .git file points to; nil for a detached HEAD or a branch naming
-- none.
function ticketdocs.branchKey(root)
  local dotgit = root .. "/.git"
  local mode = hs.fs.attributes(dotgit, "mode")
  local head
  if mode == "directory" then
    head = readAll(dotgit .. "/HEAD")
  elseif mode then
    local gitdir = (readAll(dotgit) or ""):match("^gitdir:%s*(.-)%s*$")
    if gitdir and gitdir ~= "" then
      if gitdir:sub(1, 1) ~= "/" then gitdir = root .. "/" .. gitdir end
      head = readAll(gitdir .. "/HEAD")
    end
  end
  local branch = head and head:match("^ref:%s*refs/heads/(%S+)")
  return branch and keyIn(branch) or nil
end

-- Of folders `paths` (one ticket's hits), the one changed last; hits that are the same folder (a link and its
-- target) count once. nil for none.
function ticketdocs.pick(paths)
  local best, bestAt
  for _, p in ipairs(paths) do
    local real = hs.fs.pathToAbsolute(p) or p
    local at = hs.fs.attributes(real, "modification") or 0
    if not best or at > bestAt then best, bestAt = real, at end
  end
  return best
end

-- Searches the folder holding the repo at `root` for folders named exactly one of `keys`. Calls done exactly
-- once: done({ [key] = folder }), empty when nothing is found, no key is a ticket key, the repo's parent is the
-- home folder or /, or config.DOCS_SECONDS pass (find is then stopped). A link loop makes find fail, but what it
-- found is still used.
function ticketdocs.find(root, keys, done)
  local parent = type(root) == "string" and root:gsub("/+$", ""):match("^(.*)/[^/]+$")
  local names = {}
  for _, k in ipairs(keys or {}) do
    if isKey(k) then names[#names + 1] = k end
  end
  if not parent or parent == "" or parent == os.getenv("HOME") or #names == 0 then return done({}) end

  local finished, task, timer = false, nil, nil
  local function finish(found)
    if finished then return end
    finished = true
    if timer then timer:stop() end
    done(found)
  end

  local args = { "-L", parent, "-mindepth", "1", "-maxdepth", tostring(config.DOCS_DEPTH), "(", "-name", ".git", "-o",
    "-name", "node_modules", "-o", "-name", ".*", ")", "-prune", "-o", "-type", "d", "(" }
  for i, k in ipairs(names) do
    if i > 1 then args[#args + 1] = "-o" end
    args[#args + 1] = "-name"
    args[#args + 1] = k
  end
  args[#args + 1] = ")"
  args[#args + 1] = "-print"
  task = hs.task.new("/usr/bin/find", function(_, stdout)
    if finished then return end
    local hits = {}
    for line in (stdout or ""):gmatch("[^\n]+") do
      local name = line:match("[^/]+$")
      for _, k in ipairs(names) do
        if name == k then
          hits[k] = hits[k] or {}
          hits[k][#hits[k] + 1] = line
        end
      end
    end
    local found = {}
    for k, paths in pairs(hits) do found[k] = ticketdocs.pick(paths) end
    finish(found)
  end, args)
  if not task then return finish({}) end
  timer = hs.timer.doAfter(config.DOCS_SECONDS, function()
    if finished then return end
    if task:isRunning() then task:terminate() end
    finish({})
  end)
  if not task:start() then finish({}) end
end

-- The .md files directly in `folder`, each { name, path, modified }; none for a folder that is not there.
function ticketdocs.files(folder)
  local out = {}
  local ok, iter, dir = pcall(hs.fs.dir, folder)
  if not ok or not iter then return out end
  for name in iter, dir do
    if name:sub(1, 1) ~= "." and name:lower():match("%.md$") then
      local path = folder .. "/" .. name
      local a = hs.fs.attributes(path)
      if a and a.mode == "file" then out[#out + 1] = { name = name, path = path, modified = a.modification or 0 } end
    end
  end
  return out
end

-- The names a step's own document starts with.
local NAMED = { plan = { "contract", "plan", "design", "spec" }, dev = { "implement", "log" }, review = { "review" } }

local function fits(phase, name)
  local lower = name:lower()
  for _, start in ipairs(NAMED[phase] or {}) do
    if lower:sub(1, #start) == start then return true end
  end
  return false
end

-- The newest of `files` (only those named for `phase` when `onlyNamed`); nil for none.
local function newest(files, phase, onlyNamed)
  local best
  for _, f in ipairs(files) do
    if (not onlyNamed or fits(phase, f.name)) and (not best or f.modified > best.modified) then best = f end
  end
  return best
end

-- The document step `pass` ({ phase, at, endAt }; no endAt: still running at `now`) wrote, of `files`
-- (ticketdocs.files): a file changed during it (the one named for the step first, else the newest), else the
-- newest named for it; its path, or nil.
function ticketdocs.docFor(pass, files, now)
  local last = pass.endAt or now
  local during = {}
  for _, f in ipairs(files) do
    if f.modified >= pass.at and f.modified <= last then during[#during + 1] = f end
  end
  local f = newest(during, pass.phase, true) or newest(during, pass.phase, false) or newest(files, pass.phase, true)
  return f and f.path or nil
end

return ticketdocs
