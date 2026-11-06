-- A session's facts, as the hooks write them (hook/facts-lib.sh): one file per session,
--   { "current": "ABC-12", "tickets": { "ABC-12": { "phase", "phaseAt", "phases", "ends", "jira", "seen",
--                                                   "passes": [ { "phase", "at", "endAt", "by", "verdict" } ] } },
--     "timeline": [ { "at", "ticket", "kind", "text", "phase" } ], "updatedAt": …,
--     "git": { "root", "base", "prefix", "dirtyAtStart": [ path ] }, "seen": { path: true },
--     "turns": [ { "at", "endAt", "files": [ path ], "tests": { "ran", "passed", "failed" },
--                  "commits": [ { "hash", "subject" } ] } ] }
-- read here with every field checked: a bad field, ticket or entry is dropped on its own; a file that is not
-- facts is nil. A ticket's passes (its steps, oldest first) are worked out when the file has none (written before
-- passes were kept): from its timeline lines, by the hooks' rules, and before the oldest line from its lanes' starts.
-- It knows no agent, and no Hammerspoon.

local plans = require("puppet.model.plans")

local facts = {}

local PHASES = { "plan", "dev", "review" }
local IS_PHASE = { plan = true, dev = true, review = true }

local function num(v) return type(v) == "number" and v or nil end
local function str(v) return type(v) == "string" and v or nil end

-- Whether `v` is a git commit name: 7 to 64 hex digits (40 in a SHA-1 repo, 64 in a SHA-256 one).
local function isHash(v) return type(v) == "string" and #v >= 7 and #v <= 64 and v:match("^%x+$") ~= nil end

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

-- Sorts list `out` by start (at); entries that start in the same second keep the order they were made in.
local function byStart(out)
  for i, p in ipairs(out) do p.n = i end
  table.sort(out, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.n < b.n end)
  for _, p in ipairs(out) do p.n = nil end
  return out
end

