-- The plan card's blocks: a plan's markdown read into blocks of raw text (headings, paragraphs, lists, code,
-- quotes, tables, rules), and the blocks lifted from them. Nothing here is escaped or drawn: ui/plancard.lua
-- does that. It knows no Hammerspoon.

local planblocks = {}

local function trim(text) return (text:match("^%s*(.-)%s*$")) end

local function isItem(line) return line:match("^%s*[-*+]%s") or line:match("^%s*%d+[.)]%s") end

local function cells(line)
  local out = {}
  line = line:gsub("^%s*|", ""):gsub("|%s*$", "")
  for cell in (line .. "|"):gmatch("([^|]*)|") do out[#out + 1] = trim(cell) end
  return out
end

-- Every block is a table with `kind`, its fields, and `source`: its lines as written.
function planblocks.parse(text)
  local blocks, lines, i = {}, {}, 1
  for line in (text:gsub("\r\n", "\n") .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
  if text == "" then lines = {} end
  local function add(block, first, last)
    block.source = table.concat(lines, "\n", first, math.min(last, #lines))
    blocks[#blocks + 1] = block
  end
  while i <= #lines do
    local line, first = lines[i], i
    if line:match("^%s*```") then
      local code = {}
      local lang = trim(line:match("^%s*```(.*)$"))
      i = i + 1
      while i <= #lines and not lines[i]:match("^%s*```") do code[#code + 1] = lines[i]; i = i + 1 end
      add({ kind = "code", lang = lang, lines = code }, first, i)
      i = i + 1
    elseif line:match("^%s*$") then
      i = i + 1
    elseif line:match("^#+%s") then
      local marks, title = line:match("^(#+)%s+(.-)%s*#*%s*$")
      add({ kind = "heading", level = math.min(#marks, 6), text = title }, i, i)
      i = i + 1
    elseif line:match("^%s*[-*_]%s*[-*_]%s*[-*_][-*_%s]*$") then
      add({ kind = "rule" }, i, i)
      i = i + 1
    elseif line:match("^%s*>") then
      local quote = {}
      while i <= #lines and lines[i]:match("^%s*>") do quote[#quote + 1] = (lines[i]:gsub("^%s*>%s?", "")); i = i + 1 end
      add({ kind = "quote", lines = quote }, first, i - 1)
    elseif line:match("^%s*|") then
      local rows = {}
      while i <= #lines and lines[i]:match("^%s*|") do
        if not lines[i]:match("^[%s|:-]+$") then rows[#rows + 1] = cells(lines[i]) end
        i = i + 1
      end
      add({ kind = "table", rows = rows }, first, i - 1)
    elseif isItem(line) then
      local items = {}
      while i <= #lines and isItem(lines[i]) do
        items[#items + 1] = lines[i]:match("^%s*[-*+]%s+(.*)$") or lines[i]:match("^%s*%d+[.)]%s+(.*)$")
        i = i + 1
      end
      add({ kind = "list", ordered = line:match("^%s*%d") ~= nil, items = items }, first, i - 1)
    else
      local para = {}
      while i <= #lines and not lines[i]:match("^%s*$") and not lines[i]:match("^#+%s") and not lines[i]:match("^%s*```")
        and not isItem(lines[i]) and not lines[i]:match("^%s*[>|]") do
        para[#para + 1] = trim(lines[i])
        i = i + 1
      end
      add({ kind = "paragraph", lines = para }, first, i - 1)
    end
  end
  return blocks
end

return planblocks
