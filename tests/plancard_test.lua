-- The plan card's page: the checklist and the plan's markdown as HTML, everything from the agent escaped, so
-- a plan can never run script or lead the card elsewhere.

local root = arg[0]:match("^(.*)/tests/") or "."
package.path = root .. "/Deskmates.spoon/lib/?.lua;" .. root .. "/Deskmates.spoon/lib/?/init.lua;" .. package.path
local check = dofile(root .. "/tests/support/check.lua")
local plancard = require("puppet.ui.plancard")

local function has(html, text) return html:find(text, 1, true) ~= nil end

-- markdown: the subset plans use.
local md = plancard.markdown(table.concat({
  "# Add a flag",
  "",
  "Some **bold**, *italic* and `code` text,",
  "on two lines.",
  "",
  "- one",
  "- [x] done",
  "- [ ] open",
  "",
  "1. first",
  "2. second",
  "",
  "```sh",
  "echo <hi> && exit",
  "```",
  "",
  "> a quote",
  "",
  "| Step | Change |",
  "| --- | --- |",
  "| `a.sh` | Fixed the typo. |",
  "",
  "See [the docs](https://example.com/x).",
  "",
  "---",
}, "\n"))
check("markdown: a heading", has(md, "<h1>Add a flag</h1>"))
check("markdown: bold, italic and code", has(md, "<strong>bold</strong>") and has(md, "<em>italic</em>")
  and has(md, "<code>code</code>"))
check("markdown: a paragraph's lines are one paragraph", has(md, "<p>Some <strong>bold</strong>, <em>italic</em> and <code>code</code> text, on two lines.</p>"))
check("markdown: a list", has(md, "<ul><li>one</li>"))
check("markdown: task boxes", has(md, "<li>☑ done</li>") and has(md, "<li>☐ open</li>"))
check("markdown: a numbered list", has(md, "<ol><li>first</li><li>second</li></ol>"))
check("markdown: a code block, escaped", has(md, "<pre><code>echo &lt;hi&gt; &amp;&amp; exit</code></pre>"))
check("markdown: a quote", has(md, "<blockquote>a quote</blockquote>"))
check("markdown: a table", has(md, "<table><tr><th>Step</th><th>Change</th></tr><tr><td><code>a.sh</code></td><td>Fixed the typo.</td></tr></table>"))
check("markdown: a link is text, never followed", has(md, '<span class="link">the docs</span>') and not has(md, "href"))
check("markdown: a rule", has(md, "<hr>"))

-- Nothing the agent wrote runs.
local evil = plancard.markdown('<script>alert(1)</script>\n\n<img src=x onerror="alert(1)">\n\n[x](javascript:alert(1))\n\n**<b>**')
check("escaped: no script tag", not has(evil, "<script"))
check("escaped: no img tag", not has(evil, "<img"))
check("escaped: a link's address is dropped", not has(evil, "javascript:") and not has(evil, "href"))
check("escaped: html inside bold", has(evil, "<strong>&lt;b&gt;</strong>"))

-- The whole page.
local page = plancard.html({
  steps = {
    { id = "1", title = "Write the failing test", status = "done" },
    { id = "2", title = "Fix <it>", status = "active" },
    { id = "3", title = "Run the tests", status = "pending" },
  },
  markdown = "# Plan\n\n</script><script>alert(1)</script>",
}, { title = "my-app <b>", color = "#D97757" })
check("page: the title, escaped", has(plancard.html({ steps = {}, markdown = "Text." }, { title = "my-app <b>" }), "my-app &lt;b&gt;"))
check("page: the checklist with its marks", has(page, "☑") and has(page, "▶") and has(page, "☐"))
check("page: a step's title escaped", has(page, "Fix &lt;it&gt;"))
check("page: progress", has(page, "1/3"))
check("page: the plan's heading is its title", has(page, 'class="title">Plan<'))
local scripts = 0
for _ in page:gmatch("<script") do scripts = scripts + 1 end
check("page: only its own script", scripts == 1)
check("page: a policy that allows no other script", has(page, "Content-Security-Policy") and has(page, "default-src 'none'"))
check("page: the buttons", has(page, "Go to terminal") and has(page, "Close"))
check("page: the colour only as a colour", has(page, "#D97757"))
local odd = plancard.html({ steps = {} }, { title = "x", color = 'red;}</style><script>' })
check("page: a colour that is not one is dropped", not has(odd, "</style><script>"))
check("page: no steps, no checklist", not has(plancard.html({ steps = {}, markdown = "# P" }, { title = "x" }), "☐"))

