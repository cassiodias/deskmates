-- The card's two git blocks: plan vs actual (the plan's file map against what git says changed since the
-- session's base) and the turns; everything from the agent and from git escaped, every list cut at 200 paths.

local root = arg[0]:match("^(.*)/tests/") or "."
package.path = root .. "/Deskmates.spoon/lib/?.lua;" .. root .. "/Deskmates.spoon/lib/?/init.lua;" .. package.path
local check = dofile(root .. "/tests/support/check.lua")
local workcard = require("puppet.ui.workcard")

local function has(html, text) return html:find(text, 1, true) ~= nil end
local function at(h, m) return os.time({ year = 2026, month = 11, day = 5, hour = h, min = m, sec = 0 }) end
local function count(text, what)
  local n, i = 0, 1
  while true do
    local s, e = text:find(what, i, true)
    if not s then return n end
    n, i = n + 1, e + 1
  end
end

local ROOT = "/Users/me/my-app"
local BASE = "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678"

-- Facts with a git base, `old.txt` dirty at start, and the paths the agent's hooks named.
local function factsWith(turns)
  return { tickets = {}, timeline = {}, turns = turns or {},
    git = { root = ROOT, base = BASE, dirtyAtStart = { ["old.txt"] = true } },
    seen = { ["src/app.js"] = true, ["src/new.js"] = true } }
end

-- git.read's answer: 3 commits; app.js changed (not committed yet), new.js added, old.txt dirty at start;
-- scratch.sh written by something no hook saw.
local GIT = { commits = "3\n", diff = "M\0src/app.js\0A\0src/new.js\0M\0old.txt\0", uncommitted = "src/app.js\0",
  untracked = "scratch.sh\0" }
local PLAN = { steps = {}, markdown = "# Fix it\n\n## Files\n\n- `src/app.js` — fix\n- `src/gone.js` — never touched\n"
  .. "- `src/*.css` — styles\n" }

check("no git in facts: no blocks", workcard.view({ tickets = {}, timeline = {}, turns = {}, seen = {} }, GIT, PLAN, false) == nil)
check("no facts: no blocks", workcard.view(nil, GIT, PLAN, false) == nil)

-- The three lists, with their marks.
local v = workcard.view(factsWith(), GIT, PLAN, false)
local a = v and v.actual
check("header: base, commits, uncommitted", a and a.header == "since a1b2c3d · 3 commits · 2 uncommitted")
check("lists: three, in order", a and #a.lists == 3 and a.lists[1].mark == "✓" and a.lists[1].title == "planned and changed"
  and a.lists[2].mark == "○" and a.lists[2].title == "planned, not changed"
  and a.lists[3].mark == "＋" and a.lists[3].title == "changed, not planned")
check("lists: planned and changed", a and #a.lists[1].rows == 1 and a.lists[1].rows[1].path == "src/app.js"
  and not a.lists[1].rows[1].unseen)
check("lists: planned, not changed, then the entries not checked", a and #a.lists[2].rows == 2
  and a.lists[2].rows[1].path == "src/gone.js" and not a.lists[2].rows[1].unchecked
  and a.lists[2].rows[2].path == "src/*.css" and a.lists[2].rows[2].unchecked)
check("lists: changed, not planned, the one no hook named marked", a and #a.lists[3].rows == 2
  and a.lists[3].rows[1].path == "scratch.sh" and a.lists[3].rows[1].unseen
  and a.lists[3].rows[2].path == "src/new.js" and not a.lists[3].rows[2].unseen)
check("lists: dirty at start and never named, left out", a and not has(workcard.html(v), "old.txt"))

local html = workcard.html(v)
check("html: the block, its header", has(html, '<section class="actual"><div class="label">PLAN VS ACTUAL</div>')
  and has(html, '<p class="since">since a1b2c3d · 3 commits · 2 uncommitted</p>'))
check("html: the lists with their marks", has(html, '<div class="name">✓ planned and changed <small>1</small></div>')
  and has(html, '<div class="name">○ planned, not changed <small>2</small></div>')
  and has(html, '<div class="name">＋ changed, not planned <small>2</small></div>'))
