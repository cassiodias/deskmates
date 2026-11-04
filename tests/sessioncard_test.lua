-- The session part of the card: ticket, Jira badge, phase strip, NOW and the timeline, from a session's facts;
-- everything from the agent escaped.

local root = arg[0]:match("^(.*)/tests/") or "."
package.path = root .. "/Deskmates.spoon/lib/?.lua;" .. root .. "/Deskmates.spoon/lib/?/init.lua;" .. package.path
local check = dofile(root .. "/tests/support/check.lua")
local sessioncard = require("puppet.ui.sessioncard")

local function has(html, text) return html:find(text, 1, true) ~= nil end
local function at(h, m) return os.time({ year = 2026, month = 11, day = 5, hour = h, min = m, sec = 0 }) end

local f = {
  current = "ABC-12",
  tickets = {
    ["ABC-12"] = { phase = "review", phaseAt = at(15, 40), phases = { plan = at(13, 10), dev = at(14, 50), review = at(15, 40) },
      jira = { status = "In Dev", at = at(15, 10) }, seen = at(15, 52) },
    ["ABC-34"] = { phase = "review", phaseAt = at(9, 0), phases = { review = at(9, 0) }, seen = at(9, 30) },
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
local v = sessioncard.view(f, at(15, 52))
local t = v and v.tickets[1]
check("view: the current ticket first", v and v.current == "ABC-12" and t.key == "ABC-12")
check("view: then the others", v and v.tickets[2] and v.tickets[2].key == "ABC-34" and #v.tickets == 2)
check("view: the Jira badge with its time", t and t.jira.status == "In Dev" and t.jira.time == "15:10")
check("view: the strip's states", t and t.strip[1].phase == "plan" and t.strip[1].state == "reached"
  and t.strip[2].state == "reached" and t.strip[3].phase == "review" and t.strip[3].state == "current")
check("view: the strip's times", t and t.strip[1].time == "13:10" and t.strip[2].time == "14:50" and t.strip[3].time == "15:40")
check("view: how long, on the current phase only", t and t.strip[3].took == "12 min" and t.strip[1].took == nil)
check("view: NOW is the ticket's latest reply", t and t.now == "ABC-12 is built and committed locally.")
check("view: the ticket's rows, newest first", t and #t.rows == 5 and t.rows[1].time == "15:52" and t.rows[5].time == "15:10")
check("view: row labels", t and t.rows[1].label == "" and t.rows[2].label == "review" and t.rows[3].label == "review"
  and t.rows[4].label == "✓ tests" and t.rows[5].label == "Jira")
check("view: the other ticket's NOW", v and v.tickets[2].now == "ABC-34 reviewed.")
check("view: a phase not reached is ahead", v and v.tickets[2].strip[1].state == "ahead" and v.tickets[2].strip[1].time == nil)

local function took(seconds)
  local one = { current = "ABC-1", tickets = { ["ABC-1"] = { phase = "dev", phaseAt = 1000, phases = { dev = 1000 }, seen = 1000 } }, timeline = {} }
  return sessioncard.view(one, 1000 + seconds).tickets[1].strip[2].took
end
check("took: under a minute", took(30) == "<1 min")
check("took: hours", took(2 * 3600 + 5 * 60) == "2 h 5 min")

local waiting = sessioncard.view({ tickets = { ["-"] = { phase = "dev", phaseAt = 1000, phases = { dev = 1000 }, seen = 1000 } },
  timeline = { { at = 1000, ticket = "-", kind = "skill", text = "my-developer", phase = "dev" } } }, 1000)
check("view: no ticket, only a phase: no key, the strip", waiting and waiting.tickets[1].key == nil
  and waiting.tickets[1].strip[2].state == "current" and #waiting.tickets[1].rows == 1)
check("view: nil facts", sessioncard.view(nil, 1) == nil)
check("view: facts with no tickets", sessioncard.view({ tickets = {}, timeline = {} }, 1) == nil)
local failed = sessioncard.view({ current = "ABC-1", tickets = { ["ABC-1"] = { seen = 1, phases = {} } },
  timeline = { { at = 1, ticket = "ABC-1", kind = "tests", text = "failed" } } }, 1)
check("view: failed tests", failed.tickets[1].rows[1].label == "✗ tests")

-- html: the header part and the timeline part.
local head, timeline = sessioncard.html(v)
check("html: the ticket and its badge", has(head, "ABC-12") and has(head, "In Dev") and has(head, "15:10"))
check("html: the strip's buttons", has(head, 'data-phase="plan"') and has(head, 'class="phase current" data-phase="review"'))
check("html: NOW", has(head, "NOW") and has(head, "ABC-12 is built and committed locally."))
check("html: the other ticket is hidden", has(head, 'data-key="ABC-34" hidden'))
check("html: Also lists both, current first", has(head, '<select class="also"><option value="ABC-12">ABC-12</option><option value="ABC-34">'))
check("html: the timeline's rows", has(timeline, 'data-phase="review"') and has(timeline, "QA ABC-12 lens break")
  and has(timeline, 'data-key="ABC-34" hidden'))
local single = sessioncard.html(sessioncard.view({ current = "ABC-1", tickets = { ["ABC-1"] = { seen = 1, phases = {} } }, timeline = {} }, 1))
check("html: one ticket, no Also", not has(single, "<select"))

local evil = '<script>alert(1)</script><img src=x onerror="alert(1)"></div>\'&'
local eh, et = sessioncard.html(sessioncard.view({ current = "ABC-1", tickets = { ["ABC-1"] = { seen = 1, phases = {}, jira = { status = evil, at = 1 } } },
  timeline = { { at = 1, ticket = "ABC-1", kind = "reply", text = evil }, { at = 1, ticket = "ABC-1", kind = "subagent", text = evil } } }, 1))
check("escaped: no script tag", not has(eh, "<script") and not has(et, "<script"))
check("escaped: no img tag", not has(eh, "<img") and not has(et, "<img"))
check("escaped: no stray closing div", select(2, eh:gsub("</div>", "")) == select(2, eh:gsub("<div", ""))
  and not has(et, "</div>"))
check("escaped: quotes and ampersands", has(et, "&quot;alert(1)&quot;") and has(et, "&#39;&amp;"))
check("escape: the five characters", sessioncard.escape([[<>&"']]) == "&lt;&gt;&amp;&quot;&#39;")
check("CSS: a string", type(sessioncard.CSS) == "string" and has(sessioncard.CSS, ".timeline"))

check.done("sessioncard")
