-- The card's one timeline, "What happened?": the session's turns (workcard.view, from git) and each ticket's
-- timeline (sessioncard.view) merged, newest first. A turn shows its reply, then only what it has: how long it
-- took, its tests, its files, its commits; a turn that says nothing is left out. A reply no turn ended is a row of
-- its own; every other line (a lane started, a skill, a subagent, a lane done, Jira) is a thin marker between.
-- story.view does the merging, story.html only draws, every text escaped. It knows no Hammerspoon.

local panel = require("puppet.ui.panel")
local sessioncard = require("puppet.ui.sessioncard")
local workcard = require("puppet.ui.workcard")

local story = {}

local escape = sessioncard.escape
local counted = workcard.counted

-- How long after a turn's end its reply may come.
local REPLY_SLACK = 5

-- Each turn's reply: of `replies` (each with `at`), the latest that came between turn's start and REPLY_SLACK
-- seconds after its end (`now` for a turn with no end), each reply used once; the newest turns choose first.
-- Returns { [turn index] = reply } and the replies left, in their order.
function story.match(turns, replies, now)
  local byTurn, used = {}, {}
  local order = {}
  for i = 1, #turns do order[i] = i end
  table.sort(order, function(a, b)
    if turns[a].at ~= turns[b].at then return turns[a].at > turns[b].at end
    return a < b
  end)
  for _, i in ipairs(order) do
    local t = turns[i]
    local last = (t.endAt or now) + REPLY_SLACK
    local best
    for j, r in ipairs(replies) do
      if not used[j] and r.at >= t.at and r.at <= last and (not best or r.at > replies[best].at) then best = j end
    end
    if best then used[best], byTurn[i] = true, replies[best] end
  end
  local left = {}
  for j, r in ipairs(replies) do
    if not used[j] then left[#left + 1] = r end
  end
  return byTurn, left
end

-- Whether turn row `t` with reply `reply` has anything to say.
local function says(t, reply)
  return reply ~= nil or t.total > 0 or t.tests ~= nil or #t.commits > 0 or t.dot == "running"
end

-- The markers of timeline rows `rows` (newest first): every line but replies and tests (a turn shows its tests).
-- A lane started and the skill or subagent that started it, in the same second, are one marker.
local function markers(rows)
  local into, startedBy = {}, {}
  for i, r in ipairs(rows) do
    if r.kind == "phase" then
      for j, o in ipairs(rows) do
        if not into[j] and o.at == r.at and o.phase == r.phase and (o.kind == "skill" or o.kind == "subagent") then
          into[j], startedBy[i] = i, o.text
          break
        end
      end
    end
  end
  local out = {}
  for i, r in ipairs(rows) do
    if r.kind ~= "reply" and r.kind ~= "tests" and not into[i] then
      local text = startedBy[i] or (r.text ~= "" and r.text or nil)
      out[#out + 1] = { kind = "marker", at = r.at, time = r.time, label = r.label, text = text, verdict = r.verdict }
    end
  end
  return out
end

-- One ticket's list: the turns (each with its reply from `rows`), the replies left, the markers; newest first.
local function list(turns, rows, now)
  local replies = {}
  for _, r in ipairs(rows) do
    if r.kind == "reply" then replies[#replies + 1] = r end
  end
  local byTurn, left = story.match(turns, replies, now)
  local out, shown, commits = {}, 0, 0
  for i, t in ipairs(turns) do
    local reply = byTurn[i]
    if says(t, reply) then
      local row = { kind = "turn", reply = reply and reply.text }
      for k, x in pairs(t) do row[k] = x end
      out[#out + 1] = row
      shown, commits = shown + 1, commits + #t.commits
    end
  end
  for _, r in ipairs(left) do
    out[#out + 1] = { kind = "reply", at = r.at, time = r.time, text = r.text, reply = r.text }
    shown = shown + 1
  end
  for _, m in ipairs(markers(rows)) do out[#out + 1] = m end
  for i, r in ipairs(out) do r.n = i end
  table.sort(out, function(a, b) if a.at ~= b.at then return a.at > b.at end return a.n < b.n end)
  for _, r in ipairs(out) do r.n = nil end
  local summary = "Nothing yet"
  if shown > 0 then
    summary = counted(shown, "turn") .. (commits > 0 and " · " .. counted(commits, "commit") or "")
  elseif #out > 0 then
    summary = counted(#out, "line")
  end
  return out, summary
end

-- What the story shows for the session's view `session` (sessioncard.view, or nil) and git part `work`
-- (workcard.view, or nil) at time `now`: { tickets = { { key, rows, summary } } }, one list per ticket in the
-- header's order (the session's turns in each), or one list of turns with no tickets; nil when there are no tickets
-- and no turn says anything.
function story.view(session, work, now)
  local turns = work and work.turns or {}
  local v = { tickets = {} }
  if session then
    for _, t in ipairs(session.tickets) do
      local rows, summary = list(turns, t.rows, now)
      v.tickets[#v.tickets + 1] = { key = t.key or "-", keyed = true, rows = rows, summary = summary }
    end
    return v
  end
  local rows, summary = list(turns, {}, now)
  if #rows == 0 then return nil end
  v.tickets[1] = { rows = rows, summary = summary }
  return v
end

-- A turn's `<li>`: the time, its dot on the rail, then its reply, how long and its tests, the files (a pill that
-- opens to the paths), the commits; only what it has.
local function turnHtml(t)
  local body = {}
  if t.reply then body[#body + 1] = '<div class="reply">' .. escape(t.reply) .. "</div>" end
  -- A turn filled from the transcript (the hooks did not record it) says so, muted, after the rest of its head.
  local from = t.fromTranscript and '<span class="from">from the transcript</span>' or nil
  if t.head or t.tests or from then
    local parts = {}
    if t.head then parts[#parts + 1] = "<b>" .. escape(t.head) .. "</b>" end
    if t.tests then parts[#parts + 1] = '<span class="tests">' .. escape(t.tests) .. "</span>" end
    if from then parts[#parts + 1] = from end
    body[#body + 1] = '<div class="turnhead">' .. table.concat(parts, " · ") .. "</div>"
  end
  if t.total and t.total > 0 then
    local lis = {}
    for _, path in ipairs(t.files) do lis[#lis + 1] = workcard.item(path) end
    body[#body + 1] = '<details class="files"><summary><span class="chev">›</span>' .. escape(t.summary)
      .. "</summary><ul>" .. table.concat(lis) .. workcard.moreItem(t.more) .. "</ul></details>"
  end
  for _, c in ipairs(t.commits or {}) do
    body[#body + 1] = '<div class="commit"><code>' .. escape(c.hash) .. "</code> " .. escape(c.subject) .. "</div>"
  end
  -- A turn's end (empty while it has none) lets a step keep the turn it started in; a reply alone has none.
  local ends = t.kind == "turn" and ' data-end="' .. (t.endAt and string.format("%d", t.endAt) or "") .. '"' or ""
  return '<li data-at="' .. string.format("%d", t.at) .. '"' .. ends .. '><span class="at">' .. escape(t.time or "")
    .. '</span><span class="rail"><span class="pip ' .. (t.dot or "none") .. '"></span></span><div class="turnbody">'
    .. table.concat(body) .. "</div></li>"
end

-- A marker's `<li>`: a thin line, its time, label, verdict and text.
local function markerHtml(m)
  return '<li class="marker" data-at="' .. string.format("%d", m.at) .. '"><span class="at">' .. escape(m.time or "")
    .. '</span><span class="rail"></span><div class="markline"><span class="what">' .. escape(m.label) .. "</span>"
    .. (m.verdict and ' <span class="verdict">' .. escape(m.verdict) .. "</span>" or "")
    .. (m.text and ' · <span class="text">' .. escape(m.text) .. "</span>" or "") .. "</div></li>"
end

-- The story's panel for view `v`: each ticket's list (all but the first hidden, switched by Also through data-key)
-- and its summary, and the words a step with nothing in it shows.
function story.html(v)
  local sums, lists = {}, {}
  for i, t in ipairs(v.tickets) do
    local key = t.keyed and ' data-key="' .. escape(t.key) .. '"' .. (i > 1 and " hidden" or "") or ""
    local items = {}
    for _, r in ipairs(t.rows) do
      items[#items + 1] = r.kind == "marker" and markerHtml(r) or turnHtml(r)
    end
    sums[#sums + 1] = "<span" .. key .. ">" .. escape(t.summary) .. "</span>"
    lists[#lists + 1] = '<div class="storyticket"' .. key .. '><ol class="storylist">' .. table.concat(items)
      .. '</ol><p class="nolane">Nothing happened in this step.</p></div>'
  end
  return panel.html("story", "What happened?", table.concat(sums), table.concat(lists))
end

-- The story's panel holding only `text` (the transcript being read, or why it could not be).
function story.lineHtml(text)
  return panel.html("story", "What happened?", "", '<p class="line">' .. escape(text) .. "</p>")
end

-- The styles for the story, in the page's tokens (--accent, --faint) and workcard's colours (--ok, --off, --bad).
story.CSS = table.concat({
  ".storylist { list-style: none; padding: 0; margin: 0; }",
  ".storylist > li { display: grid; grid-template-columns: 44px 14px minmax(0, 1fr); gap: 0 10px; }",
  ".storylist .at { font-size: 12px; color: var(--muted); padding-top: 1px; }",
  ".storylist .rail { display: flex; flex-direction: column; align-items: center; }",
  ".storylist .rail::after { content: ''; flex: 1; width: 2px; background: var(--faint); }",
  ".storylist > li:last-child .rail::after { content: none; }",
  ".pip { width: 10px; height: 10px; border-radius: 50%; box-sizing: border-box; margin-top: 4px; flex: none; }",
  ".pip.running { border: 2px solid var(--off); } .pip.bad { background: var(--bad); }",
  ".pip.ok { background: var(--ok); } .pip.none { background: color-mix(in srgb, CanvasText 25%, transparent); }",
  ".turnbody { display: flex; flex-direction: column; align-items: flex-start; gap: 5px; padding-bottom: 14px;",
  " min-width: 0; } .turnbody > * { max-width: 100%; } .storylist > li:last-child .turnbody { padding-bottom: 0; }",
  ".story .reply { overflow-wrap: anywhere; } .story .tests, .story .from { color: var(--muted); }",
  -- A marker: one thin line between the turns, its label in the phase colour.
  ".storylist > li.marker { font-size: 12px; } .storylist > li.marker .at { font: 11px Menlo, monospace; }",
  ".markline { padding: 0 0 8px; color: var(--muted); overflow-wrap: anywhere; }",
  ".markline .what { font-weight: 600; color: var(--accent); }",
  ".story code { font: 12px Menlo, monospace; overflow-wrap: anywhere; }",
  ".story .files ul { list-style: none; padding: 0; margin: 0; } .story .more { color: var(--muted); }",
  ".story .files > summary { list-style: none; cursor: pointer; display: inline-flex; gap: 6px; padding: 2px 9px;",
  " border-radius: 4px; background: var(--pill-bg); color: var(--pill); font: 12px Menlo, monospace; }",
  ".story .files > summary::-webkit-details-marker { display: none; }",
  ".story .files > summary:hover { background: color-mix(in srgb, var(--ok) 24%, transparent); }",
  ".story .files .chev { display: inline-block; transition: transform 0.12s; }",
  ".story .files[open] > summary .chev { transform: rotate(90deg); }",
  ".story .files[open] ul { margin-top: 4px; padding: 5px 10px; border-radius: 4px; color: var(--ok-text);",
  " background: color-mix(in srgb, var(--ok-bg) 60%, transparent); }",
  ".story .commit { font: 12px Menlo, monospace; overflow-wrap: anywhere; } .commit code { color: var(--warn); }",
  -- A step picked (body.lane, set by the page's script): the rows outside it hidden, a word when none is left.
  ".storylist > li.out { display: none; } .nolane { display: none; color: var(--muted); margin: 0; }",
  "body.lane .storylist:not(:has(> li:not(.out))) + .nolane { display: block; }",
})

return story
