-- Fills a Claude session's facts from its transcript for its card: finds the transcript where Claude Code keeps
-- it, and runs hook/backfill.sh off the main thread within config.BACKFILL_SECONDS. The script writes the facts
-- file; this hands back only its one-line answer.

local config = require("puppet.config")

local backfill = {}

local NOT_READABLE, TOO_LONG = "transcript not readable", "transcript took too long"

-- The transcript of session `session` under home `home`: ~/.claude/projects/<project>/<session>.jsonl, the first
-- found; nil when there is none. dir(path) is hs.fs.dir: it returns an iterator and the folder object the
-- iterator must be handed on each call, and throws for a folder that is not there; exists(path) says whether a file
-- is there.
function backfill.find(home, session, dir, exists)
  if type(session) ~= "string" or not session:match("^[%w._-]+$") then return nil end
  local projects = home .. "/.claude/projects"
  local ok, found = pcall(function()
    local iterate, folder = dir(projects)
    for name in iterate, folder do
      if name ~= "." and name ~= ".." then
        local path = projects .. "/" .. name .. "/" .. session .. ".jsonl"
        if exists(path) then return path end
      end
    end
    return nil
  end)
  return ok and found or nil
end

-- Runs `script` for session `session`. Calls done exactly once: done("ok", turns added), done("none"), or
-- done("error", why) when it says so, says nothing, cannot start, or takes longer than config.BACKFILL_SECONDS
-- (it is then stopped).
function backfill.run(script, session, done)
  local finished, timer, task = false, nil, nil
  local function finish(status, detail)
    if finished then return end
    finished = true
    if timer then timer:stop() end
    done(status, detail)
  end
  task = hs.task.new("/bin/sh", function(_, stdout)
    local line = (stdout or ""):match("^([^\n]*)") or ""
    local n = line:match("^ok (%d+)$")
    if n then return finish("ok", tonumber(n)) end
    if line == "none" then return finish("none") end
    local why = line:match("^error (.+)$")
    finish("error", why or NOT_READABLE)
  end, { script, session })
  if not task then return finish("error", NOT_READABLE) end
  timer = hs.timer.doAfter(config.BACKFILL_SECONDS, function()
    if finished then return end
    if task:isRunning() then task:terminate() end
    finish("error", TOO_LONG)
  end)
  if not task:start() then finish("error", NOT_READABLE) end
end

return backfill
