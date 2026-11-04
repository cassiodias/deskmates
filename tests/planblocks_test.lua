-- The plan card's blocks: a plan's markdown read into blocks of raw text, and the blocks the card lifts from
-- them. Nothing here is escaped: plancard.lua escapes when it draws.

local root = arg[0]:match("^(.*)/tests/") or "."
package.path = root .. "/Deskmates.spoon/lib/?.lua;" .. root .. "/Deskmates.spoon/lib/?/init.lua;" .. package.path
local check = dofile(root .. "/tests/support/check.lua")
local planblocks = require("puppet.ui.planblocks")

local function same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local SAMPLE = table.concat({
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
}, "\n")

local blocks = planblocks.parse(SAMPLE)
check("parse: nine blocks", #blocks == 9)
check("parse: a heading", blocks[1].kind == "heading" and blocks[1].level == 1 and blocks[1].text == "Add a flag")
check("parse: a paragraph's lines, raw", blocks[2].kind == "paragraph"
  and same(blocks[2].lines, { "Some **bold**, *italic* and `code` text,", "on two lines." }))
check("parse: a list, task boxes kept", blocks[3].kind == "list" and blocks[3].ordered == false
  and same(blocks[3].items, { "one", "[x] done", "[ ] open" }))
check("parse: a numbered list", blocks[4].kind == "list" and blocks[4].ordered == true
  and same(blocks[4].items, { "first", "second" }))
check("parse: a code block, raw", blocks[5].kind == "code" and blocks[5].lang == "sh"
  and same(blocks[5].lines, { "echo <hi> && exit" }))
check("parse: a quote", blocks[6].kind == "quote" and same(blocks[6].lines, { "a quote" }))
check("parse: a table, separator dropped", blocks[7].kind == "table"
  and same(blocks[7].rows, { { "File", "Change" }, { "`a.sh`", "Fixed the typo." } }))
check("parse: a table's source", blocks[7].source == "| File | Change |\n| --- | --- |\n| `a.sh` | Fixed the typo. |")
check("parse: a link stays in its paragraph", blocks[8].kind == "paragraph")
check("parse: a rule", blocks[9].kind == "rule")
check("parse: every block has its source", (function()
  for _, b in ipairs(blocks) do if type(b.source) ~= "string" or b.source == "" then return false end end
  return true
end)())
check("parse: nothing, no blocks", #planblocks.parse("") == 0)
check("parse: CRLF like LF", same(planblocks.parse(SAMPLE:gsub("\n", "\r\n")), blocks))

-- The file map: a Files list or a table with a file column, one row per file.
local function lifted(text) return planblocks.lift(planblocks.parse(text)) end
local function only(text, kind)
  local found
  for _, b in ipairs(lifted(text)) do if b.kind == kind then found = b end end
  return found
end
local function rows(block)
  local out = {}
  for _, r in ipairs(block and block.rows or {}) do out[#out + 1] = { r.path, r.badge or false, r.note } end
  return out
end
local list = only("## Files\n\n- Create: `bin/x.sh`\n- Modify: `README.md` — the flag", "filemap")
check("file map: a Files list", same(rows(list), { { "bin/x.sh", "new", "" }, { "README.md", "edit", "the flag" } }))
check("file map: under its heading, it needs no label", list and list.titled == true)
check("file map: its source", list and list.source == "- Create: `bin/x.sh`\n- Modify: `README.md` — the flag")
check("file map: a **Files:** line", same(rows(only("**Files:**\n- `a/b.lua` (new)", "filemap")), { { "a/b.lua", "new", "" } }))
local tableMap = only("| File | Change |\n|---|---|\n| `bin/deskmates` | edit: add the flag |", "filemap")
check("file map: a file table", same(rows(tableMap), { { "bin/deskmates", "edit", "add the flag" } }))
check("file map: a table anywhere gets a label", tableMap and not tableMap.titled)
check("file map: a path with its lines", same(rows(only("## Files\n\n- Modify: `tests/a.lua:12-30`", "filemap")),
  { { "tests/a.lua:12-30", "edit", "" } }))
check("file map: an item with no path stays a list", only("## Files\n\n- `a.sh`\n- No other files change.", "list") ~= nil
  and only("## Files\n\n- `a.sh`\n- No other files change.", "filemap") == nil)
check("file map: a code span that is no path stays a list", only("## Files\n\n- `run the tests`", "filemap") == nil)
check("file map: a list under another heading stays a list", only("## Steps\n\n- `a.sh`", "filemap") == nil)
check("file map: a table with no file column stays a table", only("| Name | Type |\n|---|---|\n| `a.sh` | edit |", "filemap") == nil)
check("file map: no badge word, no badge", same(rows(only("## Files\n\n- `a.sh` the helper", "filemap")), { { "a.sh", false, "the helper" } }))
check("file map: a word that is no badge stays in the note", same(rows(only("## Files\n\n- Test: `tests/x_test.lua`", "filemap")),
  { { "tests/x_test.lua", false, "Test" } }))
check("file map: what is not lifted is left as it was", same(lifted("# T\n\ntext"), planblocks.parse("# T\n\ntext")))

-- Endpoint rows: a method, a path, maybe a status.
local function ep(line)
  local e = planblocks.endpoint(line)
  return e and { e.method, e.path, e.status or false, e.note }
end
check("endpoint: method, path, status", same(ep("POST /api/posts/{id}/comments → 201"), { "POST", "/api/posts/{id}/comments", "201", "" }))
check("endpoint: in backticks, ascii arrow, a note", same(ep("`GET /api/posts` -> 200 — lists them"), { "GET", "/api/posts", "200", "lists them" }))
check("endpoint: no status", same(ep("DELETE /api/x"), { "DELETE", "/api/x", false, "" }))
check("endpoint: look-alikes stay text", ep("We GET /x later") == nil and ep("POST the form") == nil and ep("get /x") == nil)
check("endpoint: a status that is not three digits is a note", same(ep("POST /x → 20"), { "POST", "/x", false, "→ 20" }))
local eps = only("- POST /a → 201\n- GET /a", "endpoints")
check("endpoints: a list of them", eps ~= nil and #eps.rows == 2 and eps.rows[1].method == "POST" and eps.rows[2].path == "/a")
check("endpoints: a paragraph of them", only("PUT /a → 200\nPATCH /a", "endpoints") ~= nil)
check("endpoints: a mixed list stays a list", only("- POST /a\n- then deploy", "endpoints") == nil and only("- POST /a\n- then deploy", "list") ~= nil)

-- Review fixes: nothing in a file row is lost, and a badge only where the text says so.
check("file map: a file cell with more than its path stays a table",
  only("| File | Change |\n|---|---|\n| `a.lua` (new), `b.lua` | parser |", "filemap") == nil)
check("file map: a badge in brackets in the file cell is still read",
  same(rows(only("| File | Change |\n|---|---|\n| `a.lua` (new) | parser |", "filemap")), { { "a.lua", "new", "parser" } }))
check("file map: a verb that starts a sentence is no badge",
  same(rows(only("| File | Change |\n|---|---|\n| `a.lua` | Add a retry flag |", "filemap")), { { "a.lua", false, "Add a retry flag" } }))
check("file map: a verb in a list item is no badge",
  same(rows(only("## Files\n\n- Add tests to `a_test.lua`", "filemap")), { { "a_test.lua", false, "Add tests to" } }))
check("file map: a word joined by a hyphen is no badge",
  same(rows(only("## Files\n\n- Add-on: `a.lua`", "filemap")), { { "a.lua", false, "Add-on" } }))
check("file map: a badge alone in its cell", same(rows(only("| Path | What |\n|---|---|\n| `a/b.sh` | new |", "filemap")),
  { { "a/b.sh", "new", "" } }))

check.done("plan blocks")
