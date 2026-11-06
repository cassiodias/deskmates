-- The card's two git blocks, for a session in a git repo: did it change what the plan said (the plan's file map
-- beside what git says changed since the session's base; what changed, without a plan) and what each turn did.
-- workcard.view does the work (git's texts read and compared by model/actual.lua, rows, dots and words chosen,
-- lists cut at MAX_PATHS); workcard.html only draws, every text escaped. It knows no agent, and no Hammerspoon.

local actual = require("puppet.model.actual")
local facts = require("puppet.model.facts")
local planblocks = require("puppet.ui.planblocks")
local panel = require("puppet.ui.panel")
local sessioncard = require("puppet.ui.sessioncard")

local workcard = {}

local escape = sessioncard.escape

-- The most paths a list shows; the rest are counted ("and N more").
local MAX_PATHS = 200

local DID_NOT_ANSWER = "git did not answer"

-- The questions the plan block answers: with a plan's file map, and without one (or while that is not known).
local ASKS_PLAN = "Did it change what the plan said?"
local ASKS_CHANGED = "What changed?"

-- After a changed path no edit of the agent named (a shell command's write, or a change outside the session).
local UNSEEN = ' <span class="unseen">no edit seen</span>'

-- `n` and the word for it: "1 commit", "3 commits".
local function counted(n, word) return n .. " " .. word .. (n == 1 and "" or "s") end

-- The first MAX_PATHS items of `list`, and how many were left out.
local function capped(list)
  local out = {}
  for i = 1, math.min(#list, MAX_PATHS) do out[i] = list[i] end
  return out, #list - #out
end

-- Each kind of table row: its middle mark, the words a screen reader says for it, and its two cells for `path`
-- (a cell is { path, tint, unseen } or { say, tone }).
local KINDS = {
  matched = { mark = "=", label = "same file", cells = function(path, unseen)
    return { path = path }, { path = path, tint = "ok", unseen = unseen }
  end },
  missing = { mark = "←", label = "planned, not changed", cells = function(path)
    return { path = path, tint = "warn" }, { say = "not changed yet", tone = "warn" }
  end },
  unchecked = { mark = "?", label = "not checked", cells = function(path)
    return { path = path, tint = "neutral" }, { say = "not checked" }
  end },
  unplanned = { mark = "→", label = "not in the plan", cells = function(path, unseen)
    return { say = "not in the plan", tone = "off" }, { path = path, tint = "off", unseen = unseen }
  end },
}

-- Adds to `out` the rows of `kind` for `paths`: the first MAX_PATHS, then a "more" row counting the rest.
local function addRows(out, kind, paths, notSeen)
  local k = KINDS[kind]
  local shown, more = capped(paths)
  for _, path in ipairs(shown) do
    local left, right = k.cells(path, notSeen[path] or nil)
    out[#out + 1] = { kind = kind, mark = k.mark, label = k.label, left = left, right = right }
  end
  if more > 0 then out[#out + 1] = { kind = "more", more = more } end
end

-- The file map blocks lifted from the plan's markdown, or nil when it has none.
local function filemaps(plan)
  if not plan or type(plan.markdown) ~= "string" then return nil end
  local out = {}
  for _, block in ipairs(planblocks.lift(planblocks.parse(plan.markdown))) do
    if block.kind == "filemap" then out[#out + 1] = block end
  end
  return #out > 0 and out or nil
end

-- The number of commits in git's `rev-list --count` text (or a number), trimmed; nil when it is not one.
local function commitCount(raw)
  return tonumber(tostring(raw or ""):match("^%s*(%d+)%s*$"))
end

-- The plan block for facts `f`, git's answer `gitState` and `plan`: { heading, line, summary } while git reads or
-- when it cannot answer; otherwise { heading, summary, base, footer } and, with a plan's file map, `rows` (KINDS,
-- in order: matched, missing, unchecked, unplanned), or without one `list` ({ rows = { path, unseen }, more }).
local function actualView(f, gitState, plan)
  local maps = filemaps(plan)
  local heading = maps and ASKS_PLAN or ASKS_CHANGED
  gitState = gitState or { reading = true }
  local function only(line) return { heading = heading, line = line, summary = line } end
  if gitState.error then return only(gitState.error) end
  if gitState.reading then return only("Reading git…") end
  local commits = commitCount(gitState.commits)
  if not commits then return only(DID_NOT_ANSWER) end

  local c = actual.compare({
    planned = maps and actual.planned(maps, f.git.root, f.git.prefix) or nil,
    diff = actual.parseDiff(gitState.diff),
    untracked = actual.parseList(gitState.untracked),
    uncommitted = actual.parseList(gitState.uncommitted),
    dirtyAtStart = f.git.dirtyAtStart,
    seen = f.seen,
  })
  local out = { base = f.git.base:sub(1, 7),
    footer = counted(commits, "commit") .. ", " .. c.uncommitted .. " not committed." }
  if not c.hasPlan then
    out.heading = ASKS_CHANGED
    local list = {}
    for _, path in ipairs(c.changed) do list[#list + 1] = { path = path, unseen = c.notSeen[path] or nil } end
    local shown, more = capped(list)
    out.list = { rows = shown, more = more }
    local unseen = 0
    for _ in pairs(c.notSeen) do unseen = unseen + 1 end
    out.summary = #list == 0 and "Nothing changed"
      or #list .. " changed" .. (unseen > 0 and " · " .. unseen .. " no edit seen" or "")
    return out
  end
  out.heading, out.rows = ASKS_PLAN, {}
  -- The entries no rule can check are named apart: they are neither changed nor not changed.
  out.summary = #c.matched .. " of " .. (#c.matched + #c.missing) .. " planned changed"
    .. (#c.unchecked > 0 and " · " .. #c.unchecked .. " not checked" or "")
    .. (#c.unplanned > 0 and " · " .. #c.unplanned .. " not in the plan" or "")
  addRows(out.rows, "matched", c.matched, c.notSeen)
  addRows(out.rows, "missing", c.missing, {})
  addRows(out.rows, "unchecked", c.unchecked, {})
  addRows(out.rows, "unplanned", c.unplanned, c.notSeen)
  return out
end

-- A turn's tests in words: "tests passed (2 of 2)", "1 test failed (of 2)", "2 tests failed (of 3)", or
-- "tests ran 3" when none passed or failed (Codex counts only runs); nil when none ran.
local function testsText(t)
  local ran = math.max(t.ran, t.passed + t.failed)
  if ran == 0 then return nil end
  if t.failed > 0 then return counted(t.failed, "test") .. " failed (of " .. ran .. ")" end
  if t.passed > 0 then return "tests passed (" .. t.passed .. " of " .. ran .. ")" end
  return "tests ran " .. ran
end

-- A turn's dot: "running" (a ring) while it runs; else "bad" when a test failed, "ok" when tests passed, or "none".
local function dot(t, isRunning)
  if isRunning then return "running" end
  if t.failed > 0 then return "bad" end
  if t.passed > 0 then return "ok" end
  return "none"
end

-- One turn's row: { time, dot, head, tests, summary, files, more, total, commits } (workcard.view adds its phase); summary is the files in words. head is "Working now" for an open turn
-- when `isRunning`, how long it took when it ended, else "No end recorded".
-- The lane a turn started in: the phase of the newest activity at or before `at` that names one (a "done" too:
-- the work right after a lane closes belongs to it); nil before any.
local function laneAt(timeline, at)
  local best
  for _, e in ipairs(timeline or {}) do
    if e.phase and e.at <= at and (not best or e.at >= best.at) then best = e end
  end
  return best and best.phase
end

local function turnRow(t, isRunning)
  isRunning = isRunning and not t.endAt
  local files, more = capped(t.files)
  local head = isRunning and "Working now" or (t.endAt and sessioncard.took(t.endAt - t.at)) or "No end recorded"
  return { time = os.date("%H:%M", t.at), dot = dot(t.tests, isRunning), head = head, tests = testsText(t.tests),
    summary = #t.files == 0 and "No files edited." or counted(#t.files, "file") .. "…",
    files = files, more = more, total = #t.files, commits = t.commits }
end

-- What the two blocks show for facts `f`, git's answer `gitState` ({ reading = true }, { error = text }, or
-- terminals/git.lua's result) and `plan` (model/plans.lua's shape, or nil): { actual = actualView, turns = { turn
-- rows, newest first }, turnsSummary = "4 turns · 2 commits" }; nil when the facts know no git base. Only the
-- newest turn, open while the session `isWorking`, is working now.
function workcard.view(f, gitState, plan, isWorking)
  if not facts.hasGit(f) then return nil end
  local turns = {}
  local commits = 0
  for i, t in ipairs(f.turns or {}) do
    turns[#turns + 1] = turnRow(t, i == 1 and isWorking == true)
    turns[#turns].phase = laneAt(f.timeline, t.at)
    commits = commits + #t.commits
  end
  return { actual = actualView(f, gitState, plan), turns = turns,
    turnsSummary = counted(#turns, "turn") .. (commits > 0 and " · " .. counted(commits, "commit") or "") }
end

-- One path's `<li>`, escaped, tagged when `unseen`.
local function item(path, unseen)
  return "<li><code>" .. escape(path) .. "</code>" .. (unseen and UNSEEN or "") .. "</li>"
end

-- The `<li>` saying how many paths were left out; nothing when none were.
local function moreItem(more)
  return more > 0 and '<li class="more">and ' .. more .. " more</li>" or ""
end

-- One table cell: a path on its tint (tagged when unseen), or muted words in their tone.
local function cell(c)
  if c.path then
    return "<td" .. (c.tint and ' class="tint-' .. c.tint .. '"' or "") .. "><code>" .. escape(c.path) .. "</code>"
      .. (c.unseen and UNSEEN or "") .. "</td>"
  end
  return '<td class="say' .. (c.tone and " say-" .. c.tone or "") .. '">' .. escape(c.say) .. "</td>"
end

-- The plan's paths beside git's, one row per path, a mark between (with words for a screen reader).
local function tableHtml(rows)
  local out = { '<table class="pva"><thead><tr><th>The plan said</th><th></th><th>It changed</th></tr></thead><tbody>' }
  for _, r in ipairs(rows) do
    if r.kind == "more" then
      out[#out + 1] = '<tr class="more"><td colspan="3">and ' .. r.more .. " more</td></tr>"
    else
      out[#out + 1] = '<tr class="' .. r.kind .. '">' .. cell(r.left) .. '<td class="mark"><span aria-hidden="true">'
        .. r.mark .. '</span><span class="vh">' .. escape(r.label) .. "</span></td>" .. cell(r.right) .. "</tr>"
    end
  end
  out[#out + 1] = "</tbody></table>"
  return table.concat(out)
end

-- The plan block's panel: its question and summary, then one line, or what it shows (the table or the list) and
-- the footer.
local function actualHtml(a)
  local out = {}
  if a.line then
    out[#out + 1] = '<p class="line">' .. escape(a.line) .. "</p>"
  else
    local base = "<code>" .. escape(a.base) .. "</code>"
    if a.rows then
      out[#out + 1] = '<p class="explain">Left, the files the plan named. Right, what git shows changed since ' .. base
        .. ". A gap on either side is the answer.</p>" .. tableHtml(a.rows)
    else
      local lis = {}
      for _, r in ipairs(a.list.rows) do lis[#lis + 1] = item(r.path, r.unseen) end
      out[#out + 1] = '<p class="explain">What git shows changed since ' .. base .. '.</p><ul class="changed">'
        .. table.concat(lis) .. moreItem(a.list.more) .. "</ul>"
    end
    out[#out + 1] = '<p class="foot">' .. escape(a.footer) .. "</p>"
  end
  return panel.html("actual", a.heading, escape(a.summary),
    table.concat(out) .. '<p class="wholesession">The whole session, not only the lane picked.</p>')
end

-- One turn's `<li>`: the time, its dot on the rail, then how long and its tests, the files (a pill that opens to
-- the paths), the commits.
local function turnHtml(t)
  local files
  if t.total == 0 then
    files = '<div class="nofiles">' .. escape(t.summary) .. "</div>"
  else
    local lis = {}
    for _, path in ipairs(t.files) do lis[#lis + 1] = item(path) end
    files = '<details class="files"><summary><span class="chev">›</span>' .. escape(t.summary) .. "</summary><ul>"
      .. table.concat(lis) .. moreItem(t.more) .. "</ul></details>"
  end
  local commits = {}
  for _, c in ipairs(t.commits) do
    commits[#commits + 1] = '<div class="commit"><code>' .. escape(c.hash) .. "</code> " .. escape(c.subject) .. "</div>"
  end
  return '<li' .. (t.phase and ' data-phase="' .. t.phase .. '"' or "") .. '><span class="at">' .. t.time .. '</span><span class="rail"><span class="pip ' .. t.dot .. '"></span></span>'
    .. '<div class="turnbody"><div class="turnhead"><b>' .. escape(t.head) .. "</b>"
    .. (t.tests and '<span class="tests"> · ' .. escape(t.tests) .. "</span>" or "") .. "</div>" .. files
    .. table.concat(commits) .. "</div></li>"
end

-- The two panels for view `v` (workcard.view): the plan block, then the turns when there are any.
function workcard.html(v)
  local out = { actualHtml(v.actual) }
  if #v.turns > 0 then
    local rowsHtml = {}
    for _, t in ipairs(v.turns) do rowsHtml[#rowsHtml + 1] = turnHtml(t) end
    out[#out + 1] = panel.html("turns", "What did each turn do?", escape(v.turnsSummary),
      '<ol class="turnlist">' .. table.concat(rowsHtml) .. '</ol><p class="nolane">No turns in this lane.</p>')
  end
  return table.concat(out)
end

-- The styles for the two blocks: their colours (light, then dark on a dark page), and the page's --faint.
workcard.CSS = table.concat({
  ":root { --ok: #1A7F37; --ok-text: #116329; --ok-bg: rgba(26,127,55,0.10); --pill: #116329;",
  " --pill-bg: rgba(26,127,55,0.14); --warn: #9A6700; --warn-text: #7D5400; --warn-bg: rgba(154,103,0,0.10); --off: #4A55C8;",
  " --off-bg: rgba(74,85,200,0.10); --bad: #CF222E; --muted: color-mix(in srgb, CanvasText 60%, transparent); }",
  "@media (prefers-color-scheme: dark) { :root { --ok: #3FB950; --ok-text: #C8FFC0; --ok-bg: rgba(63,185,80,0.12);",
  " --pill: #8FD18B; --pill-bg: rgba(63,185,80,0.16); --warn: #F2C14E; --warn-text: #F5D88A; --warn-bg: rgba(242,193,78,0.10);",
  " --off: #9DA6F5; --off-bg: rgba(157,166,245,0.10); --bad: #E5534B; } }",
  ".actual p { margin: 0 0 8px; color: var(--muted); } .actual .foot { font-size: 12px; margin: 8px 0 0; }",
  ".actual code, .turns code { font: 12px Menlo, monospace; overflow-wrap: anywhere; }",
  ".vh { position: absolute; width: 1px; height: 1px; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }",
  ".pva { width: 100%; table-layout: fixed; border-collapse: separate; border-spacing: 0;",
  " border: 1px solid var(--faint); border-radius: 8px; overflow: hidden; }",
  ".pva th, .pva td { border: 0; border-top: 1px solid var(--faint); padding: 6px 10px; text-align: left;",
  " vertical-align: top; overflow-wrap: anywhere; }",
  ".pva th { border-top: 0; font-weight: 600; background: color-mix(in srgb, CanvasText 5%, transparent); }",
  ".pva th:nth-child(2) { width: 28px; padding: 0; } .pva .mark { text-align: center; padding: 6px 0; font-weight: 700; }",
  ".pva .matched .mark { color: var(--ok); } .pva .missing .mark { color: var(--warn); }",
  ".pva .unchecked .mark { color: var(--muted); } .pva .unplanned .mark { color: var(--off); }",
  ".tint-ok { background: var(--ok-bg); color: var(--ok-text); }",
  ".tint-warn { background: var(--warn-bg); color: var(--warn-text); }",
  ".tint-off { background: var(--off-bg); color: var(--off); }",
  ".tint-neutral { background: color-mix(in srgb, CanvasText 6%, transparent); }",
  ".pva .say, .pva .more td { color: var(--muted); }",
  ".pva .say-warn { color: var(--warn); }",
  ".pva .say-off { color: var(--off); }",
  ".unseen { font: 11px -apple-system, sans-serif; color: var(--muted); margin-left: 4px; }",
  ".actual .changed, .turns ul { list-style: none; padding: 0; margin: 0; } .actual .changed li { padding: 1px 0; }",
  ".actual .more, .turns .more { color: var(--muted); }",
  ".turnlist { list-style: none; padding: 0; margin: 0; }",
  ".turnlist > li { display: grid; grid-template-columns: 44px 14px minmax(0, 1fr); gap: 0 10px; }",
  ".turnlist .at { font-size: 12px; color: var(--muted); padding-top: 1px; }",
  ".turnlist .rail { display: flex; flex-direction: column; align-items: center; }",
  ".turnlist .rail::after { content: ''; flex: 1; width: 2px; background: var(--faint); }",
  ".turnlist > li:last-child .rail::after { content: none; }",
  ".pip { width: 10px; height: 10px; border-radius: 50%; box-sizing: border-box; margin-top: 4px; flex: none; }",
  ".pip.running { border: 2px solid var(--off); } .pip.bad { background: var(--bad); }",
  ".pip.ok { background: var(--ok); } .pip.none { background: color-mix(in srgb, CanvasText 25%, transparent); }",
  ".turnbody { display: flex; flex-direction: column; align-items: flex-start; gap: 5px; padding-bottom: 14px;",
  " min-width: 0; } .turnbody > * { max-width: 100%; } .turnlist > li:last-child .turnbody { padding-bottom: 0; }",
  ".turns .tests, .turns .nofiles { color: var(--muted); }",
  -- A lane picked (body.lane, set by the page's script): the turns outside it hidden, a word when none is left,
  -- and the plan block saying it does not follow the lane.
  ".turnlist > li.out { display: none; } .nolane, .wholesession { display: none; color: var(--muted); }",
  "body.lane .turnlist:not(:has(> li:not(.out))) + .nolane { display: block; } body.lane .wholesession { display: block; }",
  ".turns .files > summary { list-style: none; cursor: pointer; display: inline-flex; gap: 6px; padding: 2px 9px;",
  " border-radius: 4px; background: var(--pill-bg); color: var(--pill); font: 12px Menlo, monospace; }",
  ".turns .files > summary::-webkit-details-marker { display: none; }",
  ".turns .files > summary:hover { background: color-mix(in srgb, var(--ok) 24%, transparent); }",
  ".turns .files .chev { display: inline-block; transition: transform 0.12s; }",
  ".turns .files[open] > summary .chev { transform: rotate(90deg); }",
  ".turns .files[open] ul { margin-top: 4px; padding: 5px 10px; border-radius: 4px; color: var(--ok-text);",
  " background: color-mix(in srgb, var(--ok-bg) 60%, transparent); }",
  ".turns .commit { font: 12px Menlo, monospace; overflow-wrap: anywhere; } .commit code { color: var(--warn); }",
})

return workcard
