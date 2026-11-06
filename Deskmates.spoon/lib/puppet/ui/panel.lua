-- The card's foldable panels: each block (did it change what the plan said, what happened) is a <details> with
-- its question and a short summary that still says something folded. The page tells the Spoon when one folds
-- ("fold:story:closed"); panel.message reads that strictly, and panel.fold draws the
-- folded ones closed when the card is drawn again. It knows no Hammerspoon.

local panel = {}

-- The panels a fold message may name.
panel.IDS = { actual = true, story = true }

local function escape(text)
  return (text:gsub("[&<>\"']", { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&#39;" }))
end

local function opening(id, open)
  return '<details class="panel ' .. id .. '" data-panel="' .. id .. '"' .. (open and " open" or "") .. ">"
end

-- Panel `id` (one of IDS), open: `title` (text), `summary` (HTML, its texts already escaped) and `body` (HTML).
function panel.html(id, title, summary, body)
  return opening(id, true) .. '<summary><span class="chev">›</span><h2>' .. escape(title) .. '</h2><span class="sum">'
    .. summary .. '</span></summary><div class="panel-body">' .. body .. "</div></details>"
end

-- Page `html` with the panels in set `folded` ({ [id] = true }) drawn closed. Every text on the page is escaped,
-- so only a panel's own opening tag can match.
function panel.fold(html, folded)
  for id in pairs(folded or {}) do
    if panel.IDS[id] then
      local from = opening(id, true)
      local at = html:find(from, 1, true)
      if at then html = html:sub(1, at - 1) .. opening(id, false) .. html:sub(at + #from) end
    end
  end
  return html
end

-- A page message "fold:<id>:closed" or "fold:<id>:open": the panel's id and whether it is folded; nil for anything
-- else.
function panel.message(body)
  if type(body) ~= "string" then return nil end
  local id, state = body:match("^fold:(%l+):(%l+)$")
  if not panel.IDS[id] or (state ~= "closed" and state ~= "open") then return nil end
  return id, state == "closed"
end

panel.CSS = table.concat({
  ".panels { flex: 1; min-height: 0; overflow: auto; display: flex; flex-direction: column; gap: 10px;",
  " padding: 10px 14px; } .panels.capped { flex: none; max-height: 45vh; }",
  ".panel { border: 1px solid var(--faint); border-radius: 10px; padding: 0 12px; flex: none; }",
  ".panel > summary { list-style: none; cursor: pointer; display: flex; flex-wrap: wrap; align-items: baseline;",
  " gap: 4px 8px; padding: 10px 0; }",
  ".panel > summary::-webkit-details-marker { display: none; }",
  ".panel > summary:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; border-radius: 6px; }",
  ".panel > summary > .chev { display: inline-block; width: 12px; font-size: 13px; font-weight: 700; color: CanvasText;",
  " line-height: 1; text-align: center; transform: scale(1.5); transition: transform 0.12s; }",
  ".panel[open] > summary > .chev { transform: rotate(90deg) scale(1.5); }",
  -- The question keeps its width (wrapping only when the card is narrower than it); the summary sits beside it
  -- when it fits, else on its own line, still on the right.
  ".panel > summary h2 { display: inline; font-size: 15px; font-weight: 600; margin: 0; flex: 0 0 auto;",
  " max-width: calc(100% - 20px); }",
  ".panel > summary .sum { margin-left: auto; font-size: 12px; color: var(--muted); text-align: right; }",
  ".panel-body { padding-bottom: 12px; }",
})

return panel
