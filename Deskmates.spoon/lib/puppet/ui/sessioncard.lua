-- The session part of the card: what a session is working on, from its facts (model/facts.lua). sessioncard.view
-- turns them into what the card shows (the current ticket first, its Jira badge, the phase strip, NOW, and each
-- ticket's timeline rows for the story, ui/story.lua); sessioncard.html makes the header, every text escaped, the
-- step picked marked. It knows no Hammerspoon.

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

-- A timeline line's label: the lane started, the phase of a skill or subagent (its kind when it names none), a
-- lane's end (✓), Jira, tests; nothing for a reply.
local function label(e)
  if e.kind == "phase" then return (NAMES[e.text] or e.text) .. " started" end
  if e.kind == "jira" then return "Jira" end
  if e.kind == "tests" then return e.text == "failed" and "✗ tests" or "✓ tests" end
  if e.kind == "reply" then return "" end
  if e.kind == "done" then return "✓" .. (e.phase and " " .. NAMES[e.phase] or "") end
  if NAMES[e.phase] then return NAMES[e.phase] end
  return (e.kind:gsub("^%l", string.upper))
end

-- The verdict of ticket `t`'s step that a "done" line `e` ended, if any.
local function verdictOf(t, e)
  if e.kind ~= "done" then return nil end
  for _, p in ipairs(t.passes or {}) do
    if p.phase == e.phase and p.endAt == e.at and p.verdict then return p.verdict end
  end
  return nil
end

-- What the strip says under it once a ticket has steps: where they come from.
sessioncard.SOURCE = "Steps come from the names of the agent's skills and subagents: plan or brainstorm is Plan; "
  .. "build, implement, execute, debug or dev is Dev; review, test, verify or QA is Review."

-- The strip: ticket `t`'s passes in the order they happened, each { phase, time, ended, state, took, verdict, by,
-- from, to } (from and to: its start and the next one's, what the page filters by). A pass with an end is done; the
-- last one still open, in the ticket's phase, is current (zero-length steps after it, an end whose start was missed
-- or a parallel subagent's, do not stop it); any other is reached, up to the next start. Plan comes
-- first, ahead, when the steps do not start with it; with no steps, the three phases are ahead.
local function strip(t, now, isWorking)
  local passes, out = t.passes or {}, {}
  local current
  for i = #passes, 1, -1 do
    local p = passes[i]
    if not p.endAt then
      if p.phase == t.phase then current = i end
      break
    end
    if p.endAt ~= p.at then break end
  end
  for i, p in ipairs(passes) do
    local nextAt = passes[i + 1] and passes[i + 1].at
    local step = { phase = p.phase, time = clock(p.at), by = p.by, verdict = p.verdict, from = p.at, to = nextAt }
    if p.endAt then
      -- The step finished: ✓, its span, and the verdict the agent wrote, if any.
      step.state, step.ended = "done", clock(p.endAt)
    elseif i == current then
      -- Counted from its start; once the agent's turn is over, it ends at the last thing that happened.
      step.state = "current"
      if isWorking then step.took = took(now - p.at)
      elseif t.seen and t.seen > p.at then step.ended = clock(t.seen) end
    else
      step.state, step.ended = "reached", clock(nextAt)
    end
    out[#out + 1] = step
  end
  if #out == 0 then
    for _, p in ipairs(PHASES) do out[#out + 1] = { phase = p, state = "ahead" } end
  elseif out[1].phase ~= "plan" then
    table.insert(out, 1, { phase = "plan", state = "ahead" })
  end
  return out
end

local function ticketView(key, t, timeline, now, isWorking)
  local v = { key = key ~= "-" and key or nil, strip = strip(t, now, isWorking), rows = {} }
  if t.jira then v.jira = { status = t.jira.status, time = clock(t.jira.at) } end
  if t.passes and #t.passes > 0 then v.source = sessioncard.SOURCE end
  for _, e in ipairs(timeline) do
    if e.ticket == key then
      if e.kind == "reply" and not v.now then v.now = e.text end
      v.rows[#v.rows + 1] = { at = e.at, time = clock(e.at), kind = e.kind, label = label(e),
        text = e.kind == "phase" and "" or e.text, phase = e.phase, verdict = verdictOf(t, e) }
    end
  end
  return v
end

-- What the card shows for facts `f` at time `now`, `isWorking` while the agent's turn runs: { current = key,
-- tickets = { { key, jira, strip, source, now, rows } } }, rows (each { at, time, kind, label, text, phase,
-- verdict }) newest first, the current ticket first, then the others by when they were last worked on;
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

-- The step of `strip` drawn picked (its index), nil for none: the reader's own pick `kept` (a step's start, or
-- "none") while a step starts then; else the current step; else the newest one not ahead.
function sessioncard.pick(strip, kept)
  if kept == "none" then return nil end
  if kept then
    for i, s in ipairs(strip) do if s.from == kept then return i end end
  end
  local newest
  for i, s in ipairs(strip) do
    if s.state == "current" then return i end
    if s.state ~= "ahead" then newest = i end
  end
  return newest
end

-- A page message "step:<start>" (digits only) or "step:none": the step the reader picked, as its start, or
-- "none"; nil for anything else.
function sessioncard.stepMessage(body)
  if type(body) ~= "string" then return nil end
  if body == "step:none" then return "none" end
  local digits = body:match("^step:(%d+)$")
  if not digits or #digits > 15 then return nil end
  return tonumber(digits)
end

-- The header for view `v`: each ticket's key, badge, strip and NOW, and the Also choice. Every ticket is there,
-- all but the first hidden; the page's script switches them (data-key). On each strip the step sessioncard.pick
-- gives for `kept` is drawn picked (class on); the page filters the story by it (data-from, data-to).
function sessioncard.html(v, kept)
  local head = { '<section class="session">' }
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
    local picked = sessioncard.pick(t.strip, kept)
    local steps = {}
    for n, s in ipairs(t.strip) do
      steps[#steps + 1] = '<button class="phase ' .. s.state .. (n == picked and " on" or "") .. '" data-phase="' .. s.phase .. '"'
        .. (s.from and ' data-from="' .. string.format("%d", s.from) .. '"' or "")
        .. (s.to and ' data-to="' .. string.format("%d", s.to) .. '"' or "")
        .. (s.by and ' title="' .. escape(s.by) .. '"' or "") .. '><span class="dot"></span>'
        .. NAMES[s.phase] .. "<small>" .. (s.time or "") .. (s.took and " · " .. escape(s.took) or "")
        .. (s.ended and " → " .. s.ended or "") .. (s.state == "done" and " ✓" or "") .. "</small>"
        .. (s.by and '<span class="by">' .. escape(s.by) .. "</span>" or "")
        .. (s.verdict and '<span class="verdict">' .. escape(s.verdict) .. "</span>" or "") .. "</button>"
    end
    head[#head + 1] = '<div class="strip">' .. table.concat(steps) .. "</div>"
    if t.source then head[#head + 1] = '<p class="source">' .. escape(t.source) .. "</p>" end
    if t.now then head[#head + 1] = '<p class="now"><span class="label">NOW</span> ' .. escape(t.now) .. "</p>" end
    head[#head + 1] = "</div>"
  end
  head[#head + 1] = "</section>"
  return table.concat(head)
end

-- The styles for the session part, in the page's tokens (--accent, --faint).
sessioncard.CSS = table.concat({
  ".session { margin-bottom: 8px; } .session ~ .label { padding-top: 8px; border-top: 1px solid var(--faint); }",
  ".ticket .head { display: flex; gap: 8px; align-items: baseline; }",
  ".key { font-size: 16px; font-weight: 700; }",
  ".jira { font-size: 11px; font-weight: 600; border-radius: 4px; padding: 1px 6px; color: var(--accent);",
  " background: color-mix(in srgb, var(--accent) 15%, transparent); } .jira small { opacity: 0.7; }",
  ".also-row { float: right; display: flex; gap: 6px; align-items: center; } .also { font: inherit; }",
  -- Scrolling sideways clips what pokes out of the box: the padding keeps the dots above the line (and the
  -- current one's ring) inside it.
  ".strip { display: flex; gap: 4px; margin: 0 0 4px; padding-top: 8px; overflow-x: auto; overflow-y: hidden; }",
  ".phase { flex: 1 0 104px; min-width: 0; display: flex; flex-direction: column; align-items: flex-start; gap: 2px;",
  " background: none; border: 0; border-top: 2px solid var(--faint); padding: 6px 4px 2px; color: inherit; font: inherit;",
  " cursor: pointer; text-align: left; }",
  ".phase > * { max-width: 100%; white-space: nowrap; }",
  ".phase small { font-size: 10px; opacity: 0.6; min-height: 1em; }",
  ".phase .verdict { overflow: hidden; text-overflow: ellipsis; }",
  ".phase .by { font-size: 10px; font-weight: 400; opacity: 0.6; overflow: hidden; text-overflow: ellipsis; }",
  ".source { margin: 2px 0 0; font-size: 10px; opacity: 0.6; }",
  ".phase .dot { width: 9px; height: 9px; border-radius: 50%; border: 2px solid var(--faint); margin-top: -12px; background: Canvas; }",
  ".phase.reached { border-top-color: var(--accent); } .phase.reached .dot { background: var(--accent); border-color: var(--accent); }",
  ".phase.current { border-top-color: var(--accent); font-weight: 600; }",
  ".phase.current .dot { border-color: var(--accent); box-shadow: 0 0 0 3px color-mix(in srgb, var(--accent) 30%, transparent); }",
  ".phase.on { background: var(--faint); border-radius: 4px; }",
  ".phase.done { border-top-color: var(--accent); } .phase.done .dot { background: var(--accent); border-color: var(--accent); }",
  ".verdict { font-size: 10px; font-weight: 700; border-radius: 4px; padding: 1px 5px; color: var(--accent);",
  " background: color-mix(in srgb, var(--accent) 15%, transparent); }",
  ".now { margin: 6px 0 0; } .now .label { display: inline; margin-right: 4px; color: var(--accent); opacity: 1; }",
})

return sessioncard