-- The page reads like a plan: a header, its sections, the checklist beside it.
local STEPS = {
  { id = "1", title = "Write the failing test", status = "done" },
  { id = "2", title = "Add the flag", status = "active" },
  { id = "3", title = "Run the tests", status = "pending" },
}
local function count(text, what)
  local n, at = 0, 1
  while true do
    local s, e = text:find(what, at, true)
    if not s then return n end
    n, at = n + 1, e + 1
  end
end
local full = plancard.html({ steps = STEPS,
  markdown = "# Add a --version flag\n\n`bin/deskmates --version` prints it.\n\n## Files\n\n- a\n\n## Steps\n\n- b" },
  { title = "my-app", color = "#D97757" })
local header = full:match("<header>(.-)</header>") or ""
local article = full:match("<article>(.-)</article>") or ""
check("page: the label", has(header, ">PLAN<"))
check("page: the plan's heading is the title", has(header, "Add a --version flag") and not has(full, "<h1>"))
check("page: the first paragraph is the summary", has(header, '<p class="summary"><code>bin/deskmates --version</code> prints it.</p>')
  and count(full, "prints it.") == 1)
check("page: a progress bar", has(header, '<progress value="1" max="3">') and has(header, "1/3"))
check("page: contents from ## headings", has(article, '<h2 id="sec-1">Files</h2>') and has(article, '<h2 id="sec-2">Steps</h2>')
  and has(full, 'data-to="sec-1">Files</button>') and has(full, 'data-to="sec-2">Steps</button>'))
check("page: the contents scroll, never navigate", has(plancard.SCRIPT, "scrollIntoView") and not has(full, "href"))
local aside, checklist, art = full:find("<aside>", 1, true), full:find('class="checklist"', 1, true), full:find("<article>", 1, true)
check("page: the checklist sits in the aside, after the contents", aside and checklist and art
  and aside < checklist and checklist < art and full:find("data-to", 1, true) < checklist)
local plain = plancard.html({ steps = {}, markdown = "## Context\n\nWhy." }, { title = "my-app" })
check("page: no heading first, the session's title and no summary", has(plain:match("<header>(.-)</header>") or "", "my-app")
  and not has(plain, 'class="summary"') and has(plain, "<p>Why.</p>"))
check("page: no steps, no progress", not has(plain, "<progress"))
check("page: one ## heading, no contents", not has(plancard.html({ steps = {}, markdown = "# T\n\n## Only" }, { title = "x" }), "data-to=\""))
local hostile = plancard.html({ steps = {}, markdown = "## a <script>x</script>\n\n## b" }, { title = "x" })
check("page: a heading in the contents is escaped", has(hostile, "a &lt;script&gt;x&lt;/script&gt;</button>") and count(hostile, "<script") == 1)

-- The card's size, as saved: junk gives the default, too small is raised.
local function size(saved) local got = plancard.fitSize(saved) return got.w .. "x" .. got.h end
check("fitSize: nil gives the default", size(nil) == "600x560")
check("fitSize: a string gives the default", size("big") == "600x560")
check("fitSize: no numbers give the default", size({ w = "a", h = 3 }) == "600x560")
check("fitSize: a size is kept", size({ w = 700.6, h = 500 }) == "700x500")
check("fitSize: too small is raised", size({ w = 10, h = 10 }) == "320x280")

-- The file map, drawn from escaped text, with its source a click away.
local mapped = plancard.html({ steps = {}, markdown = "## Files\n\n- Create: `bin/x.sh`" }, { title = "x" })
check("file map: drawn", has(mapped, 'class="filemap"') and has(mapped, "<code>bin/x.sh</code>") and has(mapped, 'class="badge new"'))
check("file map: its source a click away", has(mapped, '<details class="source">') and has(mapped, "<pre><code>- Create: `bin/x.sh`</code></pre>"))
check("file map: under Files, no second label", not has(mapped, ">FILES<"))
check("file map: a table of files gets its label", has(plancard.html({ steps = {},
  markdown = "| File | Change |\n|---|---|\n| `a/b.sh` | new |" }, { title = "x" }), ">FILES<"))
local nasty = plancard.html({ steps = {}, markdown = "## Files\n\n- `a/<b>.sh` — <i>x</i>" }, { title = "x" })
check("file map: escaped", has(nasty, "<code>a/&lt;b&gt;.sh</code>") and has(nasty, "&lt;i&gt;x&lt;/i&gt;") and not has(nasty, "<i>"))

