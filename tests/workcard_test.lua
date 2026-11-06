-- The card's two git blocks: did it change what the plan said (the plan's file map beside what git says changed
-- since the session's base) and what each turn did; everything from the agent and from git escaped, every list
-- cut at 200 paths.

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

-- With a plan: one row per path, the plan's side on the left, git's on the right, a mark between.
local v = workcard.view(factsWith(), GIT, PLAN, false)
local a = v and v.actual
check("plan: the question, the base, the footer", a and a.heading == "Did it change what the plan said?"
  and a.base == "a1b2c3d" and a.footer == "3 commits, 2 not committed.")
local r = a and a.rows or {}
check("plan: five rows, matched, missing, unchecked, then unplanned", #r == 5 and r[1].kind == "matched"
  and r[2].kind == "missing" and r[3].kind == "unchecked" and r[4].kind == "unplanned" and r[5].kind == "unplanned")
check("plan: matched, the same path both sides", r[1] and r[1].mark == "=" and r[1].label == "same file"
  and r[1].left.path == "src/app.js" and r[1].left.tint == nil
  and r[1].right.path == "src/app.js" and r[1].right.tint == "ok" and not r[1].right.unseen)
check("plan: missing, not changed yet", r[2] and r[2].mark == "←" and r[2].label == "planned, not changed"
  and r[2].left.path == "src/gone.js" and r[2].left.tint == "warn"
  and r[2].right.say == "not changed yet" and r[2].right.tone == "warn")
check("plan: unchecked, as written", r[3] and r[3].mark == "?" and r[3].label == "not checked"
  and r[3].left.path == "src/*.css" and r[3].left.tint == "neutral" and r[3].right.say == "not checked" and r[3].right.tone == nil)
check("plan: unplanned, the one no hook named marked", r[4] and r[4].mark == "→" and r[4].label == "not in the plan"
  and r[4].left.say == "not in the plan" and r[4].left.tone == "off"
  and r[4].right.path == "scratch.sh" and r[4].right.tint == "off" and r[4].right.unseen
  and r[5].right.path == "src/new.js" and not r[5].right.unseen)
check("plan: the summary", a and a.summary == "1 of 2 planned changed · 1 not checked · 2 not in the plan")
check("reading and errors: the line is the summary", workcard.view(factsWith(), { reading = true }, PLAN, false).actual.summary
  == "Reading git…" and workcard.view(factsWith(), { error = "git did not answer" }, nil, false).actual.summary == "git did not answer")
local nothing = workcard.view(factsWith(), { commits = "0", diff = "", uncommitted = "", untracked = "" }, nil, false)
check("nothing changed: the summary says so", nothing and nothing.actual.summary == "Nothing changed")
local allIn = workcard.view(factsWith(), { commits = "1", diff = "M\0src/app.js\0", uncommitted = "", untracked = "" },
  { steps = {}, markdown = "# x\n\n## Files\n\n- `src/app.js` — a\n" }, false)
local someMissing = workcard.view(factsWith(), { commits = "1", diff = "M\0src/app.js\0", uncommitted = "", untracked = "" },
  { steps = {}, markdown = "# x\n\n## Files\n\n- `src/app.js` — a\n- `src/gone.js` — b\n" }, false)
check("plan, none unchecked: no not-checked part", someMissing and someMissing.actual.summary == "1 of 2 planned changed")
check("plan, all changed, none unplanned: no unplanned part", allIn and allIn.actual.summary == "1 of 1 planned changed")
check("plan: dirty at start and never named, left out", a and not has(workcard.html(v), "old.txt"))

-- A planned path changed by something no hook named: tagged on the matched row too.
local planScratch = { steps = {}, markdown = "# Fix it\n\n## Files\n\n- `scratch.sh` — a script\n" }
local mv = workcard.view(factsWith(), GIT, planScratch, false)
local mr = mv and mv.actual.rows or {}
check("plan: a matched path no hook named, tagged", mr[1] and mr[1].kind == "matched" and mr[1].right.path == "scratch.sh"
  and mr[1].right.unseen and has(workcard.html(mv), '<td class="tint-ok"><code>scratch.sh</code> <span class="unseen">'
  .. "no edit seen</span></td></tr>"))

