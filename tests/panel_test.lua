-- The card's foldable panels: their markup, the fold kept across redraws, and the page's fold message read strictly.

local root = arg[0]:match("^(.*)/tests/") or "."
package.path = root .. "/Deskmates.spoon/lib/?.lua;" .. root .. "/Deskmates.spoon/lib/?/init.lua;" .. package.path
local check = dofile(root .. "/tests/support/check.lua")
local panel = require("puppet.ui.panel")

local function has(html, text) return html:find(text, 1, true) ~= nil end

local p = panel.html("turns", "What did <each> turn do?", "4 turns", "<ol></ol>")
check("html: a details open by default, chevron, title, summary, body", p == '<details class="panel turns" data-panel="turns" open>'
  .. '<summary><span class="chev">›</span><h2>What did &lt;each&gt; turn do?</h2><span class="sum">4 turns</span></summary>'
  .. '<div class="panel-body"><ol></ol></div></details>')

local page = panel.html("actual", "A", "a", "x") .. panel.html("turns", "T", "t", "y") .. panel.html("activity", "W", "w", "z")
local folded = panel.fold(page, { turns = true })
check("fold: a folded panel has no open", has(folded, '<details class="panel turns" data-panel="turns"><summary>')
  and has(folded, '<details class="panel actual" data-panel="actual" open>')
  and has(folded, '<details class="panel activity" data-panel="activity" open>'))
check("fold: nothing folded, the page as it was", panel.fold(page, {}) == page and panel.fold(page, nil) == page)
check("fold: an unknown id does nothing", panel.fold(page, { plan = true }) == page)

local function msg(body) return { panel.message(body) } end
check("message: fold a panel", msg("fold:turns:closed")[1] == "turns" and msg("fold:turns:closed")[2] == true)
check("message: open it again", msg("fold:activity:open")[1] == "activity" and msg("fold:activity:open")[2] == false)
for _, junk in ipairs({ "fold:plan:closed", "fold:turns:shut", "fold:turns:closed:x", "fold:turns:closedx", " fold:turns:closed",
  "fold:Turns:closed", "fold::closed", "focus", "", 42, nil, {} }) do
  check("message: junk ignored (" .. tostring(junk) .. ")", panel.message(junk) == nil)
end

check("css: bordered, rounded, apart", has(panel.CSS, ".panel { border: 1px solid var(--faint); border-radius: 10px;")
  and panel.CSS:match("%.panels {[^}]*gap") ~= nil)
check("css: a sentence-case heading", panel.CSS:match("%.panel > summary h2 {[^}]*15px[^}]*600") ~= nil)
check("css: the chevron turns when open", panel.CSS:match("%.panel%[open%] > summary > %.chev {[^}]*rotate%(90deg%)") ~= nil)
check("css: the summary muted, on the right", panel.CSS:match("%.panel > summary %.sum {[^}]*margin%-left: auto[^}]*var%(%-%-muted%)") ~= nil)
check("css: focus shows", panel.CSS:match("%.panel > summary:focus%-visible {[^}]*outline") ~= nil)

check.done("panel")
