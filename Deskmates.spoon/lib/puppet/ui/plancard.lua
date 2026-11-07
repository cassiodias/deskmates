-- The plan card: a small window beside a puppet with its session's checklist and plan, opened by a click.
-- plancard.markdown and plancard.html build the page and know no Hammerspoon. Everything from the agent is
-- escaped before it is formatted, links show as text and are never followed, and the page's own script (its
-- buttons and Esc) is the only one its policy allows.

local planblocks = require("puppet.ui.planblocks")
local panel = require("puppet.ui.panel")
local sessioncard = require("puppet.ui.sessioncard")
local story = require("puppet.ui.story")
local workcard = require("puppet.ui.workcard")

local plancard = {}

local WIDTH, HEIGHT = 600, 560

local escape = sessioncard.escape

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

-- The whole page for `plan` (model/plans.lua's shape, or nil); meta.title names the session, meta.color is its
-- puppet's. On top what changed (meta.work, workcard.html, or nil): the session's result, whatever the step
-- picked, scrolling in a third of the card when open (a fifth, giving way, with a plan). Then the header for meta.session (sessioncard.view, or nil),
-- what the session is working on, with the step `step` keeps picked (sessioncard.pick: a step's start, "none", or
-- nil for the default). Then the story (meta.story, story.html, or nil): it fills the card when no plan follows,
-- else it scrolls in 30% of it, giving way, and the plan comes below with at least 120px. `folded` ({ [panel id] = true }, or nil): the panels
-- drawn closed.
function plancard.html(plan, meta, folded, step)
  local nonce = string.format("%08x%08x", math.random(0, 0x7fffffff), math.random(0, 0x7fffffff))
  local color = (meta.color or ""):match("^#%x%x%x%x%x%x$") or "#888888"
  local session = meta.session and sessioncard.html(meta.session, step)
  local hasPlan = plan ~= nil
  plan = plan or { steps = {} }
  local steps = plan.steps or {}
  local done = 0
  for _, step in ipairs(steps) do if step.status == "done" then done = done + 1 end end
  local title, summary, article, sections = split(plan.markdown)

  local body = {}
  if meta.work then body[#body + 1] = '<div class="result' .. (hasPlan and " capped" or "") .. '">' .. meta.work .. "</div>" end
  if session then body[#body + 1] = "<header>" .. session .. "</header>" end
  if meta.story then
    body[#body + 1] = '<div class="panels' .. (hasPlan and " capped" or "") .. '">' .. meta.story .. "</div>"
  end
  if hasPlan then
    body[#body + 1] = '<header><div class="label">PLAN</div><h1 class="title">' .. escape(title or meta.title or "Plan") .. "</h1>"
    if summary then body[#body + 1] = '<p class="summary">' .. inline(summary) .. "</p>" end
    if #steps > 0 then
      body[#body + 1] = '<div class="progress"><progress value="' .. done .. '" max="' .. #steps .. '"></progress>'
        .. '<span class="count">' .. done .. "/" .. #steps .. "</span></div>"
    end
    body[#body + 1] = "</header>"
  end

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
  if hasPlan then
    body[#body + 1] = '<div class="layout' .. (#aside == 0 and " solo" or "") .. '" id="plan">'
    if #aside > 0 then body[#body + 1] = "<aside>" .. table.concat(aside) .. "</aside>" end
    body[#body + 1] = "<article>" .. article .. "</article></div>"
  end
  body[#body + 1] = '<footer><button id="focus">Go to terminal</button><button id="close">Close</button></footer>'

  local faint = "color-mix(in srgb, CanvasText 15%, transparent)"
  return table.concat({
    '<!doctype html><html><head><meta charset="utf-8">',
    "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'; ",
    "script-src 'nonce-", nonce, "'\">",
    "<style>",
    ":root { --accent: ", color, "; --faint: ", faint, "; color-scheme: light dark; }",
    "body { margin: 0; box-sizing: border-box; font: 13px -apple-system, sans-serif; background: Canvas; color: CanvasText;",
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
    "[hidden] { display: none !important; }",
    sessioncard.CSS,
    workcard.CSS,
    story.CSS,
    panel.CSS,
    ".result { flex: none; max-height: 35vh; overflow: auto; padding: 10px 14px 0; border-bottom: 1px solid var(--faint);",
    " padding-bottom: 8px; }",
    -- With a plan below, what changed and the story give way to it, and the plan always shows some lines. What
    -- changed gives way first (4 to the story's 1), so on the default card the story reaches its cap.
    ".result.capped { flex: 0 4 auto; min-height: 44px; max-height: 22vh; } #plan { min-height: 120px; }",
    "footer { display: flex; gap: 8px; justify-content: flex-end; padding: 8px 14px; border-top: 1px solid var(--faint); }",
    "footer button { font: inherit; padding: 4px 12px; }",
    "#focus { background: var(--accent); color: white; border: 0; border-radius: 5px; }",
    "</style></head><body>",
    panel.fold(table.concat(body), folded),
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
  .. "document.querySelectorAll('button[data-to]:not(.phase)').forEach(function(b){b.onclick=function(){"
  .. "var t=document.getElementById(b.getAttribute('data-to'));if(!t)return;t.scrollIntoView({block:'start'});"
  .. "t.classList.remove('here');void t.offsetWidth;t.classList.add('here')}});"
  -- Also: show the ticket chosen (its header and its story), hide the others, and filter by the step picked on
  -- its strip. A strip hidden at load had no width to scroll: the one shown now opens on its newest step.
  .. "var also=document.querySelector('select.also');if(also)also.onchange=function(){"
  .. "document.querySelectorAll('[data-key]').forEach(function(el){el.hidden=el.getAttribute('data-key')!==also.value});"
  .. "document.querySelectorAll('.ticket:not([hidden]) .strip').forEach(function(s){s.scrollLeft=s.scrollWidth});picked()};"
  -- A step filters the story in place and marks the page (body.lane); a second click clears it. A line or a reply
  -- stays when it happened during the step: from its start (data-from) up to the next step's (data-to, none for the
  -- last). A turn stays while it overlaps the step: it started before the step's end and ended (data-end, empty
  -- while it has no end) after its start, since a step mostly starts inside a turn. A step not reached yet (no
  -- data-from) leaves no row. A folded panel stays folded: folds are the reader's alone.
  -- The panels stay where the reader left them: nothing is brought into view, and their scroll position is put
  -- back after the rows change. With a plan, a Plan step not reached yet clears it and takes the plan's article
  -- (what scrolls: the body never does) back to its top. The Spoon is told the step picked (its start, or none),
  -- to draw it picked again next time.
  .. "function only(b){document.body.classList.toggle('lane',!!b);"
  .. "var f=b&&b.getAttribute('data-from'),t=b&&b.getAttribute('data-to');"
  .. "document.querySelectorAll('.storylist>li').forEach(function(li){var a=Number(li.getAttribute('data-at')),"
  .. "e=li.getAttribute('data-end'),s=e===null?a:e===''?Infinity:Number(e);"
  .. "li.classList.toggle('out',!!b&&(f===null||s<Number(f)||(t!==null&&a>=Number(t))))})}"
  .. "function picked(){only(document.querySelector('.ticket:not([hidden]) button.phase.on'))}"
  .. "document.querySelectorAll('button.phase').forEach(function(b){b.onclick=function(){"
  .. "var p=b.getAttribute('data-phase'),f=b.getAttribute('data-from'),plan=document.getElementById('plan'),"
  .. "on=b.classList.contains('on'),"
  .. "panels=document.querySelector('.panels'),top=panels?panels.scrollTop:0;"
  .. "b.parentNode.querySelectorAll('button.phase').forEach(function(x){x.classList.remove('on')});only(null);"
  .. "if(plan&&p==='plan'&&f===null){send('step:none');var art=plan.querySelector('article');if(art)art.scrollTop=0;return}"
  .. "if(!on){b.classList.add('on');only(b)}"
  .. "if(!on&&f!==null)send('step:'+f);else send('step:none');"
  .. "if(panels)panels.scrollTop=top}});"
  -- The strip scrolls sideways when the steps do not fit: it opens at its end, on the newest step.
  .. "document.querySelectorAll('.strip').forEach(function(s){s.scrollLeft=s.scrollWidth});"
  -- The card opens with the story filtered to the step drawn picked (the one happening now, or the reader's).
  .. "picked();"
  -- A panel folded or opened: the Spoon keeps it so for the next drawing of this session's card. A panel drawn
  -- open fires toggle on load too: only a change from the state drawn is told, so a redraw sends nothing.
  .. "document.querySelectorAll('details.panel').forEach(function(d){var was=d.open;d.addEventListener('toggle',"
  .. "function(){if(d.open===was)return;was=d.open;"
  .. "send('fold:'+d.getAttribute('data-panel')+':'+(d.open?'open':'closed'))})});"

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
  -- The folds and the step picked belong to the session shown: kept while its card is drawn again (and opened
  -- again), dropped when another session's card opens.
  if self.foldKey ~= key then self.folded, self.step, self.foldKey = {}, nil, key end
  local content = hs.webview.usercontent.new("deskmates")
  content:setCallback(function(message)
    if message.body == "focus" then
      local shown = self.key
      if shown then self.focusTimer = hs.timer.doAfter(0, function() self.onFocus(shown) end) end
    elseif message.body == "close" then
      self:hide()
    elseif self.key == key then
      local id, isFolded = panel.message(message.body)
      if id then self.folded[id] = isFolded or nil end
      local step = sessioncard.stepMessage(message.body)
      if step then self.step = step end
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
  -- The card opens beside the terminal the double click's first click brought forward, and stays there until it is
  -- closed: losing the focus to that terminal (it becomes the active app a moment after the card shows) must not
  -- hide it.
  view:windowCallback(function(action, _, state)
    if action == "closing" then
      self.view = nil
    elseif action == "frameChange" and type(state) == "table" and self.saveSize then
      self.saveSize(plancard.fitSize({ w = state.w - chromeW, h = state.h - chromeH }))
    end
  end)
  view:html(plancard.html(plan, meta, self.folded, self.step))
  view:show()
  -- Hammerspoon becomes the active app, so the card is the key window: an inactive card loses its first click.
  -- (view:hswindow() would find the window, but it asks macOS about every app's windows: 1.5 s.)
  hs.focus()
  view:bringToFront(true)
  self.view = view
end

-- Hides the card at once and deletes it a moment later: hide runs inside the card's own callbacks (its Close
-- button), and a web view must not be deleted while it is still handling one.
function PlanCard:hide()
  if self.view then
    local view = self.view
    self.view = nil
    view:hide()
    hs.timer.doAfter(0, function() view:delete() end)
  end
  self.key = nil
end

-- Shows a newer page in the card of session `key`, in the same window; nothing when the card shows another
-- session, or none.
function PlanCard:update(key, plan, meta)
  if self.view and self.key == key then self.view:html(plancard.html(plan, meta, self.folded, self.step)) end
end

function PlanCard:isShown() return self.view ~= nil end

return plancard