-- A session started in a subfolder: the plan's relative entries are read from there, as the hooks read its paths.
local inSub = factsWith()
inSub.git.prefix = "packages/web/"
inSub.seen = { ["packages/web/src/app.js"] = true }
local sv = workcard.view(inSub, { commits = "1", diff = "M\0packages/web/src/app.js\0", uncommitted = "", untracked = "" },
  PLAN, false)
local sr = sv and sv.actual.rows or {}
check("in a subfolder: the plan's src/app.js is git's packages/web/src/app.js", sr[1] and sr[1].kind == "matched"
  and sr[1].right.path == "packages/web/src/app.js" and sr[#sr].kind ~= "unplanned")

local MARK = '<td class="mark"><span aria-hidden="true">%s</span><span class="vh">%s</span></td>'
local html = workcard.html(v)
check("html: a panel, its question and summary, then what it shows", has(html, '<details class="panel actual" data-panel="actual" open><summary><span class="chev">›</span><h2>Did it change what the plan said?</h2>'
  .. '<span class="sum">1 of 2 planned changed · 1 not checked · 2 not in the plan</span></summary><div class="panel-body">'
  .. '<p class="explain">Left, the files the plan named. Right, what git shows changed since <code>a1b2c3d</code>. '
  .. "A gap on either side is the answer.</p>"))
check("html: the table's header", has(html, '<table class="pva"><thead><tr><th>The plan said</th><th></th>'
  .. "<th>It changed</th></tr></thead><tbody>"))
check("html: matched", has(html, '<tr class="matched"><td><code>src/app.js</code></td>' .. MARK:format("=", "same file")
  .. '<td class="tint-ok"><code>src/app.js</code></td></tr>'))
check("html: missing", has(html, '<tr class="missing"><td class="tint-warn"><code>src/gone.js</code></td>'
  .. MARK:format("←", "planned, not changed") .. '<td class="say say-warn">not changed yet</td></tr>'))
check("html: unchecked", has(html, '<tr class="unchecked"><td class="tint-neutral"><code>src/*.css</code></td>'
  .. MARK:format("?", "not checked") .. '<td class="say">not checked</td></tr>'))
check("html: unplanned, no edit seen", has(html, '<tr class="unplanned"><td class="say say-off">not in the plan</td>'
  .. MARK:format("→", "not in the plan") .. '<td class="tint-off"><code>scratch.sh</code> <span class="unseen">no edit seen</span></td></tr>')
  and count(html, "no edit seen") == 1)
check("html: the footer after the table", has(html, '</tbody></table><p class="foot">3 commits, 2 not committed.</p><p class="wholesession">The whole session, not only the lane picked.</p></div></details>'))
check("html: no old labels", not has(html, "PLAN VS ACTUAL") and not has(html, "✓") and not has(html, "＋")
  and not has(html, "not seen from the agent"))
check("html: one commit is one", has(workcard.html(workcard.view(factsWith(), { commits = "1", diff = "", uncommitted = "",
  untracked = "" }, nil, false)), '<p class="foot">1 commit, 0 not committed.</p>'))

-- No plan, or a plan with no file map: what changed, one list.
for name, plan in pairs({ ["no plan"] = false, ["a plan with no file map"] = { steps = {}, markdown = "# Fix it\n\nJust text." } }) do
  local nv = workcard.view(factsWith(), GIT, plan or nil, false)
  local na = nv and nv.actual
  local nl = na and na.list
  check(name .. ": what changed, one list", na and na.heading == "What changed?" and na.rows == nil and nl
    and #nl.rows == 3 and nl.rows[1].path == "scratch.sh" and nl.rows[1].unseen
    and nl.rows[2].path == "src/app.js" and nl.rows[3].path == "src/new.js" and nl.more == 0)
  local nh = workcard.html(nv)
  check(name .. ": drawn", has(nh, '<details class="panel actual" data-panel="actual" open><summary><span class="chev">›</span>'
    .. '<h2>What changed?</h2><span class="sum">3 changed · 1 no edit seen</span></summary><div class="panel-body">'
    .. '<p class="explain">What git shows changed'
    .. ' since <code>a1b2c3d</code>.</p><ul class="changed"><li><code>scratch.sh</code> <span class="unseen">no edit seen'
    .. "</span></li><li><code>src/app.js</code></li><li><code>src/new.js</code></li></ul>"
    .. '<p class="foot">3 commits, 2 not committed.</p><p class="wholesession">The whole session, not only the lane picked.</p></div></details>') and not has(nh, "<table"))
  check(name .. ": its summary", nv and nv.actual.summary == "3 changed · 1 no edit seen")
end

-- While git reads, and when it cannot answer: one line under the heading.
local reading = workcard.view(factsWith(), { reading = true }, PLAN, false)
check("reading: the line", reading and reading.actual.line == "Reading git…" and reading.actual.rows == nil
  and reading.actual.list == nil and reading.actual.heading == "Did it change what the plan said?")
local rh = workcard.html(reading)
check("reading: drawn", has(rh, '<h2>Did it change what the plan said?</h2><span class="sum">Reading git…</span></summary>'
  .. '<div class="panel-body"><p class="line">Reading git…</p><p class="wholesession">The whole session, not only the lane picked.</p></div></details>') and not has(rh, "<table") and not has(rh, 'class="foot"'))
check("reading, no file map: what changed", has(workcard.html(workcard.view(factsWith(), { reading = true }, nil, false)),
  '<h2>What changed?</h2><span class="sum">Reading git…</span></summary><div class="panel-body"><p class="line">Reading git…</p>'))
local gone = workcard.html(workcard.view(factsWith(), { error = "base a1b2c3d no longer exists" }, PLAN, false))
check("base gone: the line", has(gone, '<p class="line">base a1b2c3d no longer exists</p>') and not has(gone, "<table"))
local mute = workcard.view(factsWith(), { commits = "fatal: oops", diff = "", uncommitted = "", untracked = "" }, PLAN, false)
check("commits not a number: git did not answer", mute and mute.actual.line == "git did not answer" and mute.actual.rows == nil)
local spaced = workcard.view(factsWith(), { commits = "  12 \n", diff = "", uncommitted = "", untracked = "" }, PLAN, false)
check("commits: the number trimmed", spaced and spaced.actual.footer == "12 commits, 0 not committed.")
local hostile = workcard.html(workcard.view(factsWith(), { error = "<b>x</b> & y" }, nil, false))
check("an error line escaped", has(hostile, "&lt;b&gt;x&lt;/b&gt; &amp; y") and not has(hostile, "<b>"))

-- The turns, newest first: when, a dot, how long (or working now), tests, files, commits.
local turns = {
  { at = at(14, 5), files = { "src/app.js", "src/new.js" }, tests = { ran = 2, passed = 1, failed = 1 },
    commits = { { hash = "a1b2c3d", subject = "Fix the typo" }, { hash = "e4f5a6b", subject = "Fix this & that" } } },
  { at = at(13, 50), endAt = at(13, 55), files = { "src/app.js" }, tests = { ran = 3, passed = 0, failed = 0 }, commits = {} },
  { at = at(13, 0), endAt = at(13, 0) + 20, files = {}, tests = { ran = 0, passed = 0, failed = 0 }, commits = {} },
  { at = at(12, 0), endAt = at(12, 4), files = {}, tests = { ran = 2, passed = 2, failed = 0 }, commits = {} },
  { at = at(11, 0), endAt = at(11, 10), files = {}, tests = { ran = 3, passed = 1, failed = 2 }, commits = {} },
}
local tv = workcard.view(factsWith(turns), GIT, PLAN, true)
local rows = tv and tv.turns
check("turns: newest first", rows and #rows == 5 and rows[1].time == "14:05" and rows[2].time == "13:50"
  and rows[3].time == "13:00" and rows[5].time == "11:00")
check("turns: working now, then how long", rows and rows[1].head == "Working now" and rows[2].head == "5 min"
  and rows[3].head == "<1 min" and rows[4].head == "4 min")
check("turns: the dots", rows and rows[1].dot == "running" and rows[2].dot == "none" and rows[3].dot == "none"
  and rows[4].dot == "ok" and rows[5].dot == "bad")
check("turns: tests in words", rows and rows[1].tests == "1 test failed (of 2)" and rows[2].tests == "tests ran 3"
  and rows[3].tests == nil and rows[4].tests == "tests passed (2 of 2)" and rows[5].tests == "2 tests failed (of 3)")
check("turns: the summary", tv and tv.turnsSummary == "5 turns · 2 commits")
check("turns: one turn, no commits", (workcard.view(factsWith({ turns[2] }), GIT, PLAN, false) or {}).turnsSummary == "1 turn")
check("turns: the files", rows and #rows[1].files == 2 and rows[1].files[1] == "src/app.js" and #rows[3].files == 0)
check("turns: the files in words", rows and rows[1].summary == "2 files…" and rows[2].summary == "1 file…"
  and rows[3].summary == "No files edited.")
check("turns: commits", rows and #rows[1].commits == 2 and rows[1].commits[1].hash == "a1b2c3d"
  and rows[1].commits[1].subject == "Fix the typo" and #rows[2].commits == 0)

local th = workcard.html(tv)
check("turns html: a panel after the plan block", has(th, '<details class="panel turns" data-panel="turns" open><summary><span class="chev">›</span><h2>What did each turn do?</h2>'
  .. '<span class="sum">5 turns · 2 commits</span></summary><div class="panel-body"><ol class="turnlist">')
  and (th:find('data-panel="actual"', 1, true) or math.huge) < (th:find('data-panel="turns"', 1, true) or 0))
check("turns html: a running row", has(th, '<li><span class="at">14:05</span><span class="rail"><span class="pip running">'
  .. '</span></span><div class="turnbody"><div class="turnhead"><b>Working now</b><span class="tests"> · 1 test failed (of 2)'
  .. "</span></div>"))
check("turns html: the other dots", has(th, '<span class="pip none">') and has(th, '<span class="pip ok">')
  and has(th, '<span class="pip bad">'))
check("turns html: the file count opens to the paths", has(th, '<details class="files"><summary><span class="chev">›</span>'
  .. "2 files…</summary><ul><li><code>src/app.js</code></li><li><code>src/new.js</code></li></ul></details>"))
check("turns html: one file", has(th, '<summary><span class="chev">›</span>1 file…</summary>'))
check("turns html: no files", has(th, '<b>&lt;1 min</b></div><div class="nofiles">No files edited.</div>'))
check("turns html: tests", has(th, '<b>5 min</b><span class="tests"> · tests ran 3</span>')
  and has(th, '<b>4 min</b><span class="tests"> · tests passed (2 of 2)</span>')
  and has(th, '<span class="tests"> · 2 tests failed (of 3)</span>'))
check("turns html: commits", has(th, '<div class="commit"><code>a1b2c3d</code> Fix the typo</div>'))
check("turns html: a subject escaped", has(th, "<code>e4f5a6b</code> Fix this &amp; that</div>"))
check("turns html: newest first", (th:find("14:05", 1, true) or math.huge) < (th:find("13:50", 1, true) or 0))
check("turns html: no old labels", not has(th, "TURNS") and not has(th, "running</span>") and not has(th, "✓"))
-- A turn carries the lane it started in: the phase of the newest activity at or before it (a "done" still counts:
-- the work right after a lane closes belongs to it). Before any activity, no lane: a lane filter hides it.
local laned = factsWith({
  { at = at(14, 5), endAt = at(14, 6), files = {}, tests = { ran = 0, passed = 0, failed = 0 }, commits = {} },
  { at = at(13, 0), endAt = at(13, 1), files = {}, tests = { ran = 0, passed = 0, failed = 0 }, commits = {} },
  { at = at(12, 30), endAt = at(12, 31), files = {}, tests = { ran = 0, passed = 0, failed = 0 }, commits = {} },
  { at = at(11, 0), endAt = at(11, 1), files = {}, tests = { ran = 0, passed = 0, failed = 0 }, commits = {} },
})
laned.timeline = {
  { at = at(14, 0), ticket = "ABC-1", kind = "phase", text = "Dev", phase = "dev" },
  { at = at(12, 0), ticket = "ABC-1", kind = "phase", text = "Dev", phase = "dev" },
  { at = at(13, 0), ticket = "ABC-1", kind = "done", text = "review", phase = "review" },
  { at = at(12, 20), ticket = "ABC-1", kind = "phase", text = "Review", phase = "review" },
  { at = at(12, 25), ticket = "ABC-1", kind = "reply", text = "no lane" },
}
local lanes = workcard.view(laned, GIT, PLAN, false)
check("turns: each in the lane it started in", lanes and lanes.turns[1].phase == "dev" and lanes.turns[2].phase == "review"
  and lanes.turns[3].phase == "review" and lanes.turns[4].phase == nil)
local lh = workcard.html(lanes)
check("turns html: the lane on the row", has(lh, '<li data-phase="dev"><span class="at">14:05</span>')
  and has(lh, '<li data-phase="review"><span class="at">13:00</span>') and has(lh, '<li><span class="at">11:00</span>'))
check("turns html: a lane with no turns says so", has(lh, '<p class="nolane">No turns in this lane.</p>'))
check("plan block: says it is the whole session while a lane is picked",
  has(lh, '<p class="wholesession">The whole session, not only the lane picked.</p>'))

-- Working now only while the session works and only for the newest turn: an open turn the agent left (it was
-- stopped, or its last hook never came) says no end was recorded; its dot comes from its tests.
local idle = workcard.view(factsWith(turns), GIT, PLAN, false)
check("not working: the open turn has no end recorded", idle and idle.turns[1].head == "No end recorded"
  and idle.turns[1].dot == "bad" and idle.turns[2].head == "5 min")
check("not working: drawn", has(workcard.html(idle), '<span class="at">14:05</span><span class="rail"><span class="pip bad">'
  .. '</span></span><div class="turnbody"><div class="turnhead"><b>No end recorded</b>')
  and not has(workcard.html(idle), "Working now"))
local left = {
  { at = at(14, 5), files = {}, tests = { ran = 0, passed = 0, failed = 0 }, commits = {} },
  { at = at(13, 50), files = {}, tests = { ran = 0, passed = 0, failed = 0 }, commits = {} },
}
local lv = workcard.view(factsWith(left), GIT, PLAN, true)
check("working: only the newest open turn is working now", lv and lv.turns[1].head == "Working now"
  and lv.turns[1].dot == "running" and lv.turns[2].head == "No end recorded" and lv.turns[2].dot == "none")
-- The newest turn already ended while the session works (between its Stop and the next prompt): its length.
local ended = workcard.view(factsWith({ { at = at(14, 5), endAt = at(14, 8), files = {},
  tests = { ran = 0, passed = 0, failed = 0 }, commits = {} } }), GIT, PLAN, true)
check("working, the newest turn ended: its length, not working now", ended and ended.turns[1].head == "3 min"
  and ended.turns[1].dot == "none" and not has(workcard.html(ended), "Working now"))
-- A turn stopped with Esc (no Stop hook) is left open when the next prompt comes, with no end and no commits.
local stopped = workcard.view(factsWith({
  { at = at(14, 5), files = {}, tests = { ran = 0, passed = 0, failed = 0 }, commits = {} },
  { at = at(13, 50), files = { "src/app.js" }, tests = { ran = 0, passed = 0, failed = 0 }, commits = {} },
}), GIT, PLAN, true)
check("stopped: its start, no end recorded, no commits", stopped and stopped.turns[2].time == "13:50"
  and stopped.turns[2].head == "No end recorded" and #stopped.turns[2].commits == 0)
check("stopped: drawn with no commits", has(workcard.html(stopped), '<b>No end recorded</b></div><details class="files">'
  .. '<summary><span class="chev">›</span>1 file…</summary><ul><li><code>src/app.js</code></li></ul></details></div></li></ol>'))

check("no turns: no turns block", not has(workcard.html(workcard.view(factsWith(), GIT, PLAN, false)), 'data-panel="turns"'))

-- The styles: light colours, dark ones for a dark page, sentence-case headings, paths that wrap.
local CSS = workcard.CSS
check("css: the light colours", has(CSS, "--ok: #1A7F37;") and has(CSS, "--ok-text: #116329;")
  and has(CSS, "--ok-bg: rgba(26,127,55,0.10);") and has(CSS, "--pill: #116329;") and has(CSS, "--pill-bg: rgba(26,127,55,0.14);")
  and has(CSS, "--warn: #9A6700;") and has(CSS, "--warn-bg: rgba(154,103,0,0.10);") and has(CSS, "--off: #4A55C8;")
  and has(CSS, "--off-bg: rgba(74,85,200,0.10);") and has(CSS, "--bad: #CF222E;"))
local dark = CSS:match("@media %(prefers%-color%-scheme: dark%) {(.-)} }") or ""
check("css: the dark colours", has(dark, "--ok: #3FB950;") and has(dark, "--ok-text: #C8FFC0;")
  and has(dark, "--ok-bg: rgba(63,185,80,0.12);") and has(dark, "--pill: #8FD18B;") and has(dark, "--pill-bg: rgba(63,185,80,0.16);")
  and has(dark, "--warn: #F2C14E;") and has(dark, "--warn-bg: rgba(242,193,78,0.10);") and has(dark, "--off: #9DA6F5;")
  and has(dark, "--off-bg: rgba(157,166,245,0.10);") and has(dark, "--bad: #E5534B;"))
check("css: the tints", CSS:match("%.tint%-ok {[^}]*var%(%-%-ok%-bg%)") and CSS:match("%.tint%-warn {[^}]*var%(%-%-warn%-bg%)")
  and CSS:match("%.tint%-off {[^}]*var%(%-%-off%-bg%)") and CSS:match("%.tint%-neutral {[^}]*background") ~= nil)
check("css: the warn text colour", has(CSS, "--warn-text: #7D5400;") and has(dark, "--warn-text: #F5D88A;"))
check("css: muted words in full colour (4.5:1)", has(CSS, ".pva .say-warn { color: var(--warn); }")
  and has(CSS, ".pva .say-off { color: var(--off); }") and not CSS:match("say%-%a+ {[^}]*color%-mix"))
check("css: a path on the warn tint in the warn text colour", has(CSS, ".tint-warn { background: var(--warn-bg); color: var(--warn-text); }"))
check("css: the dots", CSS:match("%.pip%.running {[^}]*border[^}]*var%(%-%-off%)") and CSS:match("%.pip%.ok {[^}]*var%(%-%-ok%)")
  and CSS:match("%.pip%.bad {[^}]*var%(%-%-bad%)") ~= nil)
check("css: no line after the last dot", has(CSS, ".turnlist > li:last-child .rail::after { content: none; }"))
check("css: the pill and its chevron", CSS:match("%.turns %.files > summary {[^}]*var%(%-%-pill%-bg%)") and has(CSS, "var(--pill)")
  and CSS:match("%.files%[open%] > summary %.chev {[^}]*rotate%(90deg%)") ~= nil)
check("css: open, the files are tinted too", CSS:match("%.turns %.files%[open%] ul {[^}]*background") ~= nil)
check("css: a hash in amber", CSS:match("%.commit code {[^}]*var%(%-%-warn%)") ~= nil)
check("css: paths wrap", CSS:match("overflow%-wrap: anywhere") ~= nil)

-- Escaping: a path from git and a path from a hook.
local evil = workcard.html(workcard.view(factsWith({ { at = at(9, 0), files = { "src/<b>.js" }, tests = { ran = 0, passed = 0,
  failed = 0 }, commits = {} } }), { commits = "0", diff = "M\0src/<b>.js\0", uncommitted = "", untracked = "" }, nil, false))
check("escaped: a path", has(evil, "<li><code>src/&lt;b&gt;.js</code>") and count(evil, "src/&lt;b&gt;.js") == 2
  and not has(evil, "<b>.js"))
local evilPlan = workcard.html(workcard.view(factsWith(), { commits = "0", diff = "M\0src/<b>.js\0", uncommitted = "",
  untracked = "" }, { steps = {}, markdown = "# x\n\n## Files\n\n- `src/<b>.js` — y\n" }, false))
check("escaped: a path in the table", has(evilPlan, '<td class="tint-ok"><code>src/&lt;b&gt;.js</code>')
  and not has(evilPlan, "<b>.js"))

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
local BIGGIT = { commits = "1", diff = table.concat(many), uncommitted = "", untracked = "" }
local bv = workcard.view(big, BIGGIT, nil, false)
check("cap: 200 rows and the rest counted", bv and bv.actual.list and #bv.actual.list.rows == 200 and bv.actual.list.more == 1
  and bv.actual.list.rows[200].path == "src/f200.js")
check("cap: a turn's files too", bv and #bv.turns[1].files == 200 and bv.turns[1].more == 1)
local bh = workcard.html(bv)
check("cap: and 1 more", count(bh, '<li class="more">and 1 more</li>') == 2 and not has(bh, "src/f201.js")
  and has(bh, '<span class="chev">›</span>201 files…</summary>'))
local pv = workcard.view(big, BIGGIT, { steps = {}, markdown = "# x\n\n## Files\n\n- `README.md` — y\n" }, false)
local pr = pv and pv.actual.rows or {}
check("cap: the table's rows too", #pr == 202 and pr[1].kind == "missing" and pr[201].kind == "unplanned"
  and pr[201].right.path == "src/f200.js" and pr[202].kind == "more" and pr[202].more == 1)
check("cap: the table's and 1 more", has(workcard.html(pv), '<tr class="more"><td colspan="3">and 1 more</td></tr></tbody>'))

check.done("work card")
