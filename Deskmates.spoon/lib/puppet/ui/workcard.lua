-- The card's git part, for a session in a git repo: did it change what the plan said (the plan's file map beside
-- what git says changed since the session's base; what changed, without a plan), and what each turn did, for the
-- story (ui/story.lua draws the turns). workcard.view does the work (git's texts read and compared by
-- model/actual.lua, rows, dots and words chosen, lists cut at MAX_PATHS); workcard.html only draws the plan block,
-- every text escaped. It knows no agent, and no Hammerspoon.

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
-- The paths a session is known to have touched: those its hooks saw it edit, and those its own commits name.
local function seenWith(seen, committed)
  local all = {}
  for path in pairs(seen or {}) do all[path] = true end
  for _, path in ipairs(committed or {}) do all[path] = true end
  return all
end

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
    seen = seenWith(f.seen, actual.parseList(gitState.committed)),
  })
  local out = { base = f.git.base:sub(1, 7), baseFromTranscript = f.git.fromTranscript == true or nil,
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

-- One turn's row: { at, endAt, time, dot, head, tests, summary, files, more, total, commits }; at is its start (the
-- page keeps it while a step picked on the strip covers it), endAt its end (its reply came by then), summary the
-- files in words (nil for none). head is "Working now" for an open turn when `isRunning`, how long it took when it
-- ended (nil under a minute: it says nothing), else "No end recorded".
local function turnRow(t, isRunning)
  isRunning = isRunning and not t.endAt
  local files, more = capped(t.files)
  local head
  if isRunning then head = "Working now"
  elseif not t.endAt then head = "No end recorded"
  elseif t.endAt - t.at >= 60 then head = sessioncard.took(t.endAt - t.at) end
  return { at = t.at, endAt = t.endAt, time = os.date("%H:%M", t.at), dot = dot(t.tests, isRunning), head = head,
    tests = testsText(t.tests), summary = #t.files > 0 and counted(#t.files, "file") .. "…" or nil,
    files = files, more = more, total = #t.files, commits = t.commits, fromTranscript = t.fromTranscript == true or nil }
end

-- What the git part shows for facts `f`, git's answer `gitState` ({ reading = true }, { error = text }, or
-- terminals/git.lua's result), `plan` (model/plans.lua's shape, or nil) and the branch's PR in one line (`prLine`,
-- terminals/pr.lua's, or nil): { actual = actualView, turns = { turn rows, newest first }, pr }; nil when the facts
-- know no git base. Only the newest turn, open while the session `isWorking`, is working now.
function workcard.view(f, gitState, plan, isWorking, prLine)
  if not facts.hasGit(f) then return nil end
  local turns = {}
  for i, t in ipairs(f.turns or {}) do turns[#turns + 1] = turnRow(t, i == 1 and isWorking == true) end
  return { actual = actualView(f, gitState, plan), turns = turns, pr = prLine }
end

workcard.counted = counted

-- One path's `<li>`, escaped, tagged when `unseen`.
local function item(path, unseen)
  return "<li><code>" .. escape(path) .. "</code>" .. (unseen and UNSEEN or "") .. "</li>"
end
workcard.item = item

-- The `<li>` saying how many paths were left out; nothing when none were.
local function moreItem(more)
  return more > 0 and '<li class="more">and ' .. more .. " more</li>" or ""
end
workcard.moreItem = moreItem

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
    -- A base read from the transcript (the session ran before Deskmates watched) says so.
    local base = "<code>" .. escape(a.base) .. "</code>" .. (a.baseFromTranscript and " (read from the transcript)" or "")
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
  return panel.html("actual", a.heading, escape(a.summary), table.concat(out))
end

-- The plan block's panel for view `v` (workcard.view), then the PR's line when there is one; the turns are drawn
-- in the story (ui/story.lua).
function workcard.html(v)
  return actualHtml(v.actual) .. (v.pr and '<p class="pr">' .. escape(v.pr) .. "</p>" or "")
end

-- The styles for the plan block, and the colours the story shares (light, then dark on a dark page), with the
-- page's --faint.
workcard.CSS = table.concat({
  ":root { --ok: #1A7F37; --ok-text: #116329; --ok-bg: rgba(26,127,55,0.10); --pill: #116329;",
  " --pill-bg: rgba(26,127,55,0.14); --warn: #9A6700; --warn-text: #7D5400; --warn-bg: rgba(154,103,0,0.10); --off: #4A55C8;",
  " --off-bg: rgba(74,85,200,0.10); --bad: #CF222E; --muted: color-mix(in srgb, CanvasText 60%, transparent); }",
  "@media (prefers-color-scheme: dark) { :root { --ok: #3FB950; --ok-text: #C8FFC0; --ok-bg: rgba(63,185,80,0.12);",
  " --pill: #8FD18B; --pill-bg: rgba(63,185,80,0.16); --warn: #F2C14E; --warn-text: #F5D88A; --warn-bg: rgba(242,193,78,0.10);",
  " --off: #9DA6F5; --off-bg: rgba(157,166,245,0.10); --bad: #E5534B; } }",
  ".actual p { margin: 0 0 8px; color: var(--muted); } .actual .foot { font-size: 12px; margin: 8px 0 0; }",
  ".actual code { font: 12px Menlo, monospace; overflow-wrap: anywhere; }",
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
  ".actual .changed { list-style: none; padding: 0; margin: 0; } .actual .changed li { padding: 1px 0; }",
  ".actual .more { color: var(--muted); }",
  ".result .pr { margin: 6px 2px 0; font-size: 12px; color: var(--muted); }",
})

return workcard
