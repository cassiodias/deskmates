-- The card's foldable panels: their markup, the fold kept across redraws, and the page's fold message read strictly.

local root = arg[0]:match("^(.*)/tests/") or "."
package.path = root .. "/Deskmates.spoon/lib/?.lua;" .. root .. "/Deskmates.spoon/lib/?/init.lua;" .. package.path
local check = dofile(root .. "/tests/support/check.lua")
local panel = require("puppet.ui.panel")

local function has(html, text) return html:find(text, 1, true) ~= nil end

local p = panel.html("story", "What <happened>?", "4 turns", "<ol></ol>")
check("html: a details open by default, chevron, title, summary, body", p == '<details class="panel story" data-panel="story" open>'
  .. '<summary><span class="chev">›</span><h2>What &lt;happened&gt;?</h2><span class="sum">4 turns</span></summary>'
  .. '<div class="panel-body"><ol></ol></div></details>')

-- One timeline now: the story replaced the turns and the activity.
check("ids: the plan block and the story", panel.IDS.actual and panel.IDS.story and not panel.IDS.turns and not panel.IDS.activity)
local page = panel.html("actual", "A", "a", "x") .. panel.html("story", "T", "t", "y")
local folded = panel.fold(page, { story = true })
check("fold: a folded panel has no open", has(folded, '<details class="panel story" data-panel="story"><summary>')
  and has(folded, '<details class="panel actual" data-panel="actual" open>'))
check("fold: nothing folded, the page as it was", panel.fold(page, {}) == page and panel.fold(page, nil) == page)
check("fold: an unknown id does nothing", panel.fold(page, { plan = true }) == page)

local function msg(body) return { panel.message(body) } end
check("message: fold a panel", msg("fold:story:closed")[1] == "story" and msg("fold:story:closed")[2] == true)
check("message: open it again", msg("fold:actual:open")[1] == "actual" and msg("fold:actual:open")[2] == false)
for _, junk in ipairs({ "fold:plan:closed", "fold:turns:closed", "fold:activity:open", "fold:story:shut",
  "fold:story:closed:x", "fold:story:closedx", " fold:story:closed", "fold:Story:closed", "fold::closed", "focus", "", 42, nil, {} }) do
  check("message: junk ignored (" .. tostring(junk) .. ")", panel.message(junk) == nil)
end

check("css: bordered, rounded, apart", has(panel.CSS, ".panel { border: 1px solid var(--faint); border-radius: 10px;")
  and panel.CSS:match("%.panels {[^}]*gap") ~= nil)
check("css: a sentence-case heading", panel.CSS:match("%.panel > summary h2 {[^}]*15px[^}]*600") ~= nil)
check("css: the chevron is plain to see", panel.CSS:match("%.panel > summary > %.chev {[^}]*font%-size: 13px[^}]*color: CanvasText") ~= nil)
check("css: the chevron turns when open", panel.CSS:match("%.panel%[open%] > summary > %.chev {[^}]*rotate%(90deg%)") ~= nil)
-- The question is never squeezed: the summary sits beside it when it fits, else wraps onto its own line.
check("css: the header wraps", panel.CSS:match("%.panel > summary {[^}]*flex%-wrap: wrap") ~= nil)
check("css: the title keeps its width", panel.CSS:match("%.panel > summary h2 {[^}]*flex: 0 0 auto") ~= nil)
check("css: the summary muted, on the right", panel.CSS:match("%.panel > summary %.sum {[^}]*margin%-left: auto[^}]*var%(%-%-muted%)") ~= nil)
check("css: focus shows", panel.CSS:match("%.panel > summary:focus%-visible {[^}]*outline") ~= nil)

check.done("panel")
