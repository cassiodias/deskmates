-- The plan card: a small window beside a puppet with its session's checklist and plan, opened by a click.
-- plancard.markdown and plancard.html build the page and know no Hammerspoon. Everything from the agent is
-- escaped before it is formatted, links show as text and are never followed, and the page's own script (its
-- buttons and Esc) is the only one its policy allows.

local planblocks = require("puppet.ui.planblocks")

local plancard = {}

local WIDTH, HEIGHT = 440, 520

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

-- One block of planblocks.parse as HTML, every text in it escaped.
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
  end
  return ""
end

-- The markdown plans are written in, as HTML: headings, paragraphs, lists (task boxes too), code blocks,
-- quotes, tables and rules.
function plancard.markdown(text)
  local out = {}
  for _, block in ipairs(planblocks.parse(text)) do out[#out + 1] = plancard.block(block) end
  return table.concat(out, "\n")
end

local MARKS = { done = "☑", active = "▶", pending = "☐" }

-- The whole page for `plan` (model/plans.lua's shape); meta.title names the session, meta.color is its puppet's.
function plancard.html(plan, meta)
  local nonce = string.format("%08x%08x", math.random(0, 0x7fffffff), math.random(0, 0x7fffffff))
  local color = (meta.color or ""):match("^#%x%x%x%x%x%x$") or "#888888"
  local body = {}
  local done = 0
  for _, step in ipairs(plan.steps or {}) do if step.status == "done" then done = done + 1 end end
  body[#body + 1] = "<header><h2>" .. escape(meta.title or "Plan") .. "</h2>"
  if #(plan.steps or {}) > 0 then body[#body + 1] = '<span class="count">' .. done .. "/" .. #plan.steps .. "</span>" end
  body[#body + 1] = "</header><main>"
  if #(plan.steps or {}) > 0 then
    local items = {}
    for _, step in ipairs(plan.steps) do
      items[#items + 1] = '<li class="' .. step.status .. '"><span class="mark">' .. MARKS[step.status] .. "</span>"
        .. escape(step.title) .. "</li>"
    end
    body[#body + 1] = '<ul class="steps">' .. table.concat(items) .. "</ul>"
  end
  if plan.markdown and plan.markdown ~= "" then
    body[#body + 1] = '<article>' .. plancard.markdown(plan.markdown) .. "</article>"
  end
  body[#body + 1] = '</main><footer><button id="focus">Go to terminal</button><button id="close">Close</button></footer>'
  return table.concat({
    '<!doctype html><html><head><meta charset="utf-8">',
    "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'; ",
    "script-src 'nonce-", nonce, "'\">",
    "<style>",
    ":root { --accent: ", color, "; color-scheme: light dark; }",
    "body { margin: 0; font: 13px -apple-system, sans-serif; background: Canvas; color: CanvasText;",
    " display: flex; flex-direction: column; height: 100vh; border-top: 4px solid var(--accent); }",
    "header { display: flex; align-items: baseline; gap: 8px; padding: 10px 14px 4px; }",
    "header h2 { font-size: 14px; margin: 0; flex: 1; }",
    ".count { color: var(--accent); font-weight: 600; }",
    "main { overflow: auto; padding: 0 14px 10px; flex: 1; }",
    ".steps { list-style: none; padding: 0; margin: 6px 0 12px; }",
    ".steps li { padding: 3px 0; } .steps .mark { display: inline-block; width: 20px; color: var(--accent); }",
    ".steps .done { opacity: 0.6; text-decoration: line-through; } .steps .active { font-weight: 600; }",
    "article { border-top: 1px solid color-mix(in srgb, CanvasText 15%, transparent); padding-top: 4px; }",
    "pre { background: color-mix(in srgb, CanvasText 7%, transparent); padding: 8px; overflow: auto; border-radius: 6px; }",
    "code { font: 12px Menlo, monospace; } table { border-collapse: collapse; }",
    "th, td { border: 1px solid color-mix(in srgb, CanvasText 20%, transparent); padding: 3px 6px; text-align: left; }",
    "blockquote { margin: 0; padding-left: 10px; border-left: 3px solid var(--accent); opacity: 0.8; }",
    ".link { text-decoration: underline; }",
    "footer { display: flex; gap: 8px; justify-content: flex-end; padding: 8px 14px; }",
    "button { font: inherit; padding: 4px 12px; }",
    "#focus { background: var(--accent); color: white; border: 0; border-radius: 5px; }",
    "</style></head><body>",
    table.concat(body),
    '<script nonce="', nonce, '">', plancard.SCRIPT, "</script>",
    "</body></html>",
  })
end

-- The page's one script: its buttons and Esc tell the Spoon, through the "deskmates" message handler.
plancard.SCRIPT = "function send(m){window.webkit.messageHandlers.deskmates.postMessage(m)}"
  .. "document.getElementById('focus').onclick=function(){send('focus')};"
  .. "document.getElementById('close').onclick=function(){send('close')};"
  .. "document.addEventListener('keydown',function(e){if(e.key==='Escape')send('close')});"

local PlanCard = {}
PlanCard.__index = PlanCard
plancard.PlanCard = PlanCard

-- opts.onFocus(key): the card's "Go to terminal". opts.frameFor(key, w, h): where the card goes, beside its puppet.
function plancard.new(opts)
  return setmetatable({ onFocus = opts.onFocus, frameFor = opts.frameFor }, PlanCard)
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
  local view = hs.webview.new(self.frameFor(key, WIDTH, HEIGHT), { developerExtrasEnabled = false }, content)
  view:windowStyle({ "titled", "closable", "utility" })
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
