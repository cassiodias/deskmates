-- The session part of the card: what a session is working on, from its facts (model/facts.lua). sessioncard.view
-- turns them into what the card shows (the current ticket first, its Jira badge, the phase strip, NOW and the
-- timeline); sessioncard.html makes its two parts of the page, the header and the timeline, every text escaped.
-- It knows no Hammerspoon.

local panel = require("puppet.ui.panel")

local sessioncard = {}

local PHASES = { "plan", "dev", "review" }
local NAMES = { plan = "Plan", dev = "Dev", review = "Review" }

function sessioncard.escape(text)
  return (text:gsub("[&<>\"']", { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&#39;" }))
end
local escape = sessioncard.escape

local function clock(t) return t and os.date("%H:%M", t) or nil end

-- How long `seconds` lasted, in words: "<1 min", "12 min", "1 h 5 min".
function sessioncard.took(seconds)
  local minutes = math.floor(math.max(0, seconds) / 60)
  if minutes < 1 then return "<1 min" end
  if minutes < 60 then return minutes .. " min" end
  return math.floor(minutes / 60) .. " h " .. minutes % 60 .. " min"
end
local took = sessioncard.took

local function label(e)
  if e.kind == "phase" then return e.text end
  if e.kind == "jira" then return "Jira" end
  if e.kind == "tests" then return e.text == "failed" and "✗ tests" or "✓ tests" end
  if e.kind == "reply" then return "" end
  if e.kind == "done" then return "✓ " .. (e.phase or "") end
  return e.phase or ""
end

local function ticketView(key, t, timeline, now, isWorking)
  local v = { key = key ~= "-" and key or nil, strip = {}, rows = {} }
  if t.jira then v.jira = { status = t.jira.status, time = clock(t.jira.at) } end
  for _, p in ipairs(PHASES) do
    local entered = t.phases and t.phases[p]
    local step = { phase = p, time = clock(entered) }
    local ended = t.ends and t.ends[p]
    if ended then
      -- The lane finished: ✓, its span, and the verdict the agent wrote, if any.
      step.state, step.ended, step.verdict = "done", clock(ended.at), ended.verdict
    elseif p == t.phase then
      step.state = "current"
      -- Counted from the time shown; once the agent's turn is over, it ends at the last thing that happened.
      local from = entered or t.phaseAt
      if from and isWorking then step.took = took(now - from)
      elseif from and t.seen and t.seen > from then step.ended = clock(t.seen) end
    else
      step.state = entered and "reached" or "ahead"
    end
    v.strip[#v.strip + 1] = step
  end
  for _, e in ipairs(timeline) do
    if e.ticket == key then
      if e.kind == "reply" and not v.now then v.now = e.text end
      v.rows[#v.rows + 1] = { time = clock(e.at), label = label(e), text = e.kind == "phase" and "started" or e.text,
        phase = e.phase }
    end
  end
  v.summary = #v.rows == 0 and "Nothing yet" or #v.rows .. " line" .. (#v.rows == 1 and "" or "s")
  return v
end

-- What the card shows for facts `f` at time `now`, `isWorking` while the agent's turn runs: { current = key,
-- tickets = { ticket views } }, the current ticket first, then the others by when they were last worked on;
-- nil when there is nothing to show.
function sessioncard.view(f, now, isWorking)
  if not f or next(f.tickets) == nil then return nil end
  local keys = {}
  for key in pairs(f.tickets) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b)
    if a == f.current then return true end
    if b == f.current then return false end
    local sa, sb = f.tickets[a].seen or 0, f.tickets[b].seen or 0
    if sa ~= sb then return sa > sb end
    return a < b
  end)
  local v = { current = f.current, tickets = {} }
  for _, key in ipairs(keys) do v.tickets[#v.tickets + 1] = ticketView(key, f.tickets[key], f.timeline, now, isWorking) end
  return v
end

local function hidden(i) return i > 1 and " hidden" or "" end

-- The page's two parts for view `v`: the header (each ticket's key, badge, strip and NOW, and the Also choice)
-- and the activity panel, "What happened along the way?" (each ticket's rows and summary). Every ticket is there,
-- all but the first hidden; the page's script switches them (data-key) and filters rows by phase (data-phase).
function sessioncard.html(v)
  local head, rows, sums = { '<section class="session">' }, { '<section class="timelines">' }, {}
  if #v.tickets > 1 then
    local options = {}
    for _, t in ipairs(v.tickets) do
      local name = escape(t.key or "No ticket")
      options[#options + 1] = '<option value="' .. escape(t.key or "-") .. '">' .. name .. "</option>"
    end
    head[#head + 1] = '<div class="also-row"><span class="label">ALSO</span><select class="also">'
      .. table.concat(options) .. "</select></div>"
  end
  for i, t in ipairs(v.tickets) do
    local key = escape(t.key or "-")
    head[#head + 1] = '<div class="ticket" data-key="' .. key .. '"' .. hidden(i) .. ">"
    if t.key or t.jira then
      head[#head + 1] = '<div class="head">' .. (t.key and '<span class="key">' .. key .. "</span>" or "")
        .. (t.jira and '<span class="jira">' .. escape(t.jira.status)
          .. (t.jira.time and " <small>" .. t.jira.time .. "</small>" or "") .. "</span>" or "") .. "</div>"
    end
    local strip = {}
    for _, s in ipairs(t.strip) do
      strip[#strip + 1] = '<button class="phase ' .. s.state .. '" data-phase="' .. s.phase .. '"><span class="dot"></span>'
        .. NAMES[s.phase] .. "<small>" .. (s.time or "") .. (s.took and " · " .. escape(s.took) or "")
        .. (s.ended and " → " .. s.ended or "") .. (s.state == "done" and " ✓" or "") .. "</small>"
        .. (s.verdict and '<span class="verdict">' .. escape(s.verdict) .. "</span>" or "") .. "</button>"
    end
    head[#head + 1] = '<div class="strip">' .. table.concat(strip) .. "</div>"
    if t.now then head[#head + 1] = '<p class="now"><span class="label">NOW</span> ' .. escape(t.now) .. "</p>" end
    head[#head + 1] = "</div>"
    local items = {}
    for _, r in ipairs(t.rows) do
      items[#items + 1] = '<li data-phase="' .. (r.phase or "") .. '"><span class="time">' .. (r.time or "")
        .. '</span><span class="what">' .. escape(r.label) .. '</span><span class="text">' .. escape(r.text) .. "</span></li>"
    end
    sums[#sums + 1] = '<span data-key="' .. key .. '"' .. hidden(i) .. ">" .. escape(t.summary) .. "</span>"
    rows[#rows + 1] = '<ul class="timeline" data-key="' .. key .. '"' .. hidden(i) .. ">" .. table.concat(items) .. "</ul>"
  end
  head[#head + 1] = "</section>"
  rows[#rows + 1] = "</section>"
  return table.concat(head), panel.html("activity", "What happened along the way?", table.concat(sums), table.concat(rows))
end

-- The styles for the session part, in the page's tokens (--accent, --faint).
sessioncard.CSS = table.concat({
  ".session { margin-bottom: 8px; } .session ~ .label { padding-top: 8px; border-top: 1px solid var(--faint); }",
  ".ticket .head { display: flex; gap: 8px; align-items: baseline; }",
  ".key { font-size: 16px; font-weight: 700; }",
  ".jira { font-size: 11px; font-weight: 600; border-radius: 4px; padding: 1px 6px; color: var(--accent);",
  " background: color-mix(in srgb, var(--accent) 15%, transparent); } .jira small { opacity: 0.7; }",
  ".also-row { float: right; display: flex; gap: 6px; align-items: center; } .also { font: inherit; }",
  ".strip { display: flex; gap: 4px; margin: 8px 0 4px; }",
  ".phase { flex: 1; display: flex; flex-direction: column; align-items: flex-start; gap: 2px; background: none;",
  " border: 0; border-top: 2px solid var(--faint); padding: 6px 4px 2px; color: inherit; font: inherit; cursor: pointer; }",
  ".phase small { font-size: 10px; opacity: 0.6; min-height: 1em; }",
  ".phase .dot { width: 9px; height: 9px; border-radius: 50%; border: 2px solid var(--faint); margin-top: -12px; background: Canvas; }",
  ".phase.reached { border-top-color: var(--accent); } .phase.reached .dot { background: var(--accent); border-color: var(--accent); }",
  ".phase.current { border-top-color: var(--accent); font-weight: 600; }",
  ".phase.current .dot { border-color: var(--accent); box-shadow: 0 0 0 3px color-mix(in srgb, var(--accent) 30%, transparent); }",
  ".phase.on { background: var(--faint); border-radius: 4px; }",
  ".phase.done { border-top-color: var(--accent); } .phase.done .dot { background: var(--accent); border-color: var(--accent); }",
  ".verdict { font-size: 10px; font-weight: 700; border-radius: 4px; padding: 1px 5px; color: var(--accent);",
  " background: color-mix(in srgb, var(--accent) 15%, transparent); }",
  ".now { margin: 6px 0 0; } .now .label { display: inline; margin-right: 4px; color: var(--accent); opacity: 1; }",
  ".timeline { list-style: none; padding: 0; margin: 8px 0; }",
  ".timeline li { display: grid; grid-template-columns: 44px 64px 1fr; gap: 8px; padding: 3px 0;",
  " border-bottom: 1px solid var(--faint); } .timeline li.out { display: none; }",
  ".timeline .time { font: 12px Menlo, monospace; opacity: 0.6; } .timeline .what { font-weight: 600; color: var(--accent); }",
})

return sessioncard
