-- Reads a session's repo with git for its card, off the main thread and within config.GIT_SECONDS. Hands back
-- git's raw texts; model/actual.lua reads them. Every command runs as `git -C <root>` with GIT_OPTIONAL_LOCKS=0,
-- so it never takes the index.lock of an agent committing at the same moment.

local config = require("puppet.config")

local git = {}

local DID_NOT_ANSWER = "git did not answer"

-- The git to run: the first of config.GIT_PATHS for which exists(path) holds, or nil. /usr/bin/git counts only
-- with the command line tools or Xcode in: without them it is a stub that asks to install them.
function git.find(exists)
  local tools = exists("/Library/Developer/CommandLineTools/usr/bin/git") or exists("/Applications/Xcode.app")
  for _, path in ipairs(config.GIT_PATHS) do
    if exists(path) and (path ~= "/usr/bin/git" or tools) then return path end
  end
  return nil
end

-- True when git's stderr says a revision it was given does not exist.
local function badRevision(stderr)
  local text = (stderr or ""):lower()
  return text:find("bad revision", 1, true) or text:find("unknown revision", 1, true)
    or text:find("invalid revision range", 1, true)
end

-- The environment every command run by git at `path` gets (hs.task's replaces the whole of it): git's folder
-- first on PATH, so git-lfs and the helpers installed beside it are found, then Hammerspoon's PATH.
local function environment(path)
  local folder, inherited = path:match("^(.*)/[^/]*$"), os.getenv("PATH")
  local search = folder and folder ~= "" and folder or nil
  if inherited and inherited ~= "" then search = search and search .. ":" .. inherited or inherited end
  return { PATH = search, HOME = os.getenv("HOME"), GIT_OPTIONAL_LOCKS = "0" }
end

-- Runs, one after another, the commits since `base`, the diff from it, what is not committed and what git does
-- not track, in the repo at `root`. Calls done exactly once: done({ commits, diff, uncommitted, untracked }) with
-- git's -z texts; done(nil, "base a1b2c3d no longer exists") when base is gone; done(nil, "git did not answer")
-- when there is no git, a command fails, or config.GIT_SECONDS pass (the running command is then stopped).
function git.read(root, base, done, own)
  local path = git.find(function(p) return hs.fs.attributes(p) ~= nil end)
  if not path then return done(nil, DID_NOT_ANSWER) end

  local finished, running, timer = false, nil, nil
  local function finish(result, err)
    if finished then return end
    finished = true
    if timer then timer:stop() end
    done(result, err)
  end

  -- Starts git with args; then(stdout) runs when it succeeds, failed(stderr) when it does not.
  local function run(args, thenFn, failed)
    local full = { "-C", root }
    for _, a in ipairs(args) do full[#full + 1] = a end
    running = hs.task.new(path, function(code, stdout, stderr)
      if finished then return end
      if code == 0 then return thenFn(stdout or "") end
      if failed then return failed(stderr) end
      finish(nil, DID_NOT_ANSWER)
    end, full)
    if not running then return finish(nil, DID_NOT_ANSWER) end
    running:setEnvironment(environment(path))
    if not running:start() then finish(nil, DID_NOT_ANSWER) end
  end

  timer = hs.timer.doAfter(config.GIT_SECONDS, function()
    if finished then return end
    if running and running:isRunning() then running:terminate() end
    finish(nil, DID_NOT_ANSWER)
  end)

  local result = {}
  run({ "rev-list", "--count", base .. "..HEAD" }, function(count)
    result.commits = tonumber(count:match("^%s*(%d+)%s*$"))
    if not result.commits then return finish(nil, DID_NOT_ANSWER) end
    run({ "diff", "--name-status", "-M", "-z", base, "--" }, function(diff)
      result.diff = diff
      run({ "diff", "--name-only", "-z", "HEAD", "--" }, function(uncommitted)
        result.uncommitted = uncommitted
        run({ "ls-files", "--others", "--exclude-standard", "-z" }, function(untracked)
          result.untracked = untracked
          if not own or #own == 0 then return finish(result) end
          -- The files the session's own commits touched; a commit gone (rebased away) leaves them out.
          local args = { "show", "--name-only", "-z", "--format=" }
          for _, hash in ipairs(own) do args[#args + 1] = hash end
          args[#args + 1] = "--"
          run(args, function(committed)
            result.committed = committed
            finish(result)
          end, function() finish(result) end)
        end)
      end)
    end)
  end, function(stderr)
    if badRevision(stderr) then return finish(nil, "base " .. base:sub(1, 7) .. " no longer exists") end
    finish(nil, DID_NOT_ANSWER)
  end)
end

return git
