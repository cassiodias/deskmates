-- A session's plan, as every translator writes it (hook/plan-lib.sh): one neutral file per session,
--   { "steps": [ { "id": "1", "title": "…", "status": "pending|active|done" } ], "plan": { "markdown": "…" } }
-- read here into { steps = { … }, markdown = "…" or nil }. It knows no agent, and no Hammerspoon.

local plans = {}

local STATUSES = { pending = true, active = true, done = true }
local ESCAPES = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

-- JSON into Lua: objects and arrays as tables (null leaves a hole), strings with their escapes, numbers,
-- booleans. Nil for anything that is not one whole JSON value.
function plans.decode(text)
  if type(text) ~= "string" then return nil end
  local at = 1
  local value

  local function space() at = text:find("[^ \t\r\n]", at) or #text + 1 end

  local function str()
    local out = {}
    at = at + 1
    while true do
      local c = text:sub(at, at)
      if c == "" then error("open string") end
      if c == '"' then at = at + 1; return table.concat(out) end
      if c == "\\" then
        local e = text:sub(at + 1, at + 1)
        if ESCAPES[e] then
          out[#out + 1] = ESCAPES[e]
          at = at + 2
        elseif e == "u" then
          local code = tonumber(text:sub(at + 2, at + 5), 16) or error("bad \\u")
          at = at + 6
          if code >= 0xD800 and code <= 0xDBFF and text:sub(at, at + 1) == "\\u" then
            local low = tonumber(text:sub(at + 2, at + 5), 16)
            if low and low >= 0xDC00 and low <= 0xDFFF then
              code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
              at = at + 6
            end
          end
          out[#out + 1] = utf8.char(code)
        else
          error("bad escape")
        end
      else
        local stop = text:find('["\\]', at) or error("open string")
        out[#out + 1] = text:sub(at, stop - 1)
        at = stop
      end
    end
  end

  function value()
    space()
    local c = text:sub(at, at)
    if c == "{" then
      local t = {}
      at = at + 1
      space()
      if text:sub(at, at) == "}" then at = at + 1; return t end
      while true do
        space()
        if text:sub(at, at) ~= '"' then error("key") end
        local key = str()
        space()
        if text:sub(at, at) ~= ":" then error("colon") end
        at = at + 1
        t[key] = value()
        space()
        local sep = text:sub(at, at)
        at = at + 1
        if sep == "}" then return t end
        if sep ~= "," then error("object") end
      end
    elseif c == "[" then
      local t, n = {}, 0
      at = at + 1
      space()
      if text:sub(at, at) == "]" then at = at + 1; return t end
      while true do
        n = n + 1
        t[n] = value()
        space()
        local sep = text:sub(at, at)
        at = at + 1
        if sep == "]" then return t end
        if sep ~= "," then error("array") end
      end
    elseif c == '"' then
      return str()
    else
      for word, v in pairs({ ["true"] = true, ["false"] = false, ["null"] = "null" }) do
        if text:sub(at, at + #word - 1) == word then
          at = at + #word
          if v == "null" then return nil end
          return v
        end
      end
      local number = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", at)
      if not number or number == "" or number == "-" then error("value") end
      at = at + #number
      return tonumber(number) or error("number")
    end
  end

  local ok, result = pcall(function()
    local v = value()
    space()
    if at <= #text then error("trailing") end
    return v
  end)
  if ok then return result end
  return nil
end

-- The plan file of a session in folder `dir`; nil for an id that could name a path outside it (as plan_file in
-- hook/plan-lib.sh).
function plans.path(dir, session)
  if type(session) ~= "string" or session == "" or session == "." or session == ".." then return nil end
  if session:find("[^A-Za-z0-9._-]") then return nil end
  return dir .. "/" .. session .. ".json"
end

local function read(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local text = file:read("a")
  file:close()
  return text
end

-- The plan in file `path`: only steps of the neutral shape are kept. Nil when it is missing, broken or not a plan.
function plans.load(path)
  local data = plans.decode(read(path))
  if type(data) ~= "table" or type(data.steps) ~= "table" then return nil end
  local plan = { steps = {}, updatedAt = tonumber(data.updatedAt) }
  for _, step in ipairs(data.steps) do
    if type(step) == "table" and type(step.id) == "string" and type(step.title) == "string"
      and STATUSES[step.status] then
      plan.steps[#plan.steps + 1] = { id = step.id, title = step.title, status = step.status }
    end
  end
  if type(data.plan) == "table" and type(data.plan.markdown) == "string" then plan.markdown = data.plan.markdown end
  return plan
end

-- How far along a plan is: steps done, steps in all, and the title of the step being worked on.
function plans.progress(plan)
  local p = { done = 0, total = 0 }
  for _, step in ipairs(plan and plan.steps or {}) do
    p.total = p.total + 1
    if step.status == "done" then p.done = p.done + 1 end
    if step.status == "active" and not p.active then p.active = step.title end
  end
  return p
end

-- Whether a plan has anything to show: a step, or markdown.
function plans.hasContent(plan)
  if not plan then return false end
  return #plan.steps > 0 or (plan.markdown ~= nil and plan.markdown ~= "")
end

-- Deletes the plans in `dir` no session needs: not in `keep` (a set of session ids) and last changed more than
-- `maxAge` seconds before `now`, or broken. Other files stay.
function plans.sweep(dir, keep, now, maxAge)
  local pipe = io.popen("ls -1 '" .. dir:gsub("'", "'\\''") .. "' 2>/dev/null")
  if not pipe then return end
  local names = {}
  for name in pipe:lines() do names[#names + 1] = name end
  pipe:close()
  for _, name in ipairs(names) do
    local session = name:match("^(.+)%.json$")
    if session and not keep[session] then
      local plan = plans.load(dir .. "/" .. name)
      if not plan or (plan.updatedAt or 0) < now - maxAge then os.remove(dir .. "/" .. name) end
    end
  end
end

return plans