-- The steps in the order they happened, checked: each pass with a phase and a start, its end, what started it
-- and its verdict when they are right; junk dropped alone. Sorted by start.
local function passes(list)
  local out = {}
  for _, p in ipairs(type(list) == "table" and list or {}) do
    if type(p) == "table" and IS_PHASE[p.phase] and num(p.at) then
      out[#out + 1] = { phase = p.phase, at = p.at, endAt = num(p.endAt), by = str(p.by), verdict = str(p.verdict) }
    end
  end
  return byStart(out)
end

-- The steps of facts written before passes, from ticket `t`'s lanes (checked): one per lane started, by its
-- start; its end and verdict from the lane's end when that is not before the start.
local function lanePasses(t)
  local out = {}
  for _, p in ipairs(PHASES) do
    local at = t.phases[p]
    if at then
      local e = t.ends and t.ends[p]
      local ended = e and e.at >= at
      out[#out + 1] = { phase = p, at = at, endAt = ended and e.at or nil, verdict = ended and e.verdict or nil }
    end
  end
  return byStart(out)
end

-- The words that name each phase, by the hooks' rules (hook/facts-lib.sh, phase): Review's win, then Dev's.
local PHASE_WORDS = {
  { "review", { qa = true, review = true, reviewer = true, test = true, tests = true, testing = true, tester = true } },
  { "dev", { dev = true, developer = true, develop = true, implement = true, implementation = true, build = true,
    builder = true } },
  { "plan", { plan = true, planner = true, planning = true, engineer = true, architect = true } },
}

-- The phase a skill's name or a subagent's description names, by whole words; nil for none.
function facts.phaseOf(text)
  local words = {}
  for w in tostring(text or ""):lower():gmatch("[a-z0-9]+") do words[w] = true end
  for _, p in ipairs(PHASE_WORDS) do
    for w in pairs(words) do
      if p[2][w] then return p[1] end
    end
  end
  return nil
end

-- What started a step, as the hooks keep it: nil when empty or only the phase's word; 80 characters at most.
local function startedBy(text, phase)
  local by = text:sub(1, 80)
  if by == "" or by:lower():match("^%s*(.-)%s*$") == phase then return nil end
  return by
end

-- The steps of facts written before passes, for ticket `t` and its timeline lines `lines` (oldest first), by the
-- hooks' own rules: a lane started (a "phase" line), or a skill or subagent whose name names another phase than the
-- open step's (the phase its line carries is only the ticket's at the time: a name with no phase word starts
-- nothing), starts a step, closing the open one (the same phase as the last step continues it); a "done" line closes the
-- newest open step of its phase, or is a step of no length. Before the oldest line, the lanes started earlier give
-- a step each, up to the next one's start. With no lines, the lanes alone.
local function derivedPasses(t, lines)
  if #lines == 0 then return lanePasses(t) end
  local out = {}
  local function last() return out[#out] end
  local function start(phase, at, by)
    local l = last()
    if l and l.phase == phase then
      l.endAt, l.verdict = nil, nil
      l.by = l.by or by
      return
    end
    if l and not l.endAt then l.endAt = at end
    out[#out + 1] = { phase = phase, at = at, by = by }
  end
  for _, e in ipairs(lines) do
    if e.kind == "phase" and IS_PHASE[e.text] then
      start(e.text, e.at)
    elseif (e.kind == "skill" or e.kind == "subagent") and facts.phaseOf(e.text) then
      local phase = facts.phaseOf(e.text)
      local l = last()
      if l and not l.endAt and l.phase == phase then
        -- The skill or subagent that came with the lane's start is what started the step.
        if not l.by and l.at == e.at then l.by = startedBy(e.text, phase) end
      else
        start(phase, e.at, startedBy(e.text, phase))
      end
    elseif e.kind == "done" and e.phase then
      local open
      for i = #out, 1, -1 do
        if out[i].phase == e.phase and not out[i].endAt then open = out[i] break end
      end
      local lane = t.ends and t.ends[e.phase]
      local verdict = lane and lane.at == e.at and lane.verdict or nil
      if open then open.endAt, open.verdict = e.at, verdict
      else out[#out + 1] = { phase = e.phase, at = e.at, endAt = e.at, verdict = verdict } end
    end
  end
  local before = {}
  for _, p in ipairs(lanePasses(t)) do
    if p.at < lines[1].at then before[#before + 1] = { phase = p.phase, at = p.at } end
  end
  if #out == 0 then return lanePasses(t) end
  -- A lane started before the timeline in the phase it starts with is that step, from its earlier start.
  if before[#before] and before[#before].phase == out[1].phase then
    out[1].at = before[#before].at
    before[#before] = nil
  end
  for i, p in ipairs(before) do p.endAt = (before[i + 1] or out[1]).at end
  table.move(out, 1, #out, #before + 1, before)
  return before
end

local function ticket(t, lines)
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
  out.passes = passes(t.passes)
  if #out.passes == 0 then out.passes = derivedPasses(out, lines) end
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
  for _, e in ipairs(type(data.timeline) == "table" and data.timeline or {}) do
    if type(e) == "table" and num(e.at) and str(e.ticket) and str(e.kind) and str(e.text) then
      f.timeline[#f.timeline + 1] = { at = e.at, ticket = e.ticket, kind = e.kind, text = e.text,
        phase = IS_PHASE[e.phase] and e.phase or nil }
    end
  end
  for key, t in pairs(type(data.tickets) == "table" and data.tickets or {}) do
    if type(key) == "string" then
      -- The ticket's lines, oldest first (the file keeps the newest first; lines of the same second, in order).
      local lines = {}
      for i = #f.timeline, 1, -1 do
        if f.timeline[i].ticket == key then lines[#lines + 1] = f.timeline[i] end
      end
      byStart(lines)
      f.tickets[key] = ticket(t, lines)
    end
  end
  if str(data.current) and f.tickets[data.current] then f.current = data.current end
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
