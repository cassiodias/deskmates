-- Reads the PR of a session's branch with gh for its card, off the main thread and within config.PR_SECONDS:
-- `gh pr view` in the repo, said in one line ("PR #5 · merged · checks passed"). No gh, no PR, an error or no
-- answer in time all say nothing: the card then shows no line.

local config = require("puppet.config")
local plans = require("puppet.model.plans")

local pr = {}

local FIELDS = "number,state,isDraft,url,statusCheckRollup"

-- The gh to run: the first of config.GH_PATHS for which exists(path) holds, or nil.
function pr.find(exists)
  for _, path in ipairs(config.GH_PATHS) do
    if exists(path) then return path end
  end
  return nil
end

local STATES = { OPEN = "open", MERGED = "merged", CLOSED = "closed" }
-- A finished check run's conclusions, and a status's states, that mean it failed.
local FAILED = { FAILURE = true, TIMED_OUT = true, CANCELLED = true, ACTION_REQUIRED = true, STARTUP_FAILURE = true,
  ERROR = true }
local WAITING = { PENDING = true, EXPECTED = true }

-- gh's JSON as { number, state ("open", "merged" or "closed"), draft, failing, pending, passed (the counts of
-- its checks), url (its page; only an https one) }; nil when it is not a PR.
function pr.parse(text)
  local data = plans.decode(text)
  if type(data) ~= "table" or math.type(data.number) ~= "integer" or not STATES[data.state] then return nil end
  local p = { number = data.number, state = STATES[data.state], draft = data.isDraft == true, failing = 0,
    pending = 0, passed = 0, url = type(data.url) == "string" and data.url:match("^https://[^%s]+$") or nil }
  for _, c in ipairs(type(data.statusCheckRollup) == "table" and data.statusCheckRollup or {}) do
    if type(c) == "table" then
      if c.__typename == "StatusContext" or (c.status == nil and c.state ~= nil) then
        if FAILED[c.state] then p.failing = p.failing + 1
        elseif WAITING[c.state] then p.pending = p.pending + 1
        else p.passed = p.passed + 1 end
      elseif c.status ~= "COMPLETED" then p.pending = p.pending + 1
      elseif FAILED[c.conclusion] then p.failing = p.failing + 1
      else p.passed = p.passed + 1 end
    end
  end
  return p
end

-- PR `p` (pr.parse) in one line: "PR #5 · merged · checks passed", "· 1 check failing", "· checks running",
-- "PR #8 · draft" (no checks part when it has none).
function pr.line(p)
  local state = (p.state == "open" and p.draft) and "draft" or p.state
  local out = "PR #" .. p.number .. " · " .. state
  if p.failing > 0 then
    out = out .. " · " .. p.failing .. " check" .. (p.failing == 1 and "" or "s") .. " failing"
  elseif p.pending > 0 then
    out = out .. " · checks running"
  elseif p.passed > 0 then
    out = out .. " · checks passed"
  end
  return out
end

-- Asks gh for the PR of the branch checked out at `root`. Calls done exactly once: done(line, url) (url nil when
-- gh gave no https page), or done(nil) when there is no gh, no PR, an error, or config.PR_SECONDS pass (gh is
-- then stopped).
function pr.read(root, done)
  local path = pr.find(function(p) return hs.fs.attributes(p) ~= nil end)
  if not path then return done(nil) end

  local finished, task, timer = false, nil, nil
  local function finish(line, url)
    if finished then return end
    finished = true
    if timer then timer:stop() end
    done(line, url)
  end

  task = hs.task.new(path, function(code, stdout)
    if finished then return end
    local p = code == 0 and pr.parse(stdout) or nil
    if p then finish(pr.line(p), p.url) else finish(nil) end
  end, { "pr", "view", "--json", FIELDS })
  if not task then return finish(nil) end
  -- hs.task's environment replaces the whole of it: gh's folder first on PATH (gh runs git), then Hammerspoon's.
  local folder, inherited = path:match("^(.*)/[^/]*$"), os.getenv("PATH")
  task:setEnvironment({ PATH = inherited and inherited ~= "" and folder .. ":" .. inherited or folder,
    HOME = os.getenv("HOME"), GH_PROMPT_DISABLED = "1", NO_COLOR = "1" })
  task:setWorkingDirectory(root)
  timer = hs.timer.doAfter(config.PR_SECONDS, function()
    if finished then return end
    if task:isRunning() then task:terminate() end
    finish(nil)
  end)
  if not task:start() then finish(nil) end
end

return pr
