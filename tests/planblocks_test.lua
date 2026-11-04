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

check.done("plan blocks")
