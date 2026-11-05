-- The card's two git blocks, for a session in a git repo: plan vs actual (the plan's file map against what git
-- says changed since the session's base) and its turns. workcard.view does the work (git's texts read and compared
-- by model/actual.lua, rows shaped, lists cut at MAX_PATHS); workcard.html only draws, every text escaped. It
-- knows no agent, and no Hammerspoon.

local actual = require("puppet.model.actual")
local facts = require("puppet.model.facts")
local planblocks = require("puppet.ui.planblocks")
local sessioncard = require("puppet.ui.sessioncard")

local workcard = {}

local escape = sessioncard.escape

-- The most paths a list shows; the rest are counted ("and N more").
local MAX_PATHS = 200

local DID_NOT_ANSWER = "git did not answer"

-- `n` and the word for it: "1 commit", "3 commits".
local function counted(n, word) return n .. " " .. word .. (n == 1 and "" or "s") end

-- The first MAX_PATHS items of `list`, and how many were left out.
local function capped(list)
  local out = {}
  for i = 1, math.min(#list, MAX_PATHS) do out[i] = list[i] end
  return out, #list - #out
end

-- A list of the block: { mark, title, rows, more, total } from rows { path, unseen, unchecked }.
local function list(mark, title, rows)
  local shown, more = capped(rows)
  return { mark = mark, title = title, rows = shown, more = more, total = #rows }
end

-- The paths of `paths` as rows, each one no hook of the session named marked `unseen`.
local function rows(paths, notSeen)
  local out = {}
  for _, path in ipairs(paths) do out[#out + 1] = { path = path, unseen = notSeen[path] or nil } end
  return out
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

-- Plan vs actual for facts `f`, git's answer `gitState` and `plan`: { line } while git reads or when it cannot
-- answer; otherwise { header, lists }: ✓ ○ ＋ with a plan's file map, one unmarked "changed" list without.
local function actualView(f, gitState, plan)
  gitState = gitState or { reading = true }
  if gitState.error then return { line = gitState.error } end
  if gitState.reading then return { line = "reading git…" } end
  local commits = commitCount(gitState.commits)
  if not commits then return { line = DID_NOT_ANSWER } end

  local maps = filemaps(plan)
  local c = actual.compare({
    planned = maps and actual.planned(maps, f.git.root) or nil,
    diff = actual.parseDiff(gitState.diff),
    untracked = actual.parseList(gitState.untracked),
    uncommitted = actual.parseList(gitState.uncommitted),
    dirtyAtStart = f.git.dirtyAtStart,
    seen = f.seen,
  })
  local out = { header = "since " .. f.git.base:sub(1, 7) .. " · " .. counted(commits, "commit") .. " · "
    .. c.uncommitted .. " uncommitted" }
  if not c.hasPlan then
    out.lists = { list(nil, "changed", rows(c.changed, c.notSeen)) }
    return out
  end
  local notChanged = rows(c.missing, {})
  for _, entry in ipairs(c.unchecked) do notChanged[#notChanged + 1] = { path = entry, unchecked = true } end
  out.lists = {
    list("✓", "planned and changed", rows(c.matched, c.notSeen)),
    list("○", "planned, not changed", notChanged),
    list("＋", "changed, not planned", rows(c.unplanned, c.notSeen)),
  }
  return out
end

-- A turn's tests in words: "ran 2 · ✓ 1 · ✗ 1", or "ran 2" when none passed or failed; nil when none ran.
local function testsText(t)
  if t.ran == 0 and t.passed == 0 and t.failed == 0 then return nil end
  local text = "ran " .. t.ran
  if t.passed == 0 and t.failed == 0 then return text end
  return text .. " · ✓ " .. t.passed .. " · ✗ " .. t.failed
end

-- One turn's row: { time, took, files, more, total, tests, commits }. took is how long it took; for an open turn
-- "running" when `isRunning`, else nil (a turn left open says only when it started).
local function turnRow(t, isRunning)
  local files, more = capped(t.files)
  local took = t.endAt and sessioncard.took(t.endAt - t.at) or (isRunning and "running" or nil)
  return { time = os.date("%H:%M", t.at), took = took,
    files = files, more = more, total = #t.files, tests = testsText(t.tests), commits = t.commits }
end

-- What the two blocks show for facts `f`, git's answer `gitState` ({ reading = true }, { error = text }, or
-- terminals/git.lua's result) and `plan` (model/plans.lua's shape, or nil): { actual = actualView, turns = { turn
-- rows, newest first } }; nil when the facts know no git base. Only the newest turn, open while the session
-- `isWorking`, says "running".
function workcard.view(f, gitState, plan, isWorking)
  if not facts.hasGit(f) then return nil end
  local turns = {}
  for i, t in ipairs(f.turns or {}) do turns[#turns + 1] = turnRow(t, i == 1 and isWorking == true) end
  return { actual = actualView(f, gitState, plan), turns = turns }
end

-- One path's `<li>`, escaped, with the labels in `tail` (already HTML) after it.
local function item(path, tail)
  return "<li><code>" .. escape(path) .. "</code>" .. (tail or "") .. "</li>"
end

-- The `<li>` saying how many paths were left out; nothing when none were.
local function moreItem(more)
  return more > 0 and '<li class="more">and ' .. more .. " more</li>" or ""
end

-- The plan vs actual section: its header and lists, or its one line.
local function actualHtml(a)
  local out = { '<section class="actual"><div class="label">PLAN VS ACTUAL</div>' }
  if a.line then
    out[#out + 1] = '<p class="line">' .. escape(a.line) .. "</p>"
  else
    out[#out + 1] = '<p class="since">' .. escape(a.header) .. "</p>"
    for _, l in ipairs(a.lists) do
      local lis = {}
      for _, r in ipairs(l.rows) do
        lis[#lis + 1] = item(r.path, (r.unchecked and ' <span class="unchecked">not checked</span>' or "")
          .. (r.unseen and ' <span class="unseen">not seen from the agent</span>' or ""))
      end
      out[#out + 1] = '<div class="list"><div class="name">' .. (l.mark and l.mark .. " " or "") .. escape(l.title)
        .. " <small>" .. l.total .. "</small></div><ul>" .. table.concat(lis) .. moreItem(l.more) .. "</ul></div>"
    end
  end
  out[#out + 1] = "</section>"
  return table.concat(out)
end

-- One turn's `<li>`: time, how long (empty when not known), the file count opening to the paths, tests, commits.
local function turnHtml(t)
  local files
  if t.total == 0 then
    files = '<span class="files">0 files</span>'
  else
    local lis = {}
    for _, path in ipairs(t.files) do lis[#lis + 1] = item(path) end
    files = '<details class="files"><summary>' .. counted(t.total, "file") .. "</summary><ul>" .. table.concat(lis)
      .. moreItem(t.more) .. "</ul></details>"
  end
  local commits = {}
  for _, c in ipairs(t.commits) do
    commits[#commits + 1] = '<span class="commit"><code>' .. escape(c.hash) .. "</code> " .. escape(c.subject) .. "</span>"
  end
  return '<li><span class="time">' .. t.time .. '</span><span class="took">' .. escape(t.took or "") .. "</span>" .. files
    .. (t.tests and '<span class="tests">' .. t.tests .. "</span>" or "")
    .. (#commits > 0 and '<span class="commits">' .. table.concat(commits) .. "</span>" or "") .. "</li>"
end

-- The two blocks for view `v` (workcard.view): plan vs actual, then the turns when there are any.
function workcard.html(v)
  local out = { actualHtml(v.actual) }
  if #v.turns > 0 then
    local rowsHtml = {}
    for _, t in ipairs(v.turns) do rowsHtml[#rowsHtml + 1] = turnHtml(t) end
    out[#out + 1] = '<section class="turns"><div class="label">TURNS</div><ul class="turnlist">' .. table.concat(rowsHtml)
      .. "</ul></section>"
  end
  return table.concat(out)
end

-- The styles for the two blocks, in the page's tokens (--accent, --faint).
workcard.CSS = table.concat({
  ".actual, .turns { padding-top: 8px; border-top: 1px solid var(--faint); margin-bottom: 8px; }",
  ".since { margin: 0 0 6px; font: 12px Menlo, monospace; opacity: 0.75; } .actual .line { margin: 0; opacity: 0.75; }",
  ".actual .name { font-weight: 600; margin-top: 6px; } .actual .name small { opacity: 0.55; font-weight: 400; }",
  ".actual ul, .turns ul { list-style: none; padding: 0; margin: 2px 0; }",
  ".actual li { padding: 1px 0 1px 18px; } .actual code { overflow-wrap: anywhere; }",
  ".unseen, .unchecked { font-size: 10px; opacity: 0.55; margin-left: 4px; } .more { opacity: 0.55; }",
  ".turnlist > li { display: grid; grid-template-columns: 44px 64px 1fr; gap: 2px 8px; padding: 3px 0;",
  " border-bottom: 1px solid var(--faint); }",
  ".turnlist .time { font: 12px Menlo, monospace; opacity: 0.6; } .turnlist .took { color: var(--accent); }",
  ".turnlist .tests, .turnlist .commits { grid-column: 3; } .turnlist .commit { display: block; }",
  ".turnlist summary { cursor: pointer; } .turnlist details li { padding-left: 12px; }",
})

return workcard
