-- The card's one timeline, "What happened?": the session's turns (git) and each ticket's timeline merged, newest
-- first; a reply on the turn it ended, the other lines as thin markers between; everything from the agent escaped.

local root = arg[0]:match("^(.*)/tests/") or "."
package.path = root .. "/Deskmates.spoon/lib/?.lua;" .. root .. "/Deskmates.spoon/lib/?/init.lua;" .. package.path
local check = dofile(root .. "/tests/support/check.lua")
local story = require("puppet.ui.story")
local sessioncard = require("puppet.ui.sessioncard")
local workcard = require("puppet.ui.workcard")

local function has(html, text) return html:find(text, 1, true) ~= nil end
local function at(h, m, s) return os.time({ year = 2026, month = 11, day = 5, hour = h, min = m, sec = s or 0 }) end
local function count(text, what)
  local n, i = 0, 1
  while true do
    local s, e = text:find(what, i, true)
    if not s then return n end
    n, i = n + 1, e + 1
  end
end
local NONE = { ran = 0, passed = 0, failed = 0 }

-- Matching a reply to its turn: the reply that came between the turn's start and 5 s after its end (now, for a
-- turn with no end); the latest when several did; each reply used once.
local turns = {
  { at = at(14, 5) },                                -- open: up to now
  { at = at(13, 50), endAt = at(13, 55) },
  { at = at(13, 0), endAt = at(13, 2) },
  { at = at(12, 0), endAt = at(12, 4) },
}
local replies = {
  { at = at(14, 9), text = "Working on it." },
  { at = at(13, 55, 4), text = "Fixed the typo." },  -- 4 s after its turn's end: still its reply
  { at = at(13, 2, 6), text = "Too late." },         -- 6 s after: not its turn's
  { at = at(12, 3), text = "Second thought." },
  { at = at(12, 1), text = "First thought." },
  { at = at(11, 0), text = "Before every turn." },
}
local byTurn, left = story.match(turns, replies, at(14, 10))
check("match: a reply during an open turn, up to now", byTurn[1] == replies[1])
check("match: up to 5 s after the turn's end", byTurn[2] == replies[2])
check("match: not 6 s after", byTurn[3] == nil)
check("match: the latest of several", byTurn[4] == replies[4])
check("match: the rest left, in order", #left == 3 and left[1] == replies[3] and left[2] == replies[5]
  and left[3] == replies[6])
