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

check.done("plan card")