-- Endpoint rows, drawn from escaped text.
local api = plancard.html({ steps = {}, markdown = "## API\n\n- POST /a → 201" }, { title = "x" })
check("endpoints: drawn", has(api, 'class="method post">POST<') and has(api, "<code>/a</code>") and has(api, 'class="status">201<')
  and has(api, '<details class="source">'))
local rude = plancard.html({ steps = {}, markdown = "POST /a/<x> → 201 — <b>" }, { title = "x" })
check("endpoints: escaped", has(rude, "<code>/a/&lt;x&gt;</code>") and not has(rude, "<b>"))

-- Review fix: a long first paragraph stays in the plan, whole, instead of a clipped summary.
local long = string.rep("This plan explains a lot of things at length. ", 8)
local longPage = plancard.html({ steps = {}, markdown = "# Title\n\n" .. long }, { title = "x" })
check("page: a long first paragraph is no summary", not has(longPage, 'class="summary"')
  and has(longPage:match("<article>(.-)</article>") or "", "at length."))
check("page: no summary is clipped", not has(longPage, "line-clamp"))

-- A click in the contents always shows something: the last section can scroll to the top, and the heading it
-- went to lights up for a moment.
check("contents: room to scroll the last section to the top", has(full, "article::after"))
check("contents: the heading clicked lights up", has(plancard.SCRIPT, "classList.add('here')") and has(full, "h2.here"))