local twice = story.match({ { at = 100, endAt = 200 }, { at = 100, endAt = 200 } }, { { at = 150, text = "Once." } }, 300)
check("match: each reply used once", (twice[1] ~= nil) ~= (twice[2] ~= nil))
check("match: nothing to match", next((story.match({}, {}, 1))) == nil and #select(2, story.match({}, {}, 1)) == 0)

-- A session with git and a ticket: one list, newest first.
local facts = {
  current = "ABC-12",
  tickets = { ["ABC-12"] = { phase = "review", seen = at(14, 59),
    passes = { { phase = "dev", at = at(14, 0), endAt = at(14, 55) },
               { phase = "review", at = at(14, 56), endAt = at(14, 59), verdict = "APPROVED" } } } },
  timeline = {
    { at = at(14, 59), ticket = "ABC-12", kind = "done", text = "Nothing blocking.", phase = "review" },
    { at = at(14, 57, 50), ticket = "ABC-12", kind = "reply", text = "Reviewed <it>." },
    { at = at(14, 57), ticket = "ABC-12", kind = "tests", text = "passed", phase = "review" },
    { at = at(14, 56), ticket = "ABC-12", kind = "subagent", text = "Review phase steps diff", phase = "review" },
    { at = at(14, 56), ticket = "ABC-12", kind = "phase", text = "review", phase = "review" },
    { at = at(14, 30), ticket = "ABC-12", kind = "jira", text = "In Review", phase = "dev" },
    { at = at(14, 10), ticket = "ABC-12", kind = "skill", text = "my-developer", phase = "dev" },
    { at = at(13, 40), ticket = "ABC-12", kind = "reply", text = "Older than every turn." },
  },
  git = { root = "/r", base = "a1b2c3d4e5f6", dirtyAtStart = {} }, seen = {},
  turns = {
    { at = at(14, 57), endAt = at(14, 57, 50), files = {}, tests = { ran = 2, passed = 2, failed = 0 }, commits = {} },
    { at = at(14, 40), endAt = at(14, 40, 30), files = {}, tests = NONE, commits = {} },  -- says nothing: left out
    { at = at(14, 20), endAt = at(14, 35), files = { "src/app.js" }, tests = NONE,
      commits = { { hash = "a1b2c3d", subject = "Fix this & that" } } },
    { at = at(14, 0), endAt = at(14, 0, 40), files = { "src/a.js", "src/b.js" }, tests = NONE, commits = {} },
  },
}
local now = at(15, 0)
local session = sessioncard.view(facts, now, false)
local work = workcard.view(facts, { reading = true }, nil, false)
local v = story.view(session, work, now)
local t = v and v.tickets[1]
local kinds = {}
for _, r in ipairs(t and t.rows or {}) do kinds[#kinds + 1] = r.kind .. "@" .. os.date("%H:%M", r.at) end
check("view: turns, replies and markers, newest first", table.concat(kinds, " ")
  == "marker@14:59 turn@14:57 marker@14:56 marker@14:30 turn@14:20 marker@14:10 turn@14:00 reply@13:40")
check("view: a turn with its reply", t and t.rows[2].reply == "Reviewed <it>." and t.rows[2].tests == "tests passed (2 of 2)")
check("view: a turn that says nothing is left out", t and #t.rows == 8)
check("view: a reply no turn ended is a row of its own", t and t.rows[8].text == "Older than every turn.")
check("view: test lines are dropped, the turn shows them", not has(table.concat(kinds, " "), "marker@14:57"))
check("view: a lane started and its subagent are one marker", t and t.rows[3].label == "Review started"
  and t.rows[3].text == "Review phase steps diff")
check("view: done, with the step's verdict", t and t.rows[1].label == "✓ Review" and t.rows[1].verdict == "APPROVED"
  and t.rows[1].text == "Nothing blocking.")
check("view: skill and Jira markers", t and t.rows[6].label == "Dev" and t.rows[6].text == "my-developer"
  and t.rows[4].label == "Jira" and t.rows[4].text == "In Review")
check("view: under a minute, no length", t and t.rows[7].head == nil and t.rows[5].head == "15 min")
check("view: the summary counts turns and commits", t and t.summary == "4 turns · 1 commit")

local html = story.html(v)
check("html: one panel, its question and summary", has(html, '<details class="panel story" data-panel="story" open><summary>'
  .. '<span class="chev">›</span><h2>What happened?</h2><span class="sum"><span data-key="ABC-12">4 turns · 1 commit</span></span>'))
check("html: every row with its time for the filter", count(html, "<li ") == 8 and has(html, '<li data-at="' .. at(14, 57) .. '"')
  and has(html, '<li class="marker" data-at="' .. at(14, 56) .. '"'))
check("html: a turn's start and end, for the step filter", has(html, '<li data-at="' .. at(14, 57) .. '" data-end="'
  .. at(14, 57, 50) .. '">') and not has(html, '<li data-at="' .. at(13, 40) .. '" data-end'))
check("html: a turn's reply first, then how long and tests", has(html, '<div class="turnbody"><div class="reply">Reviewed &lt;it&gt;.</div>'
  .. '<div class="turnhead"><span class="tests">tests passed (2 of 2)</span></div>'))
check("html: a turn's length", has(html, '<div class="turnhead"><b>15 min</b></div>'))
check("html: the files pill and commits", has(html, '<details class="files"><summary><span class="chev">›</span>1 file…</summary>'
  .. "<ul><li><code>src/app.js</code></li></ul></details>") and has(html, '<div class="commit"><code>a1b2c3d</code> Fix this &amp; that</div>'))
check("html: never no files edited", not has(html, "No files edited") and not has(html, "&lt;1 min"))
check("html: a marker, a thin line", has(html, '<li class="marker" data-at="' .. at(14, 56) .. '"><span class="at">14:56</span>'
  .. '<span class="rail"></span><div class="markline"><span class="what">Review started</span> · <span class="text">'
  .. "Review phase steps diff</span></div></li>"))
check("html: done with its verdict", has(html, '<span class="what">✓ Review</span> <span class="verdict">APPROVED</span> · '
  .. '<span class="text">Nothing blocking.</span>'))
check("html: a reply row, drawn like a turn with nothing else", has(html, '<li data-at="' .. at(13, 40) .. '"><span class="at">13:40</span>'
  .. '<span class="rail"><span class="pip none"></span></span><div class="turnbody"><div class="reply">Older than every turn.</div></div></li>'))
check("html: the step with nothing in it says so", has(html, '<p class="nolane">Nothing happened in this step.</p>'))
check("html: each ticket's list is switched by Also", has(html, '<div class="storyticket" data-key="ABC-12"><ol class="storylist">'))

-- Working now: the running turn keeps its words and its ring, even with nothing else.
local running = workcard.view({ tickets = {}, timeline = {}, seen = {}, git = facts.git,
  turns = { { at = at(14, 5), files = {}, tests = NONE, commits = {} },
            { at = at(13, 0), files = {}, tests = NONE, commits = {} } } }, { reading = true }, nil, true)
local rv = story.view(nil, running, at(14, 6))
check("running: shown, an open turn left before it with nothing is not", rv and #rv.tickets[1].rows == 1
  and rv.tickets[1].rows[1].head == "Working now" and rv.tickets[1].rows[1].dot == "running")
local rh = story.html(rv)
check("running: drawn with its ring, no end yet", has(rh, '<span class="pip running"></span>') and has(rh, "<b>Working now</b>")
  and has(rh, '<li data-at="' .. at(14, 5) .. '" data-end="">'))
check("git only: one list, no ticket key", not has(rh, "data-key") and has(rh, "1 turn"))
local leftOpen = workcard.view({ tickets = {}, timeline = {}, seen = {}, git = facts.git,
  turns = { { at = at(13, 0), files = { "a.js" }, tests = NONE, commits = {} } } }, { reading = true }, nil, false)
check("no end recorded: its words kept", has(story.html(story.view(nil, leftOpen, at(14, 0))), "<b>No end recorded</b>"))

-- Tickets, no git: the replies and markers alone.
local nogit = story.view(sessioncard.view({ current = "ABC-1", tickets = { ["ABC-1"] = { seen = 1, phases = {} } },
  timeline = { { at = 5, ticket = "ABC-1", kind = "reply", text = "Done." }, { at = 4, ticket = "ABC-1", kind = "jira", text = "Done" } } }, 10),
  nil, 10)
check("no git: replies and markers", nogit and #nogit.tickets[1].rows == 2 and nogit.tickets[1].rows[1].kind == "reply"
  and nogit.tickets[1].summary == "1 turn")
local empty = story.view(sessioncard.view({ current = "ABC-1", tickets = { ["ABC-1"] = { seen = 1, phases = {} } }, timeline = {} }, 1), nil, 1)
check("no git, nothing yet: the panel says so", empty and empty.tickets[1].summary == "Nothing yet"
  and has(story.html(empty), "Nothing yet"))
local markersOnly = story.view(sessioncard.view({ current = "ABC-1", tickets = { ["ABC-1"] = { seen = 1, phases = {} } },
  timeline = { { at = 4, ticket = "ABC-1", kind = "jira", text = "Done" } } }, 10), nil, 10)
check("markers only: counted as lines", markersOnly.tickets[1].summary == "1 line")
check("no session, no turns to show: no panel", story.view(nil, nil, 1) == nil
  and story.view(nil, workcard.view({ tickets = {}, timeline = {}, seen = {}, git = facts.git, turns = {} }, { reading = true }, nil, false), 1) == nil)

-- Two tickets: each its own list, with its own lines and replies; the session's turns in both.
local two = sessioncard.view({ current = "ABC-1", tickets = { ["ABC-1"] = { seen = 20, phases = {} }, ["ABC-2"] = { seen = 10, phases = {} } },
  timeline = { { at = 120, ticket = "ABC-1", kind = "reply", text = "One." }, { at = 110, ticket = "ABC-2", kind = "jira", text = "Done" } } }, 200)
local twoWork = workcard.view({ tickets = {}, timeline = {}, seen = {}, git = facts.git,
  turns = { { at = 100, endAt = 130, files = { "a.js" }, tests = NONE, commits = {} } } }, { reading = true }, nil, false)
local tv = story.view(two, twoWork, 200)
check("tickets: each its own list", #tv.tickets == 2 and tv.tickets[1].key == "ABC-1" and tv.tickets[2].key == "ABC-2")
check("tickets: the turn in both, the reply on it in its ticket's list", #tv.tickets[1].rows == 1 and tv.tickets[1].rows[1].reply == "One."
  and #tv.tickets[2].rows == 2 and tv.tickets[2].rows[2].kind == "turn" and tv.tickets[2].rows[2].reply == nil)
local th = story.html(tv)
check("tickets: all but the first hidden", has(th, '<div class="storyticket" data-key="ABC-2" hidden>')
  and has(th, '<span data-key="ABC-2" hidden>'))

-- Escaping.
local evil = '<script>alert(1)</script><img src=x onerror="alert(1)"></div>\'&'
local eh = story.html(story.view(sessioncard.view({ current = "ABC-1", tickets = { ["ABC-1"] = { seen = 1, phases = {} } },
  timeline = { { at = 3, ticket = "ABC-1", kind = "reply", text = evil }, { at = 2, ticket = "ABC-1", kind = "subagent", text = evil },
    { at = 1, ticket = "ABC-1", kind = "jira", text = evil } } }, 5), workcard.view({ tickets = {}, timeline = {}, seen = {},
  git = facts.git, turns = { { at = 2, endAt = 4, files = { evil }, tests = NONE, commits = { { hash = "abc1234", subject = evil } } } } },
  { reading = true }, nil, false), 5))
check("escaped: no tags from the agent", not has(eh, "<script") and not has(eh, "<img"))
check("escaped: no stray closing div", select(2, eh:gsub("</div>", "")) == select(2, eh:gsub("<div", "")))

-- The styles: the rail and dots, the marker's thin line, the step filter.
check("css: the rail and the dots", has(story.CSS, ".storylist .rail") and story.CSS:match("%.pip%.running {[^}]*var%(%-%-off%)") ~= nil)
check("css: a marker is a thin line in the phase colour", story.CSS:match("%.marker [^{]*{[^}]*font%-size") ~= nil
  and story.CSS:match("%.markline %.what {[^}]*var%(%-%-accent%)") ~= nil)
check("css: rows outside the step hidden, and a word when none is left", has(story.CSS, ".storylist > li.out { display: none; }")
  and has(story.CSS, "body.lane .storylist:not(:has(> li:not(.out))) + .nolane { display: block; }"))
check("css: no line after the last dot", has(story.CSS, ".storylist > li:last-child .rail::after { content: none; }"))

-- A turn filled from the transcript says so; a turn the hooks recorded does not.
local filled = workcard.view({ tickets = {}, timeline = {}, seen = {}, git = facts.git,
  turns = { { at = at(14, 5), endAt = at(14, 6), files = {}, tests = NONE, fromTranscript = true,
              commits = { { hash = "b2c3d4e", subject = "Fixed the typo." } } },
            { at = at(13, 0), endAt = at(13, 1), files = {}, tests = NONE,
              commits = { { hash = "a1b2c3d", subject = "Start." } } } } }, { reading = true }, nil, false)
local filledHtml = story.html(story.view(nil, filled, at(15, 0)) or { tickets = {} })
check("transcript: its turn says so, once", count(filledHtml, '<span class="from">from the transcript</span>') == 1)
check("transcript: in the turn it came from", filledHtml:find('data%-at="' .. at(14, 5) .. '"[^>]*>.-from the transcript') ~= nil
  and not filledHtml:find('data%-at="' .. at(13, 0) .. '"[^>]*>[^\n]-from the transcript'))

-- A full hash (facts now keep git's whole one) shows cut to 7; an old facts file's short one as it is.
local full = story.html(story.view(nil, workcard.view({ tickets = {}, timeline = {}, seen = {},
  git = { root = "/r", base = "a1b2c3d4e5f6", dirtyAtStart = {} },
  turns = { { at = 1000, endAt = 1100, files = {}, tests = { ran = 0, passed = 0, failed = 0 },
    commits = { { hash = "e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3", subject = "Fixed the typo." } } } } },
  { reading = true }, nil, false), 2000))
check("a full hash shows cut to 7", has(full, '<div class="commit"><code>e4f5a6b</code> Fixed the typo.</div>'))

check.done("story")
