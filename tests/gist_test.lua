-- A step's document in a few lines for its card: its title, the paragraph that says what it is about, the verdict
-- of its last review round, and the button that opens it; every text escaped, the file read only so far.

local root = arg[0]:match("^(.*)/tests/") or "."
package.path = root .. "/Deskmates.spoon/lib/?.lua;" .. root .. "/Deskmates.spoon/lib/?/init.lua;" .. package.path
dofile(root .. "/tests/support/hs_stub.lua")
local check = dofile(root .. "/tests/support/check.lua")
local gist = require("puppet.ui.gist")

local function has(s, part) return s:find(part, 1, true) ~= nil end

local CONTRACT = table.concat({
  "# Contract ABC-12: Export limit",
  "",
  "Version 2 · Status: approved",
  "",
  "## 1 Intent",
  "",
  "Exports are **capped** at 10 000 rows per request, so a big",
  "account no longer times out. See `limits.md`.",
  "",
  "Second paragraph, not in the gist.",
  "",
  "## 2 Scope",
  "Everything else.",
}, "\n")
local g = gist.parse(CONTRACT, "contract.md")
check("title: the first # heading", g.title == "Contract ABC-12: Export limit")
check("summary: the paragraph under Intent, its lines joined, markdown stripped",
  g.summary == "Exports are capped at 10 000 rows per request, so a big account no longer times out. See limits.md.")
check("file: its name", g.file == "contract.md")
check("no verdict, no round", g.verdict == nil and g.round == nil)

for _, heading in ipairs({ "## Summary", "## what changed", "### Goal", "## 3. Context", "## Overview" }) do
  local p = gist.parse("# T\n\nIntro.\n\n" .. heading .. "\nThe point.\n", "x.md")
  check("summary under " .. heading, p.summary == "The point.")
end
check("no such heading: the first paragraph after the title",
  gist.parse("# T\n\nIntro line.\nMore.\n\n## Scope\nNo.\n", "x.md").summary == "Intro line. More.")
check("no title: the file name", gist.parse("Just text.\n", "notes.md").title == "notes.md")
check("links keep their text only", gist.parse("# T\n\n[the spec](javascript:alert(1)) and _this_ *one*.\n", "x.md").summary
  == "the spec and this one.")

local long = string.rep("word ", 100)
local cut = gist.parse("# T\n\n" .. long .. "\n", "x.md").summary
check("cut: 280 characters at most, at a word, with …", utf8.len(cut) <= 281 and cut:sub(-3) == "…"
  and cut:sub(-4, -4) == "d")
local accents = gist.parse("# T\n\n" .. string.rep("é", 400) .. "\n", "x.md").summary
check("cut: UTF-8 not split", utf8.len(accents) ~= nil)

local REVIEW = table.concat({
  "# Review ABC-12 - Round 1 (lens: break)",
  "**Verdict: CHANGES_REQUESTED**",
  "",
  "## Findings",
  "A hole.",
  "",
  "# Review ABC-12 - Round 2 (lens: break)",
  "**Verdict: CHANGES_REQUESTED**",
  "",
  "# Review ABC-12 - Round 3 (lens: break)",
  "**Verdict: APPROVED**",
  "",
  "## Findings",
  "None left.",
}, "\n")
local r = gist.parse(REVIEW, "review.md")
check("verdict: the last round's, in words", r.verdict == "approved")
check("round: the last", r.round == 3)
check("title: the first heading", r.title == "Review ABC-12 - Round 1 (lens: break)")
local one = gist.parse("# Review ABC-12 - Round 1\n**Verdict: CHANGES_REQUESTED**\n", "review.md")
check("one round: its verdict, no round", one.verdict == "changes requested" and one.round == nil)

-- Drawn: hidden until its step is picked, every text escaped, the button that opens the file.
local evil = gist.parse("# <script>alert(1)</script>\n\n<img src=x onerror=alert(1)>\n**Verdict: OK<b>**\n", "a<b>.md")
local html = gist.html(evil, 123)
check("html: hidden, for its step", has(html, '<div class="gist" data-from="123" hidden>'))
check("html: escaped", not has(html, "<script>") and not has(html, "<img") and not has(html, "<b>")
  and has(html, "&lt;script&gt;"))
check("html: the button opens it", has(html, '<button class="doc-open" title="Open the document">a&lt;b&gt;.md</button>'))
check("html: no link", not has(html, "href"))
local rh = gist.html(r, 5)
check("html: the verdict and its round", has(rh, '<span class="verdict">approved · round 3</span>'))

-- Read from its file: at most config.DOC_BYTES, only UTF-8 text.
local dir = os.tmpname()
os.remove(dir)
os.execute("mkdir -p '" .. dir .. "'")
local function file(name, text)
  local f = io.open(dir .. "/" .. name, "wb")
  f:write(text)
  f:close()
  return dir .. "/" .. name
end
local big = gist.read(file("big.md", "# Big\n\n" .. string.rep("a", 1024 * 1024 + 10) .. "Z\n"))
check("read: a big file, its start", big and big.title == "Big")
check("read: nothing past 256 KB is read", gist.read(file("late.md", string.rep("\n", 262200) .. "# Late\n")).title == "late.md")
check("read: a cut through a character still reads", gist.read(file("utf.md", "# É\n\n" .. string.rep("é", 200000))) ~= nil)
check("read: not UTF-8, nothing", gist.read(file("bin.md", "# T\n\n\255\254\n")) == nil)
check("read: no file, nothing", gist.read(dir .. "/nope.md") == nil)
check("read: the file's name", gist.read(file("plan.md", "Hello.\n")).file == "plan.md")
os.execute("rm -rf '" .. dir .. "'")

check.done("gist")