-- The session: what changed first (the plan block), then the header (ticket, strip, NOW), then the story ("What
-- happened?"), then the plan when there is one.
local sessioncard = require("puppet.ui.sessioncard")
local workcard = require("puppet.ui.workcard")
local story = require("puppet.ui.story")
local facts = { current = "ABC-12", tickets = { ["ABC-12"] = { phase = "dev", phaseAt = 100, phases = { dev = 100 }, seen = 200,
  passes = { { phase = "dev", at = 100 } } } },
  timeline = { { at = 200, ticket = "ABC-12", kind = "reply", text = "Fixed the typo.", phase = "dev" },
               { at = 100, ticket = "ABC-12", kind = "subagent", text = "Implement ABC-12", phase = "dev" } } }
local view = sessioncard.view(facts, 300)
local STORY = story.html(story.view(view, nil, 300))
local only = plancard.html(nil, { title = "my-app", session = view, story = STORY })
local onlyHeader = only:match("<header>(.-)</header>") or ""
check("session: the ticket and strip in the header", has(onlyHeader, "ABC-12") and has(onlyHeader, 'data-phase="dev"')
  and has(onlyHeader, "NOW"))
check("session, no plan: the story fills the card", has(only, '<div class="panels"><details class="panel story"')
  and has(only, "<h2>What happened?</h2>") and has(only, "Implement ABC-12")
  and not has(only, "<article>") and not has(only, ">PLAN<"))
check("session: the step filter's rows in the story", has(only, '<li class="marker" data-at="100">')
  and (only:find('data-panel="story"', 1, true) or math.huge) < (only:find('data-at="100">', 1, true) or 0))
local both = plancard.html({ steps = STEPS, markdown = "# Add a flag\n\n## Files\n\n- a" },
  { title = "my-app", session = view, story = STORY })
check("session and plan: the plan shows", has(both, 'id="plan"') and has(both, "<article>") and has(both, ">PLAN<")
  and has(both, "ABC-12"))
check("session and plan: the story shows too, above the plan", has(both, 'data-panel="story" open>')
  and (both:find('data-panel="story"', 1, true) or math.huge) < (both:find(">PLAN<", 1, true) or 0))
check("no session: no story panel", not has(full, 'data-panel="story"') and not has(full, 'class="session"')
  and not has(full, 'class="panels'))
check("session: hidden really hides", has(both, "[hidden] { display: none !important; }"))
local evilView = sessioncard.view({ current = "ABC-1", tickets = { ["ABC-1"] = { seen = 1, phases = {} } },
  timeline = { { at = 1, ticket = "ABC-1", kind = "reply", text = "</script><script>alert(1)</script>" } } }, 1)
local evilPage = plancard.html(nil, { title = "x", session = evilView, story = story.html(story.view(evilView, nil, 1)) })
check("session: escaped on the page", count(evilPage, "<script") == 1 and has(evilPage, "default-src 'none'"))
-- Cassio (6 Nov): the card opens on the step happening now; the reader's own pick is drawn again on a redraw.
check("pick: the current step drawn picked", has(onlyHeader, 'class="phase current on" data-phase="dev"'))
local keptNone = plancard.html(nil, { title = "my-app", session = view, story = STORY }, nil, "none")
check("pick: the reader's none drawn as none", not has(keptNone, 'class="phase current on"') and has(keptNone, 'class="phase current"'))
check("script: the PR's button asks the Spoon to open it", has(plancard.SCRIPT, "button.pr-open")
  and has(plancard.SCRIPT, "send('open:pr')"))
check("script: Also switches tickets", has(plancard.SCRIPT, "select.also") and has(plancard.SCRIPT, "data-key"))
-- Live (6 Nov): Review, Dev, then Review again moved the page: each phase click brought the activity panel into view.
-- A phase click now filters in place: the panels stay where the reader left them.
local phaseClick = plancard.SCRIPT:match("button%.phase'%)%.forEach%(function%(b%){b%.onclick=function%(%)(.-)}}%);") or ""
check("script: a phase click scrolls nothing", phaseClick ~= "" and not has(phaseClick, "scrollIntoView"))
check("script: a phase click keeps the panels' scroll position", has(phaseClick, "panels.scrollTop=top"))
check("script: a phase click filters the story's rows only", has(plancard.SCRIPT, ".storylist>li")
  and not has(plancard.SCRIPT, ".timeline li") and not has(plancard.SCRIPT, ".turnlist"))
-- Review: a strip hidden at load has no width, so Also scrolls the strip of the ticket it shows to its newest step.
local alsoChange = plancard.SCRIPT:match("also%.onchange=function%(%)(.-)};") or ""
check("script: Also scrolls the shown ticket's strip to its end", has(alsoChange, "scrollLeft=s.scrollWidth"))
check("script: Also filters by the shown ticket's picked step", has(alsoChange, "picked()"))
check("script: a picked lane is told to the page", has(plancard.SCRIPT, "classList.toggle('lane'"))
check("script: a phase click filters the story, or goes to the plan", has(plancard.SCRIPT, "button.phase")
  and has(plancard.SCRIPT, "data-phase") and has(plancard.SCRIPT, "getElementById('plan')")
)
-- Live (6 Nov): the activity folded, a lane picked, then another, opened it again. A fold is the reader's alone.
check("script: a phase click opens and folds nothing", phaseClick ~= "" and not has(phaseClick, ".open="))
check("script: the story filtered to the step drawn picked, at load", has(plancard.SCRIPT, "'.ticket:not([hidden]) button.phase.on'"))
check("script: a step click tells the Spoon", has(phaseClick, "send('step:'+f)") and has(phaseClick, "send('step:none')"))
-- A <details> drawn open fires toggle on load: only a change from the state drawn is told, so a redraw sends nothing.
check("script: only a user's fold is told", has(plancard.SCRIPT, "var was=d.open;")
  and has(plancard.SCRIPT, "if(d.open===was)return;was=d.open;"))
-- The body never scrolls: Plan takes the plan's article (the part that scrolls) back to its top.
check("script: Plan scrolls the plan's article to its top", has(plancard.SCRIPT, "plan.querySelector('article')")
  and has(plancard.SCRIPT, ".scrollTop=0") and not has(plancard.SCRIPT, "plan.scrollIntoView"))
-- Live (6 Nov): Dev, Review, Dev again: a click on Dev mixed both Dev passes. A step filters by its own span now.
check("script: a step filters by time, not by phase", has(phaseClick, "data-from") and has(plancard.SCRIPT, "data-at")
  and not has(plancard.SCRIPT, "getAttribute('data-phase')!==p"))
check("script: the contents' jumps leave the steps alone", has(plancard.SCRIPT, "'button[data-to]:not(.phase)'"))
check("script: each strip shows its newest step", has(plancard.SCRIPT, "scrollLeft=s.scrollWidth"))
-- The script itself, run with node when this Mac has it: it parses, and a step click keeps the rows of its span.
local node = io.popen("command -v node 2>/dev/null"):read("l")
if node and node ~= "" then
  local function run(js)
    local path = os.tmpname()
    local h = io.open(path, "w")
    h:write(js)
    h:close()
    local pipe = io.popen("'" .. node .. "' '" .. path .. "' 2>&1; echo \"|$?\"")
    local out = pipe:read("a")
    pipe:close()
    local checked = io.popen("'" .. node .. "' --check '" .. path .. "' 2>&1; echo \"|$?\""):read("a")
    os.remove(path)
    return out, checked
  end
  local DOM = [[
function cl(){var s={};return{add:function(c){s[c]=1},remove:function(c){delete s[c]},contains:function(c){return !!s[c]},
  toggle:function(c,f){if(f===undefined)f=!s[c];if(f)s[c]=1;else delete s[c];return f}}}
function el(attrs){return{attrs:attrs||{},classList:cl(),getAttribute:function(n){return n in this.attrs?this.attrs[n]:null},
  hasAttribute:function(n){return n in this.attrs},scrollTop:0,scrollLeft:0,scrollWidth:500}}
var steps=[el({'data-phase':'plan'}),el({'data-phase':'dev','data-from':'10','data-to':'30'}),
  el({'data-phase':'review','data-from':'30','data-to':'40'}),el({'data-phase':'dev','data-from':'40'})];
var strip=el(),panels=el(),article=el(),plan=el();plan.querySelector=function(){return article};
strip.querySelectorAll=function(){return steps};
steps.forEach(function(s){s.classList.add('phase');s.parentNode=strip});
steps[3].classList.add('on');
var rows=[5,10,12,29,30,39,40,45,99].map(function(a){return el({'data-at':String(a)})})
  .concat([ ['25','35'], ['38',''], ['2','8'] ].map(function(p){return el({'data-at':p[0],'data-end':p[1]})}));
var ids={focus:el(),close:el(),plan:plan};
var document={body:el(),getElementById:function(i){return ids[i]||null},addEventListener:function(){},
  querySelector:function(q){return q==='.panels'?panels:q==='.ticket:not([hidden]) button.phase.on'
    ?steps.filter(function(s){return s.classList.contains('on')})[0]||null:null},
  querySelectorAll:function(q){return q==='button.phase'?steps:q==='.storylist>li'?rows:q==='.strip'?[strip]:[]}};
var sent=[];
var window={webkit:{messageHandlers:{deskmates:{postMessage:function(m){sent.push(m)}}}}};
function kept(){return rows.filter(function(r){return !r.classList.contains('out')})
  .map(function(r){return r.attrs['data-at']}).join(',')}
]]
  local out, checked = run(DOM .. plancard.SCRIPT .. [[
;var log=[];log.push(strip.scrollLeft,kept(),document.body.classList.contains('lane'),sent.length);
panels.scrollTop=70;steps[1].onclick();log.push(kept(),document.body.classList.contains('lane'),panels.scrollTop);
steps[3].onclick();log.push(kept());
steps[2].onclick();log.push(kept());
steps[2].onclick();log.push(kept(),document.body.classList.contains('lane'));
article.scrollTop=50;steps[0].onclick();log.push(kept(),article.scrollTop);
ids.plan=null;steps[0].onclick();log.push(kept(),document.body.classList.contains('lane'));
log.push(sent.join(' '));
console.log(log.join('/'))]])
  check("script: node parses it", checked == "|0\n")
  -- Review (6 Nov): a step mostly starts inside a turn (its subagent call): a turn stays while it overlaps the step
  -- (its end, data-end, empty while it runs); a line or a reply stays when it happened during the step.
  check("script: the step drawn picked filters at load; a step keeps the lines from its start to the next one's and "
    .. "the turns that overlap it, an ahead step none", out == "500/40,45,99,38/true/0/10,12,29,25/true/70/40,45,99,38/"
    .. "30,39,25,38/5,10,12,29,30,39,40,45,99,25,38,2/false/5,10,12,29,30,39,40,45,99,25,38,2/0//true/"
    .. "step:10 step:40 step:30 step:none step:none step:none\n|0\n")
end
check("script: a fold tells the Spoon", has(plancard.SCRIPT, "details.panel")
  and has(plancard.SCRIPT, "send('fold:'+d.getAttribute('data-panel')+':'+(d.open?'open':'closed'))"))

-- The plan block (meta.work, workcard.html) first, above the header: what changed is the session's, whatever the
-- step picked.
local function at(h, m) return os.time({ year = 2026, month = 11, day = 5, hour = h, min = m, sec = 0 }) end
local workView = workcard.view({ tickets = {}, timeline = {}, seen = {},
  git = { root = "/r", base = "a1b2c3d4e5f6", dirtyAtStart = {} },
  turns = { { at = at(9, 0), endAt = at(9, 4), files = { "a.js" }, tests = { ran = 0, passed = 0, failed = 0 }, commits = {} } } },
  { reading = true }, nil, false)
local WORK = workcard.html(workView)
local WORKSTORY = story.html(story.view(nil, workView, at(10, 0)))
local workOnly = plancard.html(nil, { title = "my-app", work = WORK, story = WORKSTORY })
check("work, no plan or tickets: the card shows it", has(workOnly, WORK) and has(workOnly, WORKSTORY) and not has(workOnly, ">PLAN<")
  and not has(workOnly, 'class="session"') and has(workOnly, "Go to terminal"))
check("work: its styles", has(workOnly, ".actual") and has(workOnly, ".unseen") and has(workOnly, ".panel {")
  and has(workOnly, ".storylist"))
local workAll = plancard.html({ steps = STEPS, markdown = "# Add a flag\n\n## Files\n\n- a" },
  { title = "my-app", session = view, work = WORK, story = STORY })
local aAt, sAt, vAt, pAt = workAll:find('data-panel="actual"', 1, true), workAll:find('class="strip"', 1, true),
  workAll:find('data-panel="story"', 1, true), workAll:find(">PLAN<", 1, true)
check("panels: what changed, the strip, the story, then the plan", aAt and sAt and vAt and pAt
  and aAt < sAt and sAt < vAt and vAt < pAt)
check("what changed: in its own box above the header", has(workAll, '<div class="result capped"><details class="panel actual"')
  and (workAll:find('<div class="result', 1, true) or math.huge) < (workAll:find("<header>", 1, true) or 0)
  and has(workOnly, '<div class="result"><details'))
check("what changed: open, it scrolls in a third of the card", workAll:match("%.result {[^}]*max%-height: 35vh[^}]*overflow: auto") ~= nil)
check("what changed: a line under its box", workAll:match("%.result {[^}]*border%-bottom: 1px solid var%(%-%-faint%)[^}]*padding%-bottom: 8px") ~= nil)
check("no work: no plan block", not has(both, 'data-panel="actual"') and not has(both, 'class="result'))
-- Review (6 Nov): with a plan, what changed (35vh), the story (45vh), the headers and the footer left the plan no
-- room at 600×560 and pushed the footer out of the window. With a plan, both boxes are smaller and give way, and
-- the plan always shows some lines.
-- On a small card, what changed gives way first (four times as fast), so what happened keeps room to read.
check("with a plan: what changed in 22vh, giving way first", workAll:match("%.result%.capped {[^}]*max%-height: 22vh") ~= nil
  and workAll:match("%.result%.capped {[^}]*flex: 0 4 auto") ~= nil)
check("with a plan: the story in 30vh, giving way", workAll:match("%.panels%.capped {[^}]*max%-height: 30vh") ~= nil
  and workAll:match("%.panels%.capped {[^}]*flex: 0 1 auto") ~= nil)
-- The page's top border is inside its 100vh, so the footer ends at the window's bottom, not 4px under it.
check("the page's border inside its height", workAll:match("body {[^}]*box%-sizing: border%-box[^}]*height: 100vh[^}]*border%-top: 4px") ~= nil)
check("with a plan: the plan keeps 120px", workAll:match("#plan {[^}]*min%-height: 120px") ~= nil)
-- Cassio (6 Nov): the panels scroll in 45% of the card only when a plan follows them; with no plan they take the
-- card's full height, scrolling in it, the buttons always in view.
check("panels, no plan: no cap", has(workOnly, '<div class="panels">') and has(only, '<div class="panels">'))
check("panels and a plan: capped", has(workAll, '<div class="panels capped">'))
check("panels css: fill the card, capped only before a plan", has(workAll, ".panels { flex: 1; min-height: 0; overflow: auto;")
  and not has(workAll, "45vh"))
check("a fixed page, the footer always in view", has(workOnly, "<body>") and has(only, "<body>") and not has(workAll, "free"))

-- Folded panels (PlanCard's set for the session shown) are drawn closed; the others open.
local foldedPage = plancard.html({ steps = STEPS, markdown = "# Add a flag\n\n## Files\n\n- a" },
  { title = "my-app", session = view, work = WORK, story = STORY }, { story = true })
check("folded: drawn closed", has(foldedPage, '<details class="panel story" data-panel="story"><summary>')
  and has(foldedPage, '<details class="panel actual" data-panel="actual" open>'))
check("folded: nothing folded, all open", count(workAll, '" open><summary>') == 2)

check.done("plan card")