check("html: a path", has(html, "<li><code>src/app.js</code></li>"))
check("html: not checked", has(html, '<li><code>src/*.css</code> <span class="unchecked">not checked</span></li>'))
check("html: not seen from the agent", has(html, '<li><code>scratch.sh</code> <span class="unseen">not seen from the agent</span></li>')
  and count(html, "not seen from the agent") == 1)
check("html: one commit is one", has(workcard.html(workcard.view(factsWith(), { commits = "1", diff = "", uncommitted = "",
  untracked = "" }, nil, false)), "since a1b2c3d · 1 commit · 0 uncommitted"))

-- No plan, or a plan with no file map: one list, changed, with no marks.
for name, plan in pairs({ ["no plan"] = false, ["a plan with no file map"] = { steps = {}, markdown = "# Fix it\n\nJust text." } }) do
  local nv = workcard.view(factsWith(), GIT, plan or nil, false)
  local nl = nv and nv.actual.lists
  check(name .. ": one list, changed", nl and #nl == 1 and nl[1].title == "changed" and nl[1].mark == nil
    and #nl[1].rows == 3 and nl[1].rows[1].path == "scratch.sh" and nl[1].rows[1].unseen
    and nl[1].rows[2].path == "src/app.js" and nl[1].rows[3].path == "src/new.js")
  local nh = workcard.html(nv)
  check(name .. ": no marks", has(nh, '<div class="name">changed <small>3</small></div>')
    and not has(nh, "✓") and not has(nh, "○") and not has(nh, "＋"))
end

-- While git reads, and when it cannot answer: one line instead of the lists.
local reading = workcard.view(factsWith(), { reading = true }, PLAN, false)
check("reading: the line", reading and reading.actual.line == "reading git…" and reading.actual.lists == nil)
local rh = workcard.html(reading)
check("reading: drawn", has(rh, '<p class="line">reading git…</p>') and not has(rh, 'class="name"')
  and not has(rh, 'class="since"'))
local gone = workcard.html(workcard.view(factsWith(), { error = "base a1b2c3d no longer exists" }, PLAN, false))
check("base gone: the line", has(gone, '<p class="line">base a1b2c3d no longer exists</p>') and not has(gone, 'class="name"'))
local mute = workcard.view(factsWith(), { commits = "fatal: oops", diff = "", uncommitted = "", untracked = "" }, PLAN, false)
check("commits not a number: git did not answer", mute and mute.actual.line == "git did not answer" and mute.actual.lists == nil)
local spaced = workcard.view(factsWith(), { commits = "  12 \n", diff = "", uncommitted = "", untracked = "" }, PLAN, false)
check("commits: the number trimmed", spaced and spaced.actual.header == "since a1b2c3d · 12 commits · 0 uncommitted")
local hostile = workcard.html(workcard.view(factsWith(), { error = "<b>x</b> & y" }, nil, false))
check("an error line escaped", has(hostile, "&lt;b&gt;x&lt;/b&gt; &amp; y") and not has(hostile, "<b>"))

