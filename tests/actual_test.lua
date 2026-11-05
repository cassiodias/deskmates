-- Plan vs actual: git's `-z` output read into paths, a plan's file maps read into the paths it names, and the two
-- compared under the strict matching rules.

local root = arg[0]:match("^(.*)/tests/") or "."
package.path = root .. "/Deskmates.spoon/lib/?.lua;" .. root .. "/Deskmates.spoon/lib/?/init.lua;" .. package.path
local check = dofile(root .. "/tests/support/check.lua")
local actual = require("puppet.model.actual")

local function same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local ROOT = "/Users/me/my-app"

-- File map blocks as planblocks lifts them, one row per path.
local function filemap(...)
  local rows = {}
  for _, path in ipairs({ ... }) do rows[#rows + 1] = { path = path, badge = "edit", note = "" } end
  return { kind = "filemap", rows = rows }
end

-- A comparison with nothing dirty at start, every changed path seen, and nothing uncommitted unless given.
local function compare(paths, diff, more)
  more = more or {}
  local seen = more.seen
  if not seen then
    seen = {}
    for _, d in ipairs(diff) do seen[d.path] = true; if d.from then seen[d.from] = true end end
    for _, p in ipairs(more.untracked or {}) do seen[p] = true end
  end
  return actual.compare{ planned = paths and actual.planned({ filemap(table.unpack(paths)) }, ROOT), diff = diff,
    untracked = more.untracked or {}, uncommitted = more.uncommitted or {}, dirtyAtStart = more.dirtyAtStart or {},
    seen = seen }
end

-- Parsing git's -z output.
check("parseDiff: statuses and paths, a rename with its old path",
  same(actual.parseDiff("M\0src/a.js\0R100\0old.js\0new.js\0D\0gone.js\0"),
    { { status = "M", path = "src/a.js" }, { status = "R", path = "new.js", from = "old.js" },
      { status = "D", path = "gone.js" } }))
check("parseDiff: no trailing NUL", same(actual.parseDiff("A\0src/app.js"), { { status = "A", path = "src/app.js" } }))
check("parseDiff: a space and non-ASCII kept as they are",
  same(actual.parseDiff("M\0src/my file.js\0A\0docs/ção.md\0"),
    { { status = "M", path = "src/my file.js" }, { status = "A", path = "docs/ção.md" } }))
check("parseDiff: empty text, no rows", same(actual.parseDiff(""), {}))
check("parseList: paths, with a space and non-ASCII", same(actual.parseList("src/my file.js\0docs/ção.md\0"),
  { "src/my file.js", "docs/ção.md" }))
check("parseList: no trailing NUL", same(actual.parseList("src/app.js\0src/b.js"), { "src/app.js", "src/b.js" }))
check("parseList: empty text, no paths", same(actual.parseList(""), {}))

-- What a plan names.
check("planned: :lines and ./ stripped, duplicates collapse",
  same(actual.planned({ filemap("src/app.js:12-30", "./src/b.js", "src/app.js"), filemap("./src/b.js") }, ROOT),
    { checked = { "src/app.js", "src/b.js" }, unchecked = {},
      written = { ["src/app.js"] = "src/app.js:12-30", ["src/b.js"] = "./src/b.js" } }))
check("planned: globs and folders unchecked, as written",
  same(actual.planned({ filemap("src/*.js", "test/?.lua", "lib/[ab].lua", "docs/") }, ROOT),
    { checked = {}, unchecked = { "docs/", "lib/[ab].lua", "src/*.js", "test/?.lua" }, written = {} }))
check("planned: absolute under the root made relative, outside unchecked",
  same(actual.planned({ filemap(ROOT .. "/src/app.js", "/etc/hosts", ROOT .. "-old/x.js") }, ROOT),
    { checked = { "src/app.js" }, unchecked = { "/Users/me/my-app-old/x.js", "/etc/hosts" },
      written = { ["src/app.js"] = ROOT .. "/src/app.js" } }))
check("planned: . and .. segments and empty segments unchecked, as written",
  same(actual.planned({ filemap(".", "../x.js", "src/../src/app.js", "src//app.js", ROOT .. "/../other/x.js") }, ROOT),
    { checked = {}, unchecked = { ".", "../x.js", "/Users/me/my-app/../other/x.js", "src/../src/app.js", "src//app.js" },
      written = {} }))
check("planned: with no root every absolute entry is unchecked",
  same(actual.planned({ filemap("/etc/hosts", "src/app.js") }, nil),
    { checked = { "src/app.js" }, unchecked = { "/etc/hosts" }, written = { ["src/app.js"] = "src/app.js" } })
  and same(actual.planned({ filemap("/etc/hosts") }, "").unchecked, { "/etc/hosts" }))

-- The comparison.
local r = compare({ "src/app.js", "src/b.js" }, { { status = "M", path = "src/app.js" } })
check("compare: a planned file that changed is matched", r.hasPlan and same(r.matched, { "src/app.js" }))
check("compare: a planned file that did not change is missing", same(r.missing, { "src/b.js" }))
check("compare: nothing unplanned", same(r.unplanned, {}) and same(r.changed, { "src/app.js" }))

r = compare({ "src/app.js" }, { { status = "M", path = "src/app.js" }, { status = "M", path = "README.md" } },
  { untracked = { "src/new.js" } })
check("compare: a change the plan did not name is unplanned, untracked included",
  same(r.unplanned, { "README.md", "src/new.js" }) and same(r.changed, { "README.md", "src/app.js", "src/new.js" }))

r = compare({ "src/*.js", "docs/", "src/app.js" }, { { status = "M", path = "src/app.js" }, { status = "M", path = "src/b.js" } })
check("compare: globs and folders unchecked, never matched",
  same(r.unchecked, { "docs/", "src/*.js" }) and same(r.matched, { "src/app.js" }) and same(r.unplanned, { "src/b.js" }))

r = compare({ "src/app.js:3", "./src/b.js" }, { { status = "M", path = "src/app.js" }, { status = "M", path = "src/b.js" } })
check("compare: :lines and ./ stripped before matching", same(r.matched, { "src/app.js", "src/b.js" }))

r = compare({ ROOT .. "/src/app.js", "/etc/hosts" }, { { status = "M", path = "src/app.js" } })
check("compare: an absolute plan path under the root matched, outside unchecked",
  same(r.matched, { "src/app.js" }) and same(r.unchecked, { "/etc/hosts" }) and same(r.missing, {}))

r = compare({ "src/app.js", "src/b.js" }, { { status = "M", path = "src/app.js" }, { status = "M", path = "src/b.js" },
  { status = "M", path = "notes.txt" } }, { dirtyAtStart = { ["src/b.js"] = true, ["notes.txt"] = true },
  seen = { ["src/app.js"] = true } })
check("compare: a path dirty at start and never seen is left out of matched, missing, unplanned and changed",
  same(r.matched, { "src/app.js" }) and same(r.missing, {}) and same(r.unplanned, {})
  and same(r.changed, { "src/app.js" }))
r = compare({ "src/app.js", "./src/b.js:4" }, { { status = "M", path = "src/b.js" } },
  { dirtyAtStart = { ["src/b.js"] = true }, seen = {} })
check("compare: a planned path dirty at start and never seen is unchecked, as written",
  same(r.unchecked, { "./src/b.js:4" }) and same(r.missing, { "src/app.js" }) and same(r.matched, {}))

r = compare({ "src/b.js" }, { { status = "M", path = "src/b.js" }, { status = "M", path = "notes.txt" } },
  { dirtyAtStart = { ["src/b.js"] = true, ["notes.txt"] = true }, seen = { ["src/b.js"] = true, ["notes.txt"] = true } })
check("compare: a path dirty at start is kept when a hook named it",
  same(r.matched, { "src/b.js" }) and same(r.unplanned, { "notes.txt" }))

r = compare({ "old.js", "new.js" }, { { status = "R", path = "new.js", from = "old.js" } })
check("compare: a rename counts under its old and new paths",
  same(r.matched, { "new.js", "old.js" }) and same(r.missing, {}) and same(r.changed, { "new.js", "old.js" }))

r = compare({ "gone.js" }, { { status = "D", path = "gone.js" } })
check("compare: a deletion counts as changed", same(r.matched, { "gone.js" }) and same(r.missing, {}))

r = compare({ "src/app.js" }, { { status = "M", path = "src/app.js" }, { status = "M", path = "src/b.js" } },
  { seen = { ["src/app.js"] = true } })
check("compare: changed paths no hook named are not seen", same(r.notSeen, { ["src/b.js"] = true }))

r = compare({ "src/app.js" }, { { status = "M", path = "src/app.js" }, { status = "M", path = "src/b.js" } },
  { untracked = { "src/new.js" }, uncommitted = { "src/b.js", "elsewhere.js" } })
check("compare: uncommitted counts the shown paths in diff HEAD or untracked", r.uncommitted == 2)

r = compare(nil, { { status = "M", path = "src/app.js" } }, { untracked = { "src/new.js" } })
check("compare: no plan still fills notSeen and uncommitted", r.uncommitted == 1
  and same(r.notSeen, {}))
r = actual.compare{ planned = nil, diff = { { status = "M", path = "src/app.js" } }, untracked = {},
  uncommitted = { "src/app.js" }, dirtyAtStart = {}, seen = {} }
check("compare: no plan, notSeen and uncommitted filled from changed",
  same(r.notSeen, { ["src/app.js"] = true }) and r.uncommitted == 1)
r = compare(nil, { { status = "M", path = "src/app.js" } }, { untracked = { "src/new.js" } })
check("compare: no plan fills only changed", r.hasPlan == false and same(r.changed, { "src/app.js", "src/new.js" })
  and same(r.matched, {}) and same(r.missing, {}) and same(r.unchecked, {}) and same(r.unplanned, {}))
r = actual.compare{ planned = actual.planned({}, ROOT), diff = { { status = "M", path = "src/app.js" } },
  untracked = {}, uncommitted = {}, dirtyAtStart = {}, seen = {} }
check("compare: a plan with no file map is no plan", r.hasPlan == false and same(r.changed, { "src/app.js" })
  and same(r.unplanned, {}))

r = compare({ "src/*.js" }, { { status = "M", path = "src/app.js" } })
check("compare: a plan with only unchecked entries is a plan", r.hasPlan == true
  and same(r.unchecked, { "src/*.js" }) and same(r.unplanned, { "src/app.js" }))

check.done("actual")
