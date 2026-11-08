-- The session part of the card: ticket, Jira badge, phase strip, NOW and the timeline, from a session's facts;
-- everything from the agent escaped.

local root = arg[0]:match("^(.*)/tests/") or "."
package.path = root .. "/Deskmates.spoon/lib/?.lua;" .. root .. "/Deskmates.spoon/lib/?/init.lua;" .. package.path
local check = dofile(root .. "/tests/support/check.lua")
local sessioncard = require("puppet.ui.sessioncard")

local function has(html, text) return html:find(text, 1, true) ~= nil end
local function clock(t) return os.date("%H:%M", t) end
local function at(h, m) return os.time({ year = 2026, month = 11, day = 5, hour = h, min = m, sec = 0 }) end

local f = {
  current = "ABC-12",
  tickets = {
    ["ABC-12"] = { phase = "review", phaseAt = at(15, 40), phases = { plan = at(13, 10), dev = at(14, 50), review = at(15, 40) },
      passes = { { phase = "plan", at = at(13, 10) }, { phase = "dev", at = at(14, 50), by = "my-developer" },
                 { phase = "review", at = at(15, 40), by = "QA ABC-12 lens break" } },
      jira = { status = "In Dev", at = at(15, 10) }, seen = at(15, 52) },
    ["ABC-34"] = { phase = "review", phaseAt = at(9, 0), phases = { review = at(9, 0) },
      passes = { { phase = "review", at = at(9, 0) } }, seen = at(9, 30) },
  },
  timeline = {
    { at = at(15, 52), ticket = "ABC-12", kind = "reply", text = "ABC-12 is built and committed locally." },
    { at = at(15, 40), ticket = "ABC-12", kind = "subagent", text = "QA ABC-12 lens break", phase = "review" },
    { at = at(15, 40), ticket = "ABC-12", kind = "phase", text = "review", phase = "review" },
    { at = at(15, 26), ticket = "ABC-12", kind = "tests", text = "passed", phase = "dev" },
    { at = at(15, 10), ticket = "ABC-12", kind = "jira", text = "In Dev", phase = "dev" },
    { at = at(9, 30), ticket = "ABC-34", kind = "reply", text = "ABC-34 reviewed." },
  },
}
local v = sessioncard.view(f, at(15, 52), true)
local t = v and v.tickets[1]
check("view: the current ticket first", v and v.current == "ABC-12" and t.key == "ABC-12")
check("view: then the others", v and v.tickets[2] and v.tickets[2].key == "ABC-34" and #v.tickets == 2)
check("view: the Jira badge with its time", t and t.jira.status == "In Dev" and t.jira.time == "15:10")
check("view: the strip is the steps, in order", t and #t.strip == 3 and t.strip[1].phase == "plan" and t.strip[2].phase == "dev"
  and t.strip[3].phase == "review")
check("view: a step left with no end is reached, up to the next one's start", t and t.strip[1].state == "reached"
  and t.strip[1].ended == "14:50" and t.strip[2].state == "reached" and t.strip[2].ended == "15:40")
check("view: the last step, in the ticket's phase, is current", t and t.strip[3].state == "current")
check("view: the strip's times", t and t.strip[1].time == "13:10" and t.strip[2].time == "14:50" and t.strip[3].time == "15:40")
check("view: each step's span, for the filter", t and t.strip[1].from == at(13, 10) and t.strip[1].to == at(14, 50)
  and t.strip[3].from == at(15, 40) and t.strip[3].to == nil)
-- Review: a Review end whose start was missed (or a parallel subagent's) left a zero-length step after the open Dev:
-- Dev is still the one running, not "reached".
local parallel = sessioncard.view({ current = "ABC-1", tickets = { ["ABC-1"] = { phase = "dev", seen = at(10, 40),
  passes = { { phase = "dev", at = at(10, 20) }, { phase = "review", at = at(10, 30), endAt = at(10, 30) } } } },
  timeline = {} }, at(10, 45), true).tickets[1].strip
check("view: a step followed only by zero-length ones is still current", parallel[2].state == "current"
  and parallel[2].took == "25 min" and parallel[3].state == "done")
local closed = sessioncard.view({ current = "ABC-1", tickets = { ["ABC-1"] = { phase = "dev", seen = at(10, 40),
  passes = { { phase = "dev", at = at(10, 20) }, { phase = "review", at = at(10, 30), endAt = at(10, 35) } } } },
  timeline = {} }, at(10, 45), true).tickets[1].strip
check("view: a step followed by a real one is reached", closed[2].state == "reached")
-- Review: the strip scrolls sideways; the dots above its line and a long verdict stay whole.
check("css: the strip leaves room for its dots", has(sessioncard.CSS, ".strip { display: flex; gap: 4px; margin: 0 0 4px; padding-top: 8px; overflow-x: auto; overflow-y: hidden; }"))
check("css: a long verdict is cut, not spilled", has(sessioncard.CSS, ".phase .verdict { overflow: hidden; text-overflow: ellipsis; }"))
check("view: what started each step", t and t.strip[1].by == nil and t.strip[2].by == "my-developer"
  and t.strip[3].by == "QA ABC-12 lens break")
check("view: how long, on the current step only", t and t.strip[3].took == "12 min" and t.strip[1].took == nil)
check("view: where steps come from", t and t.source == "Steps come from the names of the agent's skills and subagents: "
  .. "plan or brainstorm is Plan; build, implement, execute, debug or dev is Dev; review, test, verify or QA is Review.")
check("view: each row's time, for the filter", t and t.rows[1].at == at(15, 52) and t.rows[5].at == at(15, 10))
check("view: NOW is the ticket's latest reply", t and t.now == "ABC-12 is built and committed locally.")
check("view: the ticket's rows, newest first", t and #t.rows == 5 and t.rows[1].time == "15:52" and t.rows[5].time == "15:10")
check("view: row labels", t and t.rows[1].label == "" and t.rows[2].label == "Review" and t.rows[3].label == "Review started"
  and t.rows[3].text == "" and t.rows[4].label == "✓ tests" and t.rows[5].label == "Jira")
check("view: each row's kind, for the story", t and t.rows[1].kind == "reply" and t.rows[2].kind == "subagent"
  and t.rows[3].kind == "phase" and t.rows[4].kind == "tests" and t.rows[5].kind == "jira")
check("view: the other ticket's NOW", v and v.tickets[2].now == "ABC-34 reviewed.")
check("view: no Plan step yet: Plan ahead, first", v and #v.tickets[2].strip == 2 and v.tickets[2].strip[1].phase == "plan"
  and v.tickets[2].strip[1].state == "ahead" and v.tickets[2].strip[1].time == nil and v.tickets[2].strip[1].from == nil
  and v.tickets[2].strip[2].phase == "review" and v.tickets[2].strip[2].state == "current")

-- Live (6 Nov): Dev, Review, then Dev again (build, review, fix) drew Dev's span around Review's, as if the coding
-- happened inside the review. Each pass is its own step now, in the order it happened.
local again = { current = "ABC-12", tickets = { ["ABC-12"] = { phase = "review", phaseAt = at(10, 22),
  phases = { plan = at(10, 17), dev = at(10, 20), review = at(10, 19) }, seen = at(10, 23),
  passes = { { phase = "plan", at = at(10, 17), endAt = at(10, 18) }, { phase = "dev", at = at(10, 18), endAt = at(10, 19), by = "my-developer" },
             { phase = "review", at = at(10, 19), endAt = at(10, 20), by = "my-reviewer", verdict = "CHANGES_REQUESTED" },
             { phase = "dev", at = at(10, 20), endAt = at(10, 22), by = "Implement ABC-12 fixes" },
             { phase = "review", at = at(10, 22), by = "my-reviewer" } } } }, timeline = {} }
local steps = sessioncard.view(again, at(10, 25), true).tickets[1].strip
check("again: one step per pass, in order", #steps == 5 and steps[2].phase == "dev" and steps[3].phase == "review"
  and steps[4].phase == "dev" and steps[5].phase == "review")
check("again: the passes before are done, with their spans", steps[2].state == "done" and steps[2].time == "10:18"
  and steps[2].ended == "10:19" and steps[4].state == "done" and steps[4].time == "10:20" and steps[4].ended == "10:22")
check("again: the review's verdict on its own step", steps[3].verdict == "CHANGES_REQUESTED" and steps[5].verdict == nil)
check("again: each its own span", steps[4].from == at(10, 20) and steps[4].to == at(10, 22) and steps[5].to == nil)
local working = steps[5]
check("working: minutes from its own start", working.state == "current" and working.time == "10:22" and working.took == "3 min"
  and working.ended == nil)
local idle = sessioncard.view(again, at(10, 40), false).tickets[1].strip[5]
check("idle: the step ends at the last thing that happened", idle.time == "10:22" and idle.took == nil and idle.ended == "10:23")
local idleHead = sessioncard.html(sessioncard.view(again, at(10, 40), false))
check("idle: drawn as a span", idleHead:find("10:22 → 10:23", 1, true) ~= nil and not idleHead:find(" min", 1, true))
check("again: each step drawn with its span and what started it", idleHead:find('<button class="phase done" data-phase="dev" data-from="'
  .. at(10, 20) .. '" data-to="' .. at(10, 22) .. '" title="Implement ABC-12 fixes"><span class="dot"></span>Dev<small>10:20 → 10:22 ✓</small>'
  .. '<span class="by">Implement ABC-12 fixes</span></button>', 1, true) ~= nil)
check("again: the last step has no end to its span", idleHead:find('<button class="phase current on" data-phase="review" data-from="'
  .. at(10, 22) .. '" title="my-reviewer">', 1, true) ~= nil)
check("again: where steps come from, under the strip", idleHead:find('</div><p class="source">Steps come from the names of the '
  .. "agent&#39;s skills and subagents: plan or brainstorm is Plan; build, implement, execute, debug or dev is Dev; review, test, verify or QA is Review.</p>", 1, true) ~= nil)
-- A step still open when the next started elsewhere (its end was never seen): reached, up to the next start; an
-- open step that is the last but not the ticket's phase is reached too.
local stray = sessioncard.view({ current = "ABC-1", tickets = { ["ABC-1"] = { phase = "dev", seen = 50,
  passes = { { phase = "plan", at = 10 }, { phase = "dev", at = 20 }, { phase = "review", at = 30 } } } }, timeline = {} }, 60, true)
check("stray: an open step before the last is reached", stray.tickets[1].strip[2].state == "reached"
  and stray.tickets[1].strip[2].ended == clock(30))
check("stray: the last step not in the ticket's phase is reached, no end", stray.tickets[1].strip[3].state == "reached"
  and stray.tickets[1].strip[3].ended == nil and stray.tickets[1].strip[3].took == nil)

-- Cassio (5 Nov): a lane that finished says so: ✓, its span, and the verdict the agent wrote.
local done = { current = "ABC-12", tickets = { ["ABC-12"] = { phase = "review", phaseAt = at(10, 22),
  passes = { { phase = "plan", at = at(10, 17), endAt = at(10, 18) }, { phase = "dev", at = at(10, 20), endAt = at(10, 21) },
             { phase = "review", at = at(10, 22), endAt = at(10, 23), verdict = "APPROVED" } }, seen = at(10, 23) } },
  timeline = { { at = at(10, 23), ticket = "ABC-12", kind = "done", text = "Nothing blocking.", phase = "review" } } }
local dv = sessioncard.view(done, at(10, 30), true).tickets[1]
check("ended: every lane done", dv.strip[1].state == "done" and dv.strip[2].state == "done" and dv.strip[3].state == "done")
check("ended: its span", dv.strip[2].time == "10:20" and dv.strip[2].ended == "10:21" and dv.strip[2].took == nil)
check("ended: the current lane stops counting", dv.strip[3].ended == "10:23" and dv.strip[3].took == nil)
check("ended: the verdict", dv.strip[3].verdict == "APPROVED" and dv.strip[2].verdict == nil)
check("ended: the done row, with its step's verdict", dv.rows[1].label == "✓ Review" and dv.rows[1].text == "Nothing blocking."
  and dv.rows[1].verdict == "APPROVED")
local dh = sessioncard.html(sessioncard.view(done, at(10, 30), true))
check("ended: drawn done, with ✓ and the verdict", dh:find('class="phase done on" data-phase="review"', 1, true) ~= nil
  and dh:find("✓", 1, true) ~= nil and dh:find('<span class="verdict">APPROVED</span>', 1, true) ~= nil)
local reopened = { current = "ABC-12", tickets = { ["ABC-12"] = { phase = "dev", phaseAt = at(10, 25),
  passes = { { phase = "dev", at = at(10, 20) } }, seen = at(10, 25) } }, timeline = {} }
check("reopened: a lane with no end is current again", sessioncard.view(reopened, at(10, 30), true).tickets[1].strip[2].state == "current")

local function took(seconds)
  local one = { current = "ABC-1", tickets = { ["ABC-1"] = { phase = "dev", phaseAt = 1000, passes = { { phase = "dev", at = 1000 } },
    seen = 1000 } }, timeline = {} }
  return sessioncard.view(one, 1000 + seconds, true).tickets[1].strip[2].took
end
check("took: under a minute", took(30) == "<1 min")
check("took: hours", took(2 * 3600 + 5 * 60) == "2 h 5 min")

local waiting = sessioncard.view({ tickets = { ["-"] = { phase = "dev", phaseAt = 1000, passes = { { phase = "dev", at = 1000 } },
  seen = 1000 } },
  timeline = { { at = 1000, ticket = "-", kind = "skill", text = "my-developer", phase = "dev" } } }, 1000)
check("view: no ticket, only a phase: no key, the strip", waiting and waiting.tickets[1].key == nil
  and waiting.tickets[1].strip[2].state == "current" and #waiting.tickets[1].rows == 1)
check("view: nil facts", sessioncard.view(nil, 1) == nil)
check("view: facts with no tickets", sessioncard.view({ tickets = {}, timeline = {} }, 1) == nil)
local failed = sessioncard.view({ current = "ABC-1", tickets = { ["ABC-1"] = { seen = 1, phases = {} } },
  timeline = { { at = 1, ticket = "ABC-1", kind = "tests", text = "failed" } } }, 1)
check("view: failed tests", failed.tickets[1].rows[1].label == "✗ tests")
local bare = failed.tickets[1]
check("view: no steps at all: the three phases ahead, nothing said of where steps come from", #bare.strip == 3
  and bare.strip[1].state == "ahead" and bare.strip[2].state == "ahead" and bare.strip[3].state == "ahead"
  and bare.strip[2].phase == "dev" and bare.source == nil)
check("html: no steps, no source line", not has(sessioncard.html(failed), 'class="source"'))

-- html: the header (the story, "What happened?", is ui/story.lua's).
local head = sessioncard.html(v)
check("html: the header only", select("#", sessioncard.html(v)) == 1 and not has(head, "<details")
  and not has(head, 'class="timeline"'))
check("html: the ticket and its badge", has(head, "ABC-12") and has(head, "In Dev") and has(head, "15:10"))
check("html: the strip's buttons", has(head, 'data-phase="plan"') and has(head, 'class="phase current on" data-phase="review"'))
check("html: what started a step, under its times", has(head, '<small>14:50 → 15:40</small><span class="by">my-developer</span>'))
check("html: an ahead step has no span", has(head, '<button class="phase ahead" data-phase="plan"><span class="dot"></span>Plan<small></small></button>'))
check("html: NOW", has(head, "NOW") and has(head, "ABC-12 is built and committed locally."))
check("html: the other ticket is hidden", has(head, 'data-key="ABC-34" hidden'))
check("html: Also lists both, current first", has(head, '<select class="also"><option value="ABC-12">ABC-12</option><option value="ABC-34">'))
local single = sessioncard.html(sessioncard.view({ current = "ABC-1", tickets = { ["ABC-1"] = { seen = 1, phases = {} } }, timeline = {} }, 1))
check("html: one ticket, no Also", not has(single, "<select"))

-- Cassio (6 Nov): the card opens on the step happening now. The current step is picked; with none, the newest
-- step reached; with none reached, nothing. The reader's own pick (a step's start, or none) wins while that step
-- is still there.
local function strip(states)
  local out = {}
  for i, state in ipairs(states) do out[i] = { state = state, from = state ~= "ahead" and i * 10 or nil } end
  return out
end
check("pick: the current step", sessioncard.pick(strip({ "ahead", "done", "current", "done" })) == 3)
check("pick: no current, the newest not ahead", sessioncard.pick(strip({ "done", "reached", "ahead" })) == 2)
check("pick: all ahead, none", sessioncard.pick(strip({ "ahead", "ahead", "ahead" })) == nil)
check("pick: the reader's step", sessioncard.pick(strip({ "ahead", "done", "current" }), 20) == 2)
check("pick: the reader's none", sessioncard.pick(strip({ "ahead", "done", "current" }), "none") == nil)
check("pick: a step no longer there, the default", sessioncard.pick(strip({ "ahead", "done", "current" }), 99) == 3)
local pickedHead = sessioncard.html(v, at(14, 50))
check("html: the reader's step drawn picked, in the ticket that has it",
  has(pickedHead, 'class="phase reached on" data-phase="dev" data-from="' .. at(14, 50) .. '"')
  and has(pickedHead, 'class="phase current" data-phase="review"')
  and has(pickedHead, 'class="phase current on" data-phase="review" data-from="' .. at(9, 0) .. '"'))
local noneHead = sessioncard.html(v, "none")
check("html: the reader's none, nothing picked", not has(noneHead, " on\""))
local msg = function(body) return sessioncard.stepMessage(body) end
check("message: a step's start", msg("step:1730700000") == 1730700000)
check("message: none", msg("step:none") == "none")
for _, junk in ipairs({ "step:", "step:12a", "step:-12", "step: 12", "step:1.5", "step:NONE", " step:12", "step:12 ",
  "step:" .. string.rep("1", 16), "fold:story:closed", 42, nil, {} }) do
  check("message: junk refused (" .. tostring(junk) .. ")", msg(junk) == nil)
end

local evil = '<script>alert(1)</script><img src=x onerror="alert(1)"></div>\'&'
local eh = sessioncard.html(sessioncard.view({ current = "ABC-1", tickets = { ["ABC-1"] = { seen = 1, phases = {}, jira = { status = evil, at = 1 },
  passes = { { phase = "dev", at = 1, by = evil, verdict = evil } } } },
  timeline = { { at = 1, ticket = "ABC-1", kind = "reply", text = evil }, { at = 1, ticket = "ABC-1", kind = "subagent", text = evil } } }, 1))
check("escaped: no script tag", not has(eh, "<script"))
check("escaped: no img tag", not has(eh, "<img"))
check("escaped: no stray closing div", select(2, eh:gsub("</div>", "")) == select(2, eh:gsub("<div", "")))
check("escaped: quotes and ampersands", has(eh, "&quot;alert(1)&quot;") and has(eh, "&#39;&amp;"))
check("escape: the five characters", sessioncard.escape([[<>&"']]) == "&lt;&gt;&amp;&quot;&#39;")
check("escaped: what started a step, in its title too", has(eh, 'title="&lt;script&gt;') and has(eh, '<span class="by">&lt;script&gt;'))
check("CSS: a string, the picked step marked", type(sessioncard.CSS) == "string" and has(sessioncard.CSS, ".phase.on"))
check("CSS: the strip scrolls sideways, each step one line per piece", has(sessioncard.CSS, "overflow-x: auto")
  and has(sessioncard.CSS, "flex: 1 0 104px") and has(sessioncard.CSS, "text-overflow: ellipsis") and has(sessioncard.CSS, ".source"))

check.done("sessioncard")
