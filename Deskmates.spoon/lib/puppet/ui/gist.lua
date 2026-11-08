-- A step's document in a few lines, for the card's story: its title (the first # heading), the paragraph that
-- says what it is about (under Intent, Summary, Goal, Context, Overview or What changed; else the first one),
-- the verdict of its last review round, and a button that asks the Spoon to open it. gist.parse reads, gist.html
-- draws, every text escaped. It knows no Hammerspoon.

local config = require("puppet.config")
local sessioncard = require("puppet.ui.sessioncard")

local gist = {}

local escape = sessioncard.escape

-- The headings whose first paragraph says what a document is about.
local ABOUT = { intent = true, summary = true, goal = true, context = true, overview = true, ["what changed"] = true }

-- A line of markdown as plain text: a link keeps its text, emphasis and code marks go.
local function plain(text)
  text = text:gsub("!?%[([^%]]*)%]%b()", "%1")
  text = text:gsub("`", ""):gsub("%*", "")
  text = text:gsub("%f[_%w]_([^_]+)_%f[^_%w]", "%1")
  return text
end

-- The paragraph that starts at or after line `i` of `lines`: its lines up to a blank one or a heading, joined.
local function paragraph(lines, i)
  while lines[i] and lines[i]:match("^%s*$") do i = i + 1 end
  local out = {}
  while lines[i] and not lines[i]:match("^%s*$") and not lines[i]:match("^#") do
    out[#out + 1] = lines[i]:match("^%s*(.-)%s*$")
    i = i + 1
  end
  if #out == 0 then return nil end
  return (plain(table.concat(out, " ")):gsub("%s+", " "))
end

-- `text` cut to config.GIST_CHARS characters, at a word when it has one, with "…".
local function cut(text)
  if utf8.len(text) <= config.GIST_CHARS then return text end
  local short = text:sub(1, utf8.offset(text, config.GIST_CHARS + 1) - 1)
  local atWord = short:match("^(.*%S)%s+%S*$")
  return (atWord or short) .. "…"
end

-- Document `text` (named `name`) as { title, summary, verdict, round, file }: title the first # heading (else the
-- name), summary the paragraph about it (nil when none), verdict the last "**Verdict: X**" in words ("changes
-- requested"), round the last "Round N" heading's N when there are two or more.
function gist.parse(text, name)
  local lines = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line:gsub("\r$", "") end
  local g = { file = name }
  local titleAt, aboutAt, rounds, lastRound = nil, nil, 0, nil
  for i, line in ipairs(lines) do
    local level, heading = line:match("^(#+)%s+(.-)%s*$")
    if level then
      if level == "#" and not titleAt then g.title, titleAt = plain(heading), i end
      local words = heading:lower():gsub("^[%d%.%s]+", "")
      if not aboutAt and ABOUT[words] then aboutAt = i end
      local n = heading:match("[Rr]ound%s+(%d+)")
      if n then rounds, lastRound = rounds + 1, tonumber(n) end
    end
    local verdict = line:match("%*%*Verdict:%s*(.-)%s*%*%*")
    if verdict and verdict ~= "" then g.verdict = verdict:lower():gsub("_", " ") end
  end
  g.title = g.title or name
  local summary = aboutAt and paragraph(lines, aboutAt + 1) or paragraph(lines, (titleAt or 0) + 1)
  g.summary = summary and cut(summary) or nil
  if rounds >= 2 then g.round = lastRound end
  return g
end

-- The gist of the document at `path`: the first config.DOC_BYTES of it, parsed; nil when it cannot be read or is
-- not UTF-8 text (a character the cap cut in two does not count).
function gist.read(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local text = file:read(config.DOC_BYTES) or ""
  file:close()
  local ok, bad = utf8.len(text)
  if not ok then
    if #text < config.DOC_BYTES or bad <= #text - 4 then return nil end
    text = text:sub(1, bad - 1)
  end
  return gist.parse(text, path:match("[^/]+$"))
end

-- Gist `g` for the step that started at `from`: hidden until the page shows it for that step.
function gist.html(g, from)
  local verdict = g.verdict and ' <span class="verdict">' .. escape(g.verdict)
    .. (g.round and " · round " .. g.round or "") .. "</span>" or ""
  return '<div class="gist" data-from="' .. string.format("%d", from) .. '" hidden><div class="gisthead"><span class="gisttitle">'
    .. escape(g.title) .. "</span>" .. verdict .. "</div>"
    .. (g.summary and "<p>" .. escape(g.summary) .. "</p>" or "")
    .. '<button class="doc-open" title="Open the document">' .. escape(g.file) .. "</button></div>"
end

-- The styles for a gist, in the page's tokens.
gist.CSS = table.concat({
  ".gist { margin: 0 0 12px; padding: 8px 10px; border-radius: 6px; font-size: 12px;",
  " background: color-mix(in srgb, CanvasText 6%, transparent); overflow-wrap: anywhere; }",
  ".gist[hidden] { display: none; } .gist .gisttitle { font-weight: 600; } .gist .gisthead { display: flex; flex-wrap: wrap; gap: 6px; align-items: baseline; }",
  ".gist p { margin: 4px 0; color: var(--muted); }",
  ".gist .doc-open { all: unset; cursor: pointer; color: LinkText; text-decoration: underline; font: 12px Menlo, monospace; }",
  ".gist .doc-open:focus-visible { outline: 2px solid Highlight; outline-offset: 2px; }",
})

return gist
