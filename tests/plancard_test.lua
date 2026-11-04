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
  "| File | Change |",
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
check("markdown: a table", has(md, "<table><tr><th>File</th><th>Change</th></tr><tr><td><code>a.sh</code></td><td>Fixed the typo.</td></tr></table>"))
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
check("page: the title, escaped", has(page, "my-app &lt;b&gt;"))
check("page: the checklist with its marks", has(page, "☑") and has(page, "▶") and has(page, "☐"))
check("page: a step's title escaped", has(page, "Fix &lt;it&gt;"))
check("page: progress", has(page, "1/3"))
check("page: the plan", has(page, "<h1>Plan</h1>"))
local scripts = 0
for _ in page:gmatch("<script") do scripts = scripts + 1 end
check("page: only its own script", scripts == 1)
check("page: a policy that allows no other script", has(page, "Content-Security-Policy") and has(page, "default-src 'none'"))
check("page: the buttons", has(page, "Go to terminal") and has(page, "Close"))
check("page: the colour only as a colour", has(page, "#D97757"))
local odd = plancard.html({ steps = {} }, { title = "x", color = 'red;}</style><script>' })
check("page: a colour that is not one is dropped", not has(odd, "</style><script>"))
check("page: no steps, no checklist", not has(plancard.html({ steps = {}, markdown = "# P" }, { title = "x" }), "☐"))

check.done("plan card")
