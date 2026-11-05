-- Plan vs actual: what the plan's file maps name, against what git says changed since the session's base.
-- The rules are strict: a plan entry and a changed path match only when equal relative to the repo root (a relative
-- entry read from the session's folder, as the hooks read the agent's paths); an entry no rule can decide (a glob,
-- a folder, a path outside the repo) is shown as written, never matched. It knows no
-- agent, and no Hammerspoon.

local actual = {}

-- The fields of git's `-z` output, in order; a trailing NUL or none, and empty text, give the same fields.
local function fields(text)
  local out = {}
  for field in (type(text) == "string" and text or ""):gmatch("[^%z]+") do out[#out + 1] = field end
  return out
end

-- The keys of set `set`, sorted.
local function sorted(set)
  local out = {}
  for key in pairs(set) do out[#out + 1] = key end
  table.sort(out)
  return out
end

-- `git diff --name-status -M -z` output as rows { status, path, from }: `status` is the letter ("M", "A", "D",
-- "R", …), and a rename or copy carries its old path in `from`. A row cut short is dropped.
function actual.parseDiff(text)
  local list, rows, i = fields(text), {}, 1
  while i <= #list do
    local status = list[i]:sub(1, 1)
    if status == "R" or status == "C" then
      if not list[i + 2] then break end
      rows[#rows + 1] = { status = status, path = list[i + 2], from = list[i + 1] }
      i = i + 3
    else
      if not list[i + 1] then break end
      rows[#rows + 1] = { status = status, path = list[i + 1] }
      i = i + 2
    end
  end
  return rows
end

-- Any `-z` path list (`git diff --name-only -z`, `git ls-files -z`) as a list of paths.
function actual.parseList(text)
  return fields(text)
end

-- Whether `path` has a segment no rule can place: `.`, `..`, or an empty one (`a//b`).
local function hasOddSegment(path)
  for segment in (path .. "/"):gmatch("([^/]*)/") do
    if segment == "" or segment == "." or segment == ".." then return true end
  end
  return false
end

-- A plan entry relative to `root`, or nil when no rule can decide it: a glob (`*`, `?`, `[`), a folder (a trailing
-- `/`), an absolute path outside the root (or any absolute path with no root), or a `.`, `..` or empty segment.
-- A relative entry starts at `prefix` (the session folder's place in the repo, "src/", or "" for the root), as
-- the hooks read the agent's relative paths. A `:12-30` suffix and a leading `./` are dropped first.
local function relative(entry, root, prefix)
  local path = entry:gsub(":[%d][%d%-,]*$", "")
  if path:find("[%*%?%[]") or path:sub(-1) == "/" then return nil end
  if path:sub(1, 1) == "/" then
    local base = type(root) == "string" and root:gsub("/+$", "") or ""
    if base == "" then return nil end
    local top = base .. "/"
    if path:sub(1, #top) ~= top then return nil end
    path = path:sub(#top + 1)
  else
    while path:sub(1, 2) == "./" do path = path:sub(3) end
    if path == "" then return nil end
    path = (type(prefix) == "string" and prefix or "") .. path
  end
  while path:sub(1, 2) == "./" do path = path:sub(3) end
  if path == "" or hasOddSegment(path) then return nil end
  return path
end

-- What the plan's file maps (planblocks' { kind = "filemap", rows = { { path, … } } }) name, for repo `root` and
-- a session started at `prefix` in it ("src/"; nil or "" for the root): { checked = { paths relative to the root },
-- unchecked = { entries as written }, written = { [path] = the first entry as written that gave it } }, lists
-- sorted, duplicates collapsed.
function actual.planned(filemaps, root, prefix)
  local checked, unchecked, written = {}, {}, {}
  for _, block in ipairs(filemaps or {}) do
    for _, row in ipairs(block.rows or {}) do
      if type(row.path) == "string" then
        local path = relative(row.path, root, prefix)
        if path then
          checked[path] = true
          written[path] = written[path] or row.path
        else
          unchecked[row.path] = true
        end
      end
    end
  end
  return { checked = sorted(checked), unchecked = sorted(unchecked), written = written }
end

-- The paths git says changed, as a set: every diff row's path, a rename's old path too, and every untracked
-- file. A path dirty when the session started is left out unless a hook of this session named it (`seen`).
local function changedSet(diff, untracked, dirtyAtStart, seen)
  local set = {}
  local function add(path)
    if path and (not dirtyAtStart[path] or seen[path]) then set[path] = true end
  end
  for _, row in ipairs(diff or {}) do
    add(row.path)
    if row.status == "R" then add(row.from) end
  end
  for _, path in ipairs(untracked or {}) do add(path) end
  return set
end

-- How many of the `changed` paths are not committed yet: named by `git diff HEAD` (`uncommitted`) or untracked.
local function countUncommitted(changed, uncommitted, untracked)
  local pending, n = {}, 0
  for _, path in ipairs(uncommitted or {}) do pending[path] = true end
  for _, path in ipairs(untracked or {}) do pending[path] = true end
  for path in pairs(changed) do if pending[path] then n = n + 1 end end
  return n
end

-- The plan against git, from { planned = actual.planned(…) or nil, diff = parseDiff rows, untracked = { paths },
-- uncommitted = { paths }, dirtyAtStart = set, seen = set }:
--   { hasPlan, matched, missing, unchecked, unplanned, changed (sorted lists), notSeen = { [path] = true },
--     uncommitted = n }.
-- matched: planned and changed; missing: planned, not changed; unplanned: changed, not planned; unchecked: the
-- entries no rule can decide, and a planned path dirty at start that no hook named (as written); notSeen: changed
-- paths no hook named. With no plan, or a plan with no file map entry, the plan's lists stay empty.
function actual.compare(input)
  local dirtyAtStart, seen = input.dirtyAtStart or {}, input.seen or {}
  local changed = changedSet(input.diff, input.untracked, dirtyAtStart, seen)
  local planned = input.planned
  local out = { hasPlan = planned ~= nil and (#planned.checked > 0 or #planned.unchecked > 0), matched = {},
    missing = {}, unchecked = {}, unplanned = {}, changed = sorted(changed), notSeen = {},
    uncommitted = countUncommitted(changed, input.uncommitted, input.untracked) }
  for path in pairs(changed) do
    if not seen[path] then out.notSeen[path] = true end
  end
  if not out.hasPlan then return out end

  local named, unchecked = {}, {}
  for _, entry in ipairs(planned.unchecked) do unchecked[entry] = true end
  for _, path in ipairs(planned.checked) do
    named[path] = true
    if changed[path] then
      out.matched[#out.matched + 1] = path
    elseif dirtyAtStart[path] and not seen[path] then
      unchecked[(planned.written or {})[path] or path] = true
    else
      out.missing[#out.missing + 1] = path
    end
  end
  for _, path in ipairs(out.changed) do
    if not named[path] then out.unplanned[#out.unplanned + 1] = path end
  end
  out.unchecked = sorted(unchecked)
  return out
end

return actual
