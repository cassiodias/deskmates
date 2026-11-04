-- The plan card: a small window beside a puppet with its session's checklist and plan, opened by a click.
-- plancard.markdown and plancard.html build the page and know no Hammerspoon. Everything from the agent is
-- escaped before it is formatted, links show as text and are never followed, and the page's own script (its
-- buttons and Esc) is the only one its policy allows.

local planblocks = require("puppet.ui.planblocks")

local plancard = {}

local WIDTH, HEIGHT = 600, 560

local function escape(text)
  return (text:gsub("[&<>\"']", { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&#39;" }))
end

-- Bold, italic, code and links in one line of text, escaped first. Code is kept apart so its text stays as is.
local function inline(text)
  local codes = {}
  text = text:gsub("`([^`]+)`", function(code)
    codes[#codes + 1] = "<code>" .. escape(code) .. "</code>"
    return "\0" .. #codes .. "\0"
  end)
  text = escape(text)
  text = text:gsub("%[([^%]]+)%]%(([^%)]*)%)", '<span class="link">%1</span>')
  text = text:gsub("%*%*(.-)%*%*", "<strong>%1</strong>")
  text = text:gsub("__(.-)__", "<strong>%1</strong>")
  text = text:gsub("%*([^%*]+)%*", "<em>%1</em>")
  return (text:gsub("%z(%d+)%z", function(n) return codes[tonumber(n)] end))
end

local function box(item)
  local mark, rest = item:match("^%[([ xX])%]%s+(.*)$")
  if mark then return (mark == " " and "☐ " or "☑ ") .. inline(rest) end
  return inline(item)
end

local function row(cellsOf, tag)
  local out = {}
  for _, cell in ipairs(cellsOf) do out[#out + 1] = inline(cell) end
  return "<tr><" .. tag .. ">" .. table.concat(out, "</" .. tag .. "><" .. tag .. ">") .. "</" .. tag .. "></tr>"
end

-- A lifted block's markdown, a click away: the reader can always check what it was drawn from.
local function source(block)
  return '<details class="source"><summary>source</summary><pre><code>' .. escape(block.source) .. "</code></pre></details>"
end

-- One block of planblocks.parse or planblocks.lift as HTML, every text in it escaped.
function plancard.block(block)
  local kind = block.kind
  if kind == "heading" then
    return "<h" .. block.level .. ">" .. inline(block.text) .. "</h" .. block.level .. ">"
  elseif kind == "paragraph" then
    return "<p>" .. inline(table.concat(block.lines, " ")) .. "</p>"
  elseif kind == "list" then
    local items = {}
    for _, item in ipairs(block.items) do items[#items + 1] = "<li>" .. box(item) .. "</li>" end
    local tag = block.ordered and "ol" or "ul"
    return "<" .. tag .. ">" .. table.concat(items) .. "</" .. tag .. ">"
  elseif kind == "code" then
    local code = {}
    for _, line in ipairs(block.lines) do code[#code + 1] = escape(line) end
    return "<pre><code>" .. table.concat(code, "\n") .. "</code></pre>"
  elseif kind == "quote" then
    return "<blockquote>" .. inline(table.concat(block.lines, " ")) .. "</blockquote>"
  elseif kind == "table" then
    local html = { "<table>" }
    for r, cellsOf in ipairs(block.rows) do html[#html + 1] = row(cellsOf, r == 1 and "th" or "td") end
    return table.concat(html) .. "</table>"
  elseif kind == "rule" then
    return "<hr>"
  elseif kind == "filemap" then
    local rows = {}
    for _, r in ipairs(block.rows) do
      rows[#rows + 1] = '<div class="file"><code>' .. escape(r.path) .. '</code><span class="badge'
        .. (r.badge and " " .. r.badge or "") .. '">' .. (r.badge or "") .. '</span><span class="note">'
        .. inline(r.note) .. "</span></div>"
    end
    return '<div class="filemap">' .. (block.titled and "" or '<div class="label">FILES</div>')
      .. table.concat(rows) .. source(block) .. "</div>"
  elseif kind == "endpoints" then
    local rows = {}
    for _, r in ipairs(block.rows) do
      rows[#rows + 1] = '<div class="endpoint"><span class="method ' .. r.method:lower() .. '">' .. r.method
        .. "</span><code>" .. escape(r.path) .. '</code><span class="status">' .. (r.status or "")
        .. '</span><span class="note">' .. inline(r.note) .. "</span></div>"
    end
    return '<div class="endpoints">' .. table.concat(rows) .. source(block) .. "</div>"
  end
  return ""
end

-- The markdown plans are written in, as HTML: headings, paragraphs, lists (task boxes too), code blocks,
-- quotes, tables and rules, and the blocks lifted from them (planblocks.lift).
function plancard.markdown(text)
  local out = {}
  for _, block in ipairs(planblocks.lift(planblocks.parse(text))) do out[#out + 1] = plancard.block(block) end
  return table.concat(out, "\n")
end

local MARKS = { done = "☑", active = "▶", pending = "☐" }

-- The longest first paragraph shown as the summary; a longer one stays in the plan, where it reads whole.
local SUMMARY_LENGTH = 240

-- The plan's title and summary (its first heading when that is a `#` one, and a short paragraph after it,
-- lifted into the header), and the rest of its blocks, with an id on each `##` heading for the contents.
local function split(markdown)
  local blocks = planblocks.lift(planblocks.parse(markdown or ""))
  local title, summary, first = nil, nil, 1
  if blocks[1] and blocks[1].kind == "heading" and blocks[1].level == 1 then
    title, first = blocks[1].text, 2
    local para = blocks[2] and blocks[2].kind == "paragraph" and table.concat(blocks[2].lines, " ")
    if para and (utf8.len(para) or #para) <= SUMMARY_LENGTH then summary, first = para, 3 end
  end
  local rest, sections = {}, {}
  for i = first, #blocks do
    local block = blocks[i]
    if block.kind == "heading" and block.level == 2 then
      sections[#sections + 1] = block.text
      rest[#rest + 1] = '<h2 id="sec-' .. #sections .. '">' .. inline(block.text) .. "</h2>"
    else
      rest[#rest + 1] = plancard.block(block)
    end
  end
  return title, summary, table.concat(rest, "\n"), sections
end

-- The whole page for `plan` (model/plans.lua's shape); meta.title names the session, meta.color is its puppet's.
function plancard.html(plan, meta)
  local nonce = string.format("%08x%08x", math.random(0, 0x7fffffff), math.random(0, 0x7fffffff))
  local color = (meta.color or ""):match("^#%x%x%x%x%x%x$") or "#888888"
  local steps = plan.steps or {}
  local done = 0
  for _, step in ipairs(steps) do if step.status == "done" then done = done + 1 end end
  local title, summary, article, sections = split(plan.markdown)

  local body = { '<header><div class="label">PLAN</div><h1 class="title">', escape(title or meta.title or "Plan"), "</h1>" }
  if summary then body[#body + 1] = '<p class="summary">' .. inline(summary) .. "</p>" end
  if #steps > 0 then
    body[#body + 1] = '<div class="progress"><progress value="' .. done .. '" max="' .. #steps .. '"></progress>'
      .. '<span class="count">' .. done .. "/" .. #steps .. "</span></div>"
  end
  body[#body + 1] = "</header>"

  local aside = {}
  if #sections >= 2 then
    aside[#aside + 1] = '<nav class="contents"><div class="label">ON THIS PLAN</div>'
    for n, text in ipairs(sections) do
      aside[#aside + 1] = '<button data-to="sec-' .. n .. '">' .. inline(text) .. "</button>"
    end
    aside[#aside + 1] = "</nav>"
  end
  if #steps > 0 then
    local items = {}
    for _, step in ipairs(steps) do
      items[#items + 1] = '<li class="' .. step.status .. '"><span class="mark">' .. MARKS[step.status] .. "</span>"
        .. escape(step.title) .. "</li>"
    end
    aside[#aside + 1] = '<section class="checklist"><div class="label">CHECKLIST</div><ul class="steps">'
      .. table.concat(items) .. "</ul></section>"
  end
  body[#body + 1] = '<div class="layout' .. (#aside == 0 and " solo" or "") .. '">'
  if #aside > 0 then body[#body + 1] = "<aside>" .. table.concat(aside) .. "</aside>" end
  body[#body + 1] = "<article>" .. article .. "</article></div>"
  body[#body + 1] = '<footer><button id="focus">Go to terminal</button><button id="close">Close</button></footer>'

  local faint = "color-mix(in srgb, CanvasText 15%, transparent)"
  return table.concat({
    '<!doctype html><html><head><meta charset="utf-8">',
    "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'; ",
    "script-src 'nonce-", nonce, "'\">",
    "<style>",
    ":root { --accent: ", color, "; --faint: ", faint, "; color-scheme: light dark; }",
    "body { margin: 0; font: 13px -apple-system, sans-serif; background: Canvas; color: CanvasText;",
    " display: flex; flex-direction: column; height: 100vh; border-top: 4px solid var(--accent); }",
    ".label { font-size: 10px; font-weight: 700; letter-spacing: 0.08em; opacity: 0.55; margin-bottom: 4px; }",
    "header { padding: 10px 14px 8px; border-bottom: 1px solid var(--faint); }",
    "header .title { font-size: 16px; margin: 0; }",
    ".summary { margin: 4px 0 0; opacity: 0.8; }",
    ".progress { display: flex; align-items: center; gap: 8px; margin-top: 6px; }",
    "progress { flex: 1; accent-color: var(--accent); } .count { color: var(--accent); font-weight: 600; }",
    ".layout { flex: 1; min-height: 0; display: grid; grid-template-columns: 180px 1fr; }",
    ".layout.solo { grid-template-columns: 1fr; }",
    "aside { overflow: auto; padding: 10px 10px 10px 14px; border-right: 1px solid var(--faint); }",
    "article { overflow: auto; padding: 0 14px 10px; }",
    ".contents { margin-bottom: 14px; } .contents button { display: block; width: 100%; text-align: left; background: none;",
    " border: 0; padding: 3px 4px; border-radius: 4px; color: inherit; font: inherit; cursor: pointer; }",
    ".contents button:hover { background: var(--faint); }",
    "article::after { content: ''; display: block; height: 70vh; }",
    "h2 { scroll-margin-top: 8px; border-radius: 4px; } h2.here { animation: here 1.4s ease-out; }",
    "@keyframes here { from { background: color-mix(in srgb, var(--accent) 30%, transparent); } to { background: transparent; } }",
    "@media (max-width: 559px) { .layout { display: flex; flex-direction: column; overflow: auto; }",
    " aside { display: contents; } .contents { order: 1; padding: 10px 14px 0; }",
    " article { order: 2; overflow: visible; } .checklist { order: 3; padding: 0 14px 10px; } }",
    ".steps { list-style: none; padding: 0; margin: 0; }",
    ".steps li { padding: 3px 0; } .steps .mark { display: inline-block; width: 20px; color: var(--accent); }",
    ".steps .done { opacity: 0.6; text-decoration: line-through; } .steps .active { font-weight: 600; }",
    "pre { background: color-mix(in srgb, CanvasText 7%, transparent); padding: 8px; overflow: auto; border-radius: 6px; }",
    "code { font: 12px Menlo, monospace; } table { border-collapse: collapse; }",
    "th, td { border: 1px solid color-mix(in srgb, CanvasText 20%, transparent); padding: 3px 6px; text-align: left; }",
    "blockquote { margin: 0; padding-left: 10px; border-left: 3px solid var(--accent); opacity: 0.8; }",
    ".link { text-decoration: underline; }",
    ".filemap { margin: 8px 0; } .file { display: grid; grid-template-columns: minmax(0, max-content) 52px 1fr; gap: 8px;",
    " align-items: baseline; padding: 3px 0; border-bottom: 1px solid var(--faint); }",
    ".file code { overflow-wrap: anywhere; } .note { opacity: 0.75; }",
    ".badge { font-size: 10px; font-weight: 600; text-align: center; border-radius: 4px; padding: 1px 4px; }",
    ".badge.new { color: #2e9d4e; background: color-mix(in srgb, #2e9d4e 15%, transparent); }",
    ".badge.edit { color: var(--accent); background: color-mix(in srgb, var(--accent) 15%, transparent); }",
    ".badge.delete { color: #d0453a; background: color-mix(in srgb, #d0453a 15%, transparent); }",
    ".endpoints { margin: 8px 0; } .endpoint { display: grid; grid-template-columns: 58px minmax(0, max-content) 36px 1fr;",
    " gap: 8px; align-items: baseline; padding: 3px 0; border-bottom: 1px solid var(--faint); }",
    ".endpoint code { overflow-wrap: anywhere; } .status { font: 600 12px Menlo, monospace; opacity: 0.8; }",
    ".method { --m: #3a7bd5; font: 700 10px Menlo, monospace; text-align: center; border-radius: 4px; padding: 2px 4px;",
    " color: var(--m); background: color-mix(in srgb, var(--m) 15%, transparent); }",
    ".method.post { --m: #2e9d4e; } .method.put, .method.patch { --m: #c98a12; } .method.delete { --m: #d0453a; }",
    ".source { margin-top: 4px; font-size: 11px; } .source summary { cursor: pointer; opacity: 0.55; }",
    "footer { display: flex; gap: 8px; justify-content: flex-end; padding: 8px 14px; border-top: 1px solid var(--faint); }",
    "footer button { font: inherit; padding: 4px 12px; }",
    "#focus { background: var(--accent); color: white; border: 0; border-radius: 5px; }",
    "</style></head><body>",
    table.concat(body),
    '<script nonce="', nonce, '">', plancard.SCRIPT, "</script>",
    "</body></html>",
  })
end

-- The page's one script: its buttons and Esc tell the Spoon, through the "deskmates" message handler; a click
-- in the contents scrolls to its section, inside the page, and lights its heading up.
plancard.SCRIPT = "function send(m){window.webkit.messageHandlers.deskmates.postMessage(m)}"
  .. "document.getElementById('focus').onclick=function(){send('focus')};"
  .. "document.getElementById('close').onclick=function(){send('close')};"
  .. "document.addEventListener('keydown',function(e){if(e.key==='Escape')send('close')});"
  .. "document.querySelectorAll('[data-to]').forEach(function(b){b.onclick=function(){"
  .. "var t=document.getElementById(b.getAttribute('data-to'));if(!t)return;t.scrollIntoView({block:'start'});"
  .. "t.classList.remove('here');void t.offsetWidth;t.classList.add('here')}});"

local PlanCard = {}
PlanCard.__index = PlanCard
plancard.PlanCard = PlanCard

local MIN_WIDTH, MIN_HEIGHT = 320, 280

-- The card's size from what was saved: a table with numbers w and h, raised to the smallest card; anything
-- else is the default size.
function plancard.fitSize(saved)
  if type(saved) ~= "table" or type(saved.w) ~= "number" or type(saved.h) ~= "number" then
    return { w = WIDTH, h = HEIGHT }
  end
  return { w = math.max(MIN_WIDTH, math.floor(saved.w)), h = math.max(MIN_HEIGHT, math.floor(saved.h)) }
end

-- opts.onFocus(key): the card's "Go to terminal". opts.frameFor(key, w, h): where the card goes, beside its puppet.
-- opts.loadSize() and opts.saveSize({ w, h }) (optional): the size the card was last left at.
function plancard.new(opts)
  return setmetatable({ onFocus = opts.onFocus, frameFor = opts.frameFor, loadSize = opts.loadSize,
    saveSize = opts.saveSize }, PlanCard)
end

-- Shows session `key`'s plan; meta as for plancard.html. Replaces a card already open.
function PlanCard:show(key, plan, meta)
  self:hide()
  self.key = key
  local content = hs.webview.usercontent.new("deskmates")
  content:setCallback(function(message)
    if message.body == "focus" then
      local shown = self.key
      self:hide()
      if shown then self.onFocus(shown) end
    elseif message.body == "close" then
      self:hide()
    end
  end)
  local size = plancard.fitSize(self.loadSize and self.loadSize())
  local rect = self.frameFor(key, size.w, size.h)
  local view = hs.webview.new(rect, { developerExtrasEnabled = false }, content)
  view:windowStyle({ "titled", "closable", "utility", "resizable" })
  -- new() takes the page's rect, but frame() and frameChange give the window's, title bar included (once the
  -- style above gives it one): keep the difference, so the size saved is the page's and the card does not grow
  -- each time it opens.
  local outer = view:frame()
  local chromeW, chromeH = outer.w - rect.w, outer.h - rect.h
  view:windowTitle(meta.title or "Plan")
  view:allowTextEntry(true)
  view:deleteOnClose(true)
  view:level(hs.drawing.windowLevels.floating)
  -- Nothing on the page leads anywhere: only the page itself loads.
  view:policyCallback(function(action, _, details)
    if action == "navigationAction" then return details and details.navigationType == "other" end
    return action ~= "newWindow"
  end)
  view:windowCallback(function(action, _, state)
    if action == "closing" then
      self.view = nil
    elseif action == "focusChange" and state == false then
      self:hide()
    elseif action == "frameChange" and type(state) == "table" and self.saveSize then
      self.saveSize(plancard.fitSize({ w = state.w - chromeW, h = state.h - chromeH }))
    end
  end)
  view:html(plancard.html(plan, meta))
  view:show()
  view:bringToFront(true)
  local window = view:hswindow()
  if window then window:focus() end
  self.view = view
end

-- Hides the card at once and deletes it a moment later: hide runs inside the card's own callbacks (its
-- buttons, losing focus), and a web view must not be deleted while it is still handling one.
function PlanCard:hide()
  if self.view then
    local view = self.view
    self.view = nil
    view:hide()
    hs.timer.doAfter(0, function() view:delete() end)
  end
  self.key = nil
end

function PlanCard:isShown() return self.view ~= nil end

return plancard
