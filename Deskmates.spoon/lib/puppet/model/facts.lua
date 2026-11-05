-- A session's facts, as the hooks write them (hook/facts-lib.sh): one file per session,
--   { "current": "ABC-12", "tickets": { "ABC-12": { "phase", "phaseAt", "phases", "ends", "jira", "seen" } },
--     "timeline": [ { "at", "ticket", "kind", "text", "phase" } ], "updatedAt": …,
--     "git": { "root", "base", "prefix", "dirtyAtStart": [ path ] }, "seen": { path: true },
--     "turns": [ { "at", "endAt", "files": [ path ], "tests": { "ran", "passed", "failed" },
--                  "commits": [ { "hash", "subject" } ] } ] }
-- read here with every field checked: a bad field, ticket or entry is dropped on its own; a file that is not
-- facts is nil. It knows no agent, and no Hammerspoon.

local plans = require("puppet.model.plans")

local facts = {}

local PHASES = { "plan", "dev", "review" }
local IS_PHASE = { plan = true, dev = true, review = true }

local function num(v) return type(v) == "number" and v or nil end
local function str(v) return type(v) == "string" and v or nil end

-- Whether `v` is a git commit name: 7 to 40 hex digits.
local function isHash(v) return type(v) == "string" and #v >= 7 and #v <= 40 and v:match("^%x+$") ~= nil end

-- The strings in list `v`, in order, junk dropped; empty for anything but a list.
local function strings(v)
  local out = {}
  for _, s in ipairs(type(v) == "table" and v or {}) do
    if type(s) == "string" then out[#out + 1] = s end
  end
  return out
end

-- The paths in list `v` as a set { [path] = true }.
local function pathSet(v)
  local out = {}
  for _, p in ipairs(strings(v)) do out[p] = true end
  return out
end

-- The facts file of a session in folder `dir`; nil for an id that could name a path outside it.
facts.path = plans.path

local function ticket(t)
  if type(t) ~= "table" then return nil end
  local out = { phase = IS_PHASE[t.phase] and t.phase or nil, phaseAt = num(t.phaseAt), seen = num(t.seen) or 0,
    phases = {} }
  if type(t.phases) == "table" then
    for _, p in ipairs(PHASES) do out.phases[p] = num(t.phases[p]) end
  end
  if type(t.ends) == "table" then
    for _, p in ipairs(PHASES) do
      local e = t.ends[p]
      if type(e) == "table" and num(e.at) then
        out.ends = out.ends or {}
        out.ends[p] = { at = e.at, outcome = str(e.outcome), verdict = str(e.verdict) }
      end
    end
  end
  if type(t.jira) == "table" and str(t.jira.status) then
    out.jira = { status = t.jira.status, at = num(t.jira.at) }
  end
  return out
end

-- The session folder's place in the repo, as git's `--show-prefix` gives it ("src/", "packages/web/"): `v` when it
-- is "" or segments each ending in "/", none of them empty, "." or ".."; else "" (the root).
local function prefix(v)
  if type(v) ~= "string" or v:sub(-1) ~= "/" then return "" end
  for segment in v:gmatch("([^/]*)/") do
    if segment == "" or segment == "." or segment == ".." then return "" end
  end
  return v
end

-- The git block, checked: { root, base, prefix, dirtyAtStart = set }; nil unless root and base are right.
local function git(g)
  if type(g) ~= "table" or not str(g.root) or not isHash(g.base) then return nil end
  return { root = g.root, base = g.base, prefix = prefix(g.prefix), dirtyAtStart = pathSet(g.dirtyAtStart) }
end

-- The `seen` paths as a set; only an entry that is `true` counts.
local function seen(s)
  local out = {}
  if type(s) == "table" then
    for path, v in pairs(s) do
      if type(path) == "string" and v == true then out[path] = true end
    end
  end
  return out
end

-- A turn's test counts; each count that is not a number is 0.
local function tests(t)
  t = type(t) == "table" and t or {}
  return { ran = num(t.ran) or 0, passed = num(t.passed) or 0, failed = num(t.failed) or 0 }
end

-- A turn's commits, those with a hash and a subject, in order.
local function commits(list)
  local out = {}
  for _, c in ipairs(type(list) == "table" and list or {}) do
    if type(c) == "table" and str(c.hash) and str(c.subject) then
      out[#out + 1] = { hash = c.hash, subject = c.subject }
    end
  end
  return out
end

-- A turn, checked; nil without a start time.
local function turn(t)
  if type(t) ~= "table" or not num(t.at) then return nil end
  return { at = t.at, endAt = num(t.endAt), files = strings(t.files), tests = tests(t.tests),
    commits = commits(t.commits) }
end

-- The facts in file `path`, checked; nil when it is missing, broken or not facts.
function facts.load(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local data = plans.decode(file:read("a"))
  file:close()
  if type(data) ~= "table" then return nil end
  local g = git(data.git)
  if type(data.tickets) ~= "table" and not g then return nil end
  local f = { tickets = {}, timeline = {}, updatedAt = num(data.updatedAt), git = g, seen = seen(data.seen),
    turns = {} }
  for _, t in ipairs(type(data.turns) == "table" and data.turns or {}) do
    f.turns[#f.turns + 1] = turn(t)
  end
  for key, t in pairs(type(data.tickets) == "table" and data.tickets or {}) do
    if type(key) == "string" then f.tickets[key] = ticket(t) end
  end
  if str(data.current) and f.tickets[data.current] then f.current = data.current end
  for _, e in ipairs(type(data.timeline) == "table" and data.timeline or {}) do
    if type(e) == "table" and num(e.at) and str(e.ticket) and str(e.kind) and str(e.text) then
      f.timeline[#f.timeline + 1] = { at = e.at, ticket = e.ticket, kind = e.kind, text = e.text,
        phase = IS_PHASE[e.phase] and e.phase or nil }
    end
  end
  return f
end

-- Whether facts have anything to show: a ticket (or a phase waiting for one).
function facts.hasContent(f)
  return f ~= nil and next(f.tickets) ~= nil
end

-- Whether facts know the session's git base.
function facts.hasGit(f)
  return f ~= nil and f.git ~= nil
end

-- Deletes the facts in `dir` no session needs: not in `keep` and last changed more than `maxAge` seconds
-- before `now`, or broken.
function facts.sweep(dir, keep, now, maxAge)
  local pipe = io.popen("ls -1 '" .. dir:gsub("'", "'\\''") .. "' 2>/dev/null")
  if not pipe then return end
  local names = {}
  for name in pipe:lines() do names[#names + 1] = name end
  pipe:close()
  for _, name in ipairs(names) do
    local session = name:match("^(.+)%.json$")
    if session and not keep[session] then
      local f = facts.load(dir .. "/" .. name)
      if not f or (f.updatedAt or 0) < now - maxAge then os.remove(dir .. "/" .. name) end
    end
  end
end

return facts