-- The turns, newest first: start time, how long (or running), files, tests, commits.
local turns = {
  { at = at(14, 5), files = { "src/app.js", "src/new.js" }, tests = { ran = 2, passed = 1, failed = 1 },
    commits = { { hash = "a1b2c3d", subject = "Fix the typo" }, { hash = "e4f5a6b", subject = "Fix this & that" } } },
  { at = at(13, 50), endAt = at(13, 55), files = { "src/app.js" }, tests = { ran = 3, passed = 0, failed = 0 }, commits = {} },
  { at = at(13, 0), endAt = at(13, 0) + 20, files = {}, tests = { ran = 0, passed = 0, failed = 0 }, commits = {} },
}
local tv = workcard.view(factsWith(turns), GIT, PLAN, true)
local rows = tv and tv.turns
check("turns: newest first", rows and #rows == 3 and rows[1].time == "14:05" and rows[2].time == "13:50" and rows[3].time == "13:00")
check("turns: running, then how long", rows and rows[1].took == "running" and rows[2].took == "5 min" and rows[3].took == "<1 min")
check("turns: the files", rows and #rows[1].files == 2 and rows[1].files[1] == "src/app.js" and #rows[3].files == 0)
check("turns: tests", rows and rows[1].tests == "ran 2 · ✓ 1 · ✗ 1" and rows[2].tests == "ran 3" and rows[3].tests == nil)
check("turns: commits", rows and #rows[1].commits == 2 and rows[1].commits[1].hash == "a1b2c3d"
  and rows[1].commits[1].subject == "Fix the typo" and #rows[2].commits == 0)

local th = workcard.html(tv)
check("turns html: after plan vs actual", has(th, '<section class="turns"><div class="label">TURNS</div>')
  and (th:find('class="actual"', 1, true) or math.huge) < (th:find('class="turns"', 1, true) or 0))
check("turns html: a row", has(th, '<span class="time">14:05</span><span class="took">running</span>'))
check("turns html: the file count opens to the paths", has(th, '<details class="files"><summary>2 files</summary><ul>'
  .. "<li><code>src/app.js</code></li><li><code>src/new.js</code></li></ul></details>"))
check("turns html: one file", has(th, "<summary>1 file</summary>"))
check("turns html: no files", has(th, '<span class="files">0 files</span>'))
check("turns html: tests", has(th, '<span class="tests">ran 2 · ✓ 1 · ✗ 1</span>') and has(th, '<span class="tests">ran 3</span>'))
check("turns html: commits", has(th, '<span class="commit"><code>a1b2c3d</code> Fix the typo</span>'))
check("turns html: a subject escaped", has(th, "<code>e4f5a6b</code> Fix this &amp; that</span>"))
check("turns html: newest first", (th:find("14:05", 1, true) or math.huge) < (th:find("13:50", 1, true) or 0))
-- "running" only while the session works and only for the newest turn: an open turn the agent left (it was
-- stopped, or its last hook never came) shows its start and no length.
local idle = workcard.view(factsWith(turns), GIT, PLAN, false)
check("not working: the open turn says no running", idle and idle.turns[1].took == nil and idle.turns[2].took == "5 min")
check("not working: drawn with an empty length",
  has(workcard.html(idle), '<span class="time">14:05</span><span class="took"></span><details class="files">')
  and not has(workcard.html(idle), "running"))
local left = {
  { at = at(14, 5), files = {}, tests = { ran = 0, passed = 0, failed = 0 }, commits = {} },
  { at = at(13, 50), files = {}, tests = { ran = 0, passed = 0, failed = 0 }, commits = {} },
}
local lv = workcard.view(factsWith(left), GIT, PLAN, true)
check("working: only the newest open turn is running", lv and lv.turns[1].took == "running" and lv.turns[2].took == nil)

check("no turns: no turns block", not has(workcard.html(workcard.view(factsWith(), GIT, PLAN, false)), 'class="turns"'))

-- Escaping: a path from git and a path from a hook.
local evil = workcard.html(workcard.view(factsWith({ { at = at(9, 0), files = { "src/<b>.js" }, tests = { ran = 0, passed = 0,
  failed = 0 }, commits = {} } }), { commits = "0", diff = "M\0src/<b>.js\0", uncommitted = "", untracked = "" }, nil, false))
check("escaped: a path", has(evil, "<li><code>src/&lt;b&gt;.js</code>") and not has(evil, "<b>"))

-- 200 paths per list, then how many more.
local many, files = {}, {}
for i = 1, 201 do
  local path = string.format("src/f%03d.js", i)
  many[#many + 1] = "A\0" .. path .. "\0"
  files[#files + 1] = path
end
local seen = {}
for _, p in ipairs(files) do seen[p] = true end
local big = factsWith({ { at = at(9, 0), endAt = at(9, 1), files = files, tests = { ran = 0, passed = 0, failed = 0 }, commits = {} } })
big.seen = seen
local bv = workcard.view(big, { commits = "1", diff = table.concat(many), uncommitted = "", untracked = "" }, nil, false)
check("cap: 200 rows and the rest counted", bv and #bv.actual.lists[1].rows == 200 and bv.actual.lists[1].more == 1
  and bv.actual.lists[1].rows[200].path == "src/f200.js")
check("cap: a turn's files too", bv and #bv.turns[1].files == 200 and bv.turns[1].more == 1)
local bh = workcard.html(bv)
check("cap: and 1 more", count(bh, '<li class="more">and 1 more</li>') == 2 and not has(bh, "src/f201.js")
  and has(bh, '<div class="name">changed <small>201</small></div>') and has(bh, "<summary>201 files</summary>"))

check.done("work card")
