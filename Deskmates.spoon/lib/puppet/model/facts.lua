-- A session's facts, as the hooks write them (hook/facts-lib.sh): one file per session,
--   { "current": "ABC-12", "tickets": { "ABC-12": { "phase", "phaseAt", "phases", "ends", "jira", "seen" } },
--     "timeline": [ { "at", "ticket", "kind", "text", "phase" } ], "updatedAt": … }
-- read here with every field checked: a bad field, ticket or entry is dropped on its own; a file that is not
-- facts is nil. It knows no agent, and no Hammerspoon.

local plans = require("puppet.model.plans")

local facts = {}

local PHASES = { "plan", "dev", "review" }
local IS_PHASE = { plan = true, dev = true, review = true }

local function num(v) return type(v) == "number" and v or nil end
local function str(v) return type(v) == "string" and v or nil end

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

-- The facts in file `path`, checked; nil when it is missing, broken or not facts.
function facts.load(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local data = plans.decode(file:read("a"))
  file:close()
  if type(data) ~= "table" or type(data.tickets) ~= "table" then return nil end
  local f = { tickets = {}, timeline = {}, updatedAt = num(data.updatedAt) }
  for key, t in pairs(data.tickets) do
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
